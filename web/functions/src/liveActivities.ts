/**
 * The group plan Live Activity, run by the server (1.1):
 * - starts it on each phone at its chosen lead time before the meet time
 *   (ActivityKit push-to-start, iOS 17.2+), for decided plans with a time;
 * - updates it with friends' "On my way" arrival times;
 * - ends it with a dismissal date, so it goes away on time even if the app
 *   never opens: at the meet time, 30 min or 1 hour after, or when you
 *   arrive ("When I arrive", falling back to 30 min after);
 * - ends it right away when the plan is reopened, ended, or you leave.
 *
 * Per phone, per plan: sessions/{id}/devices/{uid} (written by the app, see
 * GroupService.saveDevice). The server keeps laStartedFor / laEndedFor there
 * (the meet time, in ms, it started / ended an activity for).
 *
 * Content-state and attributes must match GroupPlanAttributes in
 * Shared/Activity/GroupPlanAttributes.swift.
 */
import { bumpStat } from "./stats";
import { FieldValue, Timestamp, getFirestore, type DocumentData, type DocumentReference,
  type QueryDocumentSnapshot } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { sendLiveActivity, swiftDate, type ApnsEnv } from "./apns";

const MIN = 60 * 1000;
const HOUR = 60 * MIN;

function db() { return getFirestore(); }

function millis(value: unknown): number | undefined {
  if (value instanceof Timestamp) return value.toMillis();
  if (value && typeof (value as Timestamp).toMillis === "function") return (value as Timestamp).toMillis();
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function envOf(device: DocumentData): ApnsEnv {
  return device.apnsEnv === "sandbox" ? "sandbox" : "production";
}

/** How long after the meet time it stays ("Remove from Lock Screen"). */
export function lingerMs(removeWhen: unknown): number {
  switch (removeWhen) {
    case "meet": return 0;
    case "after60": return HOUR;
    default: return 30 * MIN;   // after30, and "arrive" when nobody arrived
  }
}

function leadMs(device: DocumentData): number {
  const minutes = typeof device.leadMinutes === "number" ? device.leadMinutes : 120;
  return Math.min(480, Math.max(60, minutes)) * MIN;
}

/** The meet time this phone has a countdown for, if any. */
function activityMeet(device: DocumentData): number | undefined {
  return millis(device.laStartedFor) ?? millis(device.activityMeet);
}

function hasActivityFor(device: DocumentData, meet: number): boolean {
  return millis(device.laStartedFor) === meet || millis(device.activityMeet) === meet;
}

export interface Arrival { uid: string; name: string; etaMs?: number; status: string; }

/** Everyone's "On my way" (eta docs), oldest first. */
export async function arrivals(sessionRef: DocumentReference): Promise<Arrival[]> {
  const snap = await sessionRef.collection("eta").get();
  return snap.docs.map((d) => {
    const e = d.data();
    return {
      uid: d.id,
      name: typeof e.name === "string" && e.name.trim() ? e.name.trim() : "Someone",
      etaMs: millis(e.eta),
      status: ["onTheWay", "late", "arrived"].includes(e.status) ? e.status : "onTheWay",
      leftMs: millis(e.leftAt) ?? 0,
    };
  }).sort((a, b) => a.leftMs - b.leftMs).map(({ uid, name, etaMs, status }) => ({ uid, name, etaMs, status }));
}

/** The table: who's expected (everyone in the plan except people who RSVP'd no). */
export async function expectedPeople(sessionRef: DocumentReference): Promise<string[]> {
  const [members, rsvps] = await Promise.all([sessionRef.collection("members").get(), sessionRef.collection("rsvps").get()]);
  const declined = new Set(rsvps.docs.filter((d) => d.get("going") === false).map((d) => d.id));
  return members.docs.map((d) => d.id).filter((id) => !declined.has(id));
}

export interface TableState {
  /// This phone's own "On my way" status.
  myStatus?: string;
  expected?: number;
  allHere?: boolean;
}

/** GroupPlanAttributes.ContentState for this phone. */
export function contentState(meet: number, device: DocumentData, others: Arrival[], table: TableState = {}): Record<string, unknown> {
  // This phone's own leave-by, if it worked one out for this meet time.
  const planMeet = millis(device.planMeet);
  const leaveAt = planMeet === meet ? millis(device.leaveAt) : undefined;
  const travel = planMeet === meet && typeof device.travelMinutes === "number" ? Math.max(0, Math.round(device.travelMinutes)) : 0;
  const state: Record<string, unknown> = {
    meetTime: swiftDate(meet),
    leaveAt: swiftDate(leaveAt !== undefined && travel > 0 ? leaveAt : meet),
    travelMinutes: leaveAt !== undefined ? travel : 0,
  };
  if (others.length) {
    state.arrivals = others.slice(0, 8).map((a) => ({
      name: a.name.slice(0, 40),
      ...(a.etaMs !== undefined ? { eta: swiftDate(a.etaMs) } : {}),
      status: a.status,
    }));
  }
  if (table.myStatus) state.myStatus = table.myStatus;
  if (table.expected !== undefined && table.expected > 0) state.expected = table.expected;
  if (table.allHere) state.allHere = true;
  return state;
}

/** For one phone: its own status, and the table's size. */
function tableFor(uid: string, all: Arrival[], expected: string[]): TableState {
  return { myStatus: all.find((a) => a.uid === uid)?.status, expected: expected.length };
}

/** When the system should redraw (UNIX seconds): leave-by, then the meet time. */
function staleDate(meet: number, device: DocumentData, now: number): number {
  const leave = millis(device.planMeet) === meet ? millis(device.leaveAt) : undefined;
  if (leave !== undefined && leave > now) return Math.floor(leave / 1000);
  return Math.floor((meet > now ? meet : meet + lingerMs(device.removeWhen)) / 1000);
}

function winnerName(session: DocumentData): string {
  const options: unknown = session.options;
  if (Array.isArray(options)) {
    const match = options.find((o) => o && o.id === session.winnerID);
    if (match && typeof match.name === "string" && match.name.trim()) return match.name;
  }
  return "The plan";
}

async function forgetToken(ref: DocumentReference, field: "startToken" | "updateToken", token: string) {
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.get(field) === token) tx.update(ref, { [field]: FieldValue.delete() });
  }).catch((err) => logger.warn("Couldn't remove a dead Live Activity token", { path: ref.path, err: String(err) }));
}

/** Claims a step for this meet time, once (two runs never both send it). */
async function claim(ref: DocumentReference, field: "laStartedFor" | "laEndedFor", meet: number): Promise<boolean> {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || millis(snap.get(field)) === meet) return false;
    tx.update(ref, { [field]: meet });
    return true;
  });
}

// MARK: - Start / update / end one phone

async function start(sessionDoc: QueryDocumentSnapshot, session: DocumentData, meet: number,
  device: QueryDocumentSnapshot, others: Arrival[], now: number, table: TableState = {}): Promise<void> {
  const d = device.data();
  const token = d.startToken as string;
  if (!(await claim(device.ref, "laStartedFor", meet))) return;
  const place = winnerName(session);
  const label = typeof session.meetTimeLabel === "string" ? session.meetTimeLabel : "";
  const title = typeof session.title === "string" && session.title.trim() ? session.title.trim().slice(0, 60) : "Group plan";
  const result = await sendLiveActivity(token, envOf(d), {
    aps: {
      timestamp: Math.floor(now / 1000),
      event: "start",
      "content-state": contentState(meet, d, others, table),
      "attributes-type": "GroupPlanAttributes",
      attributes: { sessionID: sessionDoc.id, title, place },
      "stale-date": staleDate(meet, d, now),
      "relevance-score": 100,
      // Quiet: shows the countdown with a banner, no sound.
      alert: { title: place, body: label ? `${label} · Your countdown is on the Lock Screen` : "Your countdown is on the Lock Screen" },
    },
  });
  if (result.dead) await forgetToken(device.ref, "startToken", token);
  if (!result.ok && !result.dead) {
    // Try again next run, but not forever (a setup problem would retry every 5 minutes).
    const fails = millis(d.laStartFailsFor) === meet && typeof d.laStartFails === "number" ? d.laStartFails + 1 : 1;
    await device.ref.update(fails >= 3
      ? { laStartFails: fails, laStartFailsFor: meet }
      : { laStartedFor: FieldValue.delete(), laStartFails: fails, laStartFailsFor: meet }).catch(() => {});
  }
  if (result.ok) await bumpStat("countdownsStarted");
  logger.info("Live Activity start", { sessionId: sessionDoc.id, uid: device.id, ok: result.ok });
}

/** Ends this phone's countdown: gone at `dismissAt` (ms; now = right away). */
export async function endFor(sessionId: string, deviceRef: DocumentReference, d: DocumentData,
  meet: number | undefined, dismissAt: number, now = Date.now(),
  finalState?: Record<string, unknown>): Promise<void> {
  const token = typeof d.updateToken === "string" ? d.updateToken : undefined;
  if (meet !== undefined && !(await claim(deviceRef, "laEndedFor", meet).catch(() => false))) return;
  if (!token) return;  // Without its token, the app's own timers and the stale date take it down.
  const result = await sendLiveActivity(token, envOf(d), {
    aps: {
      timestamp: Math.floor(now / 1000),
      event: "end",
      "dismissal-date": Math.floor(Math.max(now, dismissAt) / 1000),
      ...(finalState ? { "content-state": finalState }
        : meet !== undefined ? { "content-state": contentState(meet, d, []) } : {}),
    },
  });
  if (result.dead) await forgetToken(deviceRef, "updateToken", token);
  logger.info("Live Activity end", { sessionId, uid: deviceRef.id, ok: result.ok });
}

/** Sends the new state (friends' arrival times, a new meet time) to everyone with a countdown. */
export async function updateAll(sessionRef: DocumentReference, meet: number, opts: { quiet: boolean; except?: string }): Promise<void> {
  const [devices, all, expected] = await Promise.all([
    sessionRef.collection("devices").get(), arrivals(sessionRef), expectedPeople(sessionRef)]);
  const now = Date.now();
  await Promise.all(devices.docs.map(async (device) => {
    const d = device.data();
    if (device.id === opts.except || typeof d.updateToken !== "string") return;
    if (!hasActivityFor(d, meet) || millis(d.laEndedFor) === meet) return;
    const others = all.filter((a) => a.uid !== device.id);
    const result = await sendLiveActivity(d.updateToken, envOf(d), {
      aps: {
        timestamp: Math.floor(now / 1000),
        event: "update",
        "content-state": contentState(meet, d, others, tableFor(device.id, all, expected)),
        "stale-date": staleDate(meet, d, now),
      },
    }, { priority: opts.quiet ? 5 : 10 });
    if (result.dead) await forgetToken(device.ref, "updateToken", d.updateToken);
  }));
}

// MARK: - The scheduled run (every 5 minutes, in releaseHeldResults)

export async function liveActivityTick(): Promise<void> {
  const now = Date.now();
  const due = await db().collection("sessions")
    .where("meetTime", ">", Timestamp.fromMillis(now - 6 * HOUR))
    .where("meetTime", "<=", Timestamp.fromMillis(now + 8 * HOUR + 10 * MIN))
    .get();
  for (const sessionDoc of due.docs) {
    try {
      const session = sessionDoc.data();
      const meet = millis(session.meetTime);
      if (meet === undefined) continue;
      // "On my way" times are deleted once the plan is well over.
      if (meet < now - 2 * HOUR) { await deleteArrivals(sessionDoc.ref); continue; }
      if (session.status !== "decided" || session.announced === false || !session.winnerID) continue;
      const devices = await sessionDoc.ref.collection("devices").get();
      if (devices.empty) continue;
      const [all, expected] = await Promise.all([arrivals(sessionDoc.ref), expectedPeople(sessionDoc.ref)]);
      for (const device of devices.docs) {
        const d = device.data();
        const others = all.filter((a) => a.uid !== device.id);
        if (hasActivityFor(d, meet)) {
          if (millis(d.laEndedFor) === meet) continue;
          // End a few minutes early with the exact dismissal date (this runs every 5 minutes).
          const removeAt = meet + lingerMs(d.removeWhen);
          if (now >= removeAt - 6 * MIN) await endFor(sessionDoc.id, device.ref, d, meet, removeAt, now);
          continue;
        }
        if (d.countdownOn === false || typeof d.startToken !== "string" || millis(d.laEndedFor) === meet) continue;
        if (session.everyoneHereAt) continue;   // Everyone's already at the table.
        if (now >= meet || now < meet - leadMs(d)) continue;
        // Still in the group (left, or removed when it ended).
        if (!(await sessionDoc.ref.collection("members").doc(device.id).get()).exists) continue;
        await start(sessionDoc, session, meet, device, others, now, tableFor(device.id, all, expected));
      }
    } catch (err) {
      logger.error("liveActivityTick: plan failed", { sessionId: sessionDoc.id, err: String(err) });
    }
  }
}

export async function deleteArrivals(sessionRef: DocumentReference): Promise<void> {
  const snap = await sessionRef.collection("eta").get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

// MARK: - Plan changes

/** Reopened, a new place, or ended: every countdown goes now, and can start fresh later. */
export async function endAllNow(sessionRef: DocumentReference): Promise<void> {
  const devices = await sessionRef.collection("devices").get();
  const now = Date.now();
  await Promise.all(devices.docs.map(async (device) => {
    const d = device.data();
    const meet = activityMeet(d);
    if (meet !== undefined && millis(d.laEndedFor) !== meet) {
      await endFor(sessionRef.id, device.ref, d, undefined, now, now);
    }
    await device.ref.update({
      laStartedFor: FieldValue.delete(), laEndedFor: FieldValue.delete(), activityMeet: FieldValue.delete(),
    }).catch(() => {});
  }));
}

/**
 * The plan was ended (its doc deleted). Devices docs are private (the
 * creator's app can't list them), so the server ends any countdowns and
 * deletes them, plus any arrival times left behind.
 */
export async function planDeleted(sessionRef: DocumentReference): Promise<void> {
  const devices = await sessionRef.collection("devices").get();
  const now = Date.now();
  await Promise.all(devices.docs.map(async (device) => {
    const d = device.data();
    const meet = activityMeet(d);
    if (meet !== undefined && millis(d.laEndedFor) !== meet) {
      // Mark it ended first, so the delete below doesn't send a second end push.
      await device.ref.update({ laEndedFor: meet }).catch(() => {});
      await endFor(sessionRef.id, device.ref, d, undefined, now, now);
    }
    await device.ref.delete().catch(() => {});
  }));
  await deleteArrivals(sessionRef);
}

/** Everyone's here: each countdown shows "All 4 here ✓" for a minute, then goes. */
export const ALL_HERE_LINGER_MS = 60 * 1000;

export async function everyoneHere(sessionRef: DocumentReference, meet: number, expected: string[]): Promise<void> {
  const [devices, all] = await Promise.all([sessionRef.collection("devices").get(), arrivals(sessionRef)]);
  const now = Date.now();
  await Promise.all(devices.docs.map(async (device) => {
    const d = device.data();
    if (!hasActivityFor(d, meet) || millis(d.laEndedFor) === meet) return;
    const others = all.filter((a) => a.uid !== device.id);
    const final = contentState(meet, d, others, { ...tableFor(device.id, all, expected), allHere: true });
    await endFor(sessionRef.id, device.ref, d, meet, now + ALL_HERE_LINGER_MS, now, final);
  }));
}

/** The meet time moved: countdowns already up follow it. */
export async function meetTimeChanged(sessionRef: DocumentReference, oldMeet: number, newMeet: number): Promise<void> {
  const devices = await sessionRef.collection("devices").get();
  const moved = devices.docs.filter((d) => hasActivityFor(d.data(), oldMeet) && millis(d.get("laEndedFor")) !== oldMeet);
  await Promise.all(moved.map((d) => d.ref.update({ laStartedFor: newMeet, laEndedFor: FieldValue.delete() })));
  if (moved.length) await updateAll(sessionRef, newMeet, { quiet: false });
}
