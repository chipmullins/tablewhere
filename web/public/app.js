// Tablewhere web vote page: https://<host>/v/<sessionId>
// Same Firestore data as the app and iMessage extension.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth, signInAnonymously, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import {
  getFirestore, doc, collection, onSnapshot, setDoc, deleteDoc, serverTimestamp, runTransaction, increment
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";

const $ = (id) => document.getElementById(id);
const sections = ["loading", "error", "name-step", "vote-step", "decided-step"];

function show(id) {
  sections.forEach((s) => { $(s).hidden = s !== id; });
}

$("error-retry")?.addEventListener("click", () => location.reload());

function fail(message, canRetry = false) {
  $("error-text").textContent = message;
  const retry = $("error-retry");
  if (retry) retry.hidden = !canRetry;
  show("error");
}

// Same palette as the app's monogram tiles, chosen by a stable hash of the name.
const TILES = [
  ["#3A2914", "#FFB23F"], ["#3A1A1A", "#FF8A7A"], ["#3A1620", "#FF7A93"],
  ["#1D2A1A", "#9BE08A"], ["#332A10", "#FFD25E"], ["#2A2233", "#D7B8FF"], ["#1B2433", "#8FB4FF"]
];
function tileColors(name) {
  let h = 0;
  for (const ch of name) h = ((h * 31) + ch.codePointAt(0)) & 0x7fffffff;
  return TILES[h % TILES.length];
}

function formatCode(code) {
  return code && code.length === 6 ? `${code.slice(0, 3)}·${code.slice(3)}` : code || "";
}

// "7:00 PM" today, "tomorrow at 7:00 PM", or "Sat at 7:00 PM" (same as the app).
function formatTime(ts) {
  if (!ts) return null;
  const date = ts.toDate ? ts.toDate() : new Date(ts);
  const time = date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  const startOf = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((startOf(date) - startOf(new Date())) / 86400000);
  if (days <= 0) return `at ${time}`;
  if (days === 1) return `tomorrow at ${time}`;
  if (days <= 6) return `${date.toLocaleDateString([], { weekday: "short" })} at ${time}`;
  // A week or more out (plans made ahead): "Sat, Nov 14 at 7:00 PM".
  return `${date.toLocaleDateString([], { weekday: "short", month: "short", day: "numeric" })} at ${time}`;
}

// ---------------------------------------------------------------------------
// Group blacklist: app users share their blacklisted places, scrambled per
// group (SHA-256 of "<sessionId>|<placeId>", first 8 bytes as hex; same as
// GroupBlacklist.hash in the app). Places anyone blocked are "ruled out":
// shown, but they can't win and can't be voted for or added.
const hashCache = new Map();
async function blockedHash(placeId) {
  const key = `${sessionId}|${placeId}`;
  if (!hashCache.has(key)) {
    const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key)));
    hashCache.set(key, [...bytes.slice(0, 8)].map((b) => b.toString(16).padStart(2, "0")).join(""));
  }
  return hashCache.get(key);
}
function groupBlocked() {
  return new Set(members.flatMap((m) => Array.isArray(m.blockedHashes) ? m.blockedHashes : []));
}
let ruledOut = new Set();
let everythingRuledOut = false;

// A timed vote whose time is up (it stays "open" until the creator locks it in).
function isTimeUp() {
  const closes = session?.closesAt?.toDate ? session.closesAt.toDate() : null;
  return !!closes && session.status === "open" && closes <= Date.now();
}
function acceptsChanges() { return session.status === "open" && !isTimeUp(); }
async function refreshRuledOut() {
  if (!globalThis.crypto?.subtle) return;  // only on https; the live page always is
  const blocked = groupBlocked();
  const next = new Set();
  if (blocked.size && session) {
    for (const o of session.options || []) {
      if (blocked.has(await blockedHash(o.id))) next.add(o.id);
    }
  }
  // If someone has every place blacklisted, they all count again.
  const all = next.size > 0 && next.size === (session.options || []).length;
  const effective = all ? new Set() : next;
  const changed = all !== everythingRuledOut || effective.size !== ruledOut.size
    || [...effective].some((id) => !ruledOut.has(id));
  ruledOut = effective;
  everythingRuledOut = all;
  if (changed) render();
}

const sessionId = (location.pathname.match(/^\/v\/([^/]+)/) || [])[1];
if (!sessionId) {
  fail("This link is missing part of its address. Ask whoever sent it to share it again.");
  throw new Error("No session id");
}

// Loaded dynamically so a missing config shows a message instead of hanging on "Loading…".
let firebaseConfig;
try {
  ({ firebaseConfig } = await import("./firebase-config.js"));
} catch {
  fail("This page isn’t set up yet. (Missing firebase-config.js — see the README.)");
  throw new Error("Missing firebase-config.js");
}

// Optional: the MapKit JS token for "Suggest a place" (web/tools/make-mapkit-token.mjs).
// Without it, friends on the web can still vote; they just can't add places.
let mapkitToken = null;
try {
  ({ mapkitToken } = await import("./mapkit-token.js"));
} catch { /* no token yet */ }

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const sessionRef = doc(db, "sessions", sessionId);

let uid = null;
let session = null;
let votes = [];
let members = [];
let rsvps = [];
let busy = false;
// An RSVP tapped before we knew your name: sent once you've typed it.
let pendingRSVP = null;
const NAME_KEY = "forkroad.name";
let membersLoaded = false;

// localStorage throws in some private / cookies-blocked browsers; fall back to memory.
const memoryStore = new Map();
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return memoryStore.get(k) ?? null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { memoryStore.set(k, v); } },
  remove(k) { try { localStorage.removeItem(k); } catch { /* ignore */ } memoryStore.delete(k); },
};

onAuthStateChanged(auth, (user) => {
  if (user) { uid = user.uid; start(); }
});
signInAnonymously(auth).catch(() => fail("Couldn’t connect. Check your connection and try again.", true));

// Anonymous daily counts for the stats page (stats/{yyyy-mm-dd}, UTC): one
// number per thing per day, nothing about who. Same as UsageStats in the app.
function bumpStat(field) {
  const day = new Date().toISOString().slice(0, 10);
  setDoc(doc(db, "stats", day), { [field]: increment(1) }, { merge: true }).catch(() => {});
}
function countVisitOncePerDay() {
  const day = new Date().toISOString().slice(0, 10);
  try {
    if (localStorage.getItem("forkroad.visitDay") === day) return;
    localStorage.setItem("forkroad.visitDay", day);
  } catch { /* private mode: count anyway */ }
  bumpStat("webVisitors");
}

let started = false;
function start() {
  if (started) return;
  started = true;
  countVisitOncePerDay();

  onSnapshot(sessionRef, (snap) => {
    if (!snap.exists()) return fail("This group plan has ended. Whoever started it ended it, or it no longer exists.");
    session = snap.data();
    render();
    refreshRuledOut();
  }, () => fail("Couldn’t load this plan. Check your connection and try again.", true));

  onSnapshot(collection(sessionRef, "votes"), (snap) => {
    votes = snap.docs.map((d) => d.data());
    render();
  });

  onSnapshot(collection(sessionRef, "rsvps"), (snap) => {
    rsvps = snap.docs.map((d) => d.data());
    render();
  }, () => {});

  $("rsvp-in").addEventListener("click", () => {
    const mine = rsvps.find((r) => r.userID === uid);
    answerRSVP(true, mine?.going ? mine.guests || 0 : 0);
  });
  $("rsvp-out").addEventListener("click", () => answerRSVP(false, 0));
  $("guests-minus").addEventListener("click", () => {
    const mine = rsvps.find((r) => r.userID === uid);
    answerRSVP(true, Math.max(0, (mine?.guests || 0) - 1));
  });
  $("guests-plus").addEventListener("click", () => {
    const mine = rsvps.find((r) => r.userID === uid);
    answerRSVP(true, Math.min(MAX_GUESTS, (mine?.guests || 0) + 1));
  });
  $("calendar").addEventListener("click", downloadCalendar);

  onSnapshot(collection(sessionRef, "members"), (snap) => {
    members = snap.docs.map((d) => d.data());
    membersLoaded = true;
    render();
    refreshRuledOut();
  }, () => { membersLoaded = true; render(); });

  $("name-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const name = $("name-input").value.trim().slice(0, 30);
    if (!name) return;
    store.set(NAME_KEY, name);
    // You join the group when you vote, add a pick, or RSVP (just looking
    // doesn't put you on the "waiting on" list). A rename updates it now.
    if (members.some((m) => m.id === uid)) await join(name);
    else store.remove(sessionNameKey());
    render();
  });

  // "Not you? Change name": back to the name step (a shared phone, a typo).
  $("change-name").addEventListener("click", () => {
    store.remove(NAME_KEY);
    store.remove(sessionNameKey());
    $("name-input").value = "";
    render();
    $("name-input").focus();
  });
}

function sessionNameKey() { return `forkroad.name.${sessionId}`; }

// Two Sams in one group become "Sam" and "Sam 2" (same as the app).
function uniqueName(name) {
  const taken = new Set(members.filter((m) => m.id !== uid).map((m) => String(m.name || "").toLowerCase()));
  if (!taken.has(name.toLowerCase())) return name;
  for (let n = 2; n <= 20; n++) {
    if (!taken.has(`${name} ${n}`.toLowerCase())) return `${name} ${n}`;
  }
  return name;
}

/** Join the group the first time you do something (vote, add a pick, RSVP). */
async function ensureJoined() {
  if (members.some((m) => m.id === uid)) return;
  const name = myName();
  if (name) await join(name);
}

async function join(name) {
  const unique = uniqueName(name);
  store.set(sessionNameKey(), unique);
  await setDoc(doc(sessionRef, "members", uid), { id: uid, name: unique, joinedAt: serverTimestamp() }, { merge: true });
  // Changed your name after voting: your vote shows the new one too.
  if (votes.some((v) => v.voterID === uid)) {
    await setDoc(doc(sessionRef, "votes", uid), { voterName: unique }, { merge: true }).catch(() => {});
  }
}

function myName() {
  return store.get(sessionNameKey()) || store.get(NAME_KEY);
}

// MARK: Spin reveal
// Someone watching an open spin sees the wheel land, like in the app. Someone
// opening the link afterward gets a quick version, once per device (reopening
// the link later goes straight to the result).
let sawUndecided = false;   // this page has shown the plan before it was decided
let revealedFor = null;     // the winner we already played (or skipped) the reveal for
let revealing = false;

function revealKey() { return `forkroad.revealed.${sessionId}.${session.winnerID}`; }

function shouldReveal() {
  if (!isSpin() || revealing || revealedFor === session.winnerID || (session.options || []).length < 2) return false;
  return sawUndecided || !store.get(revealKey());
}

/** `quick`: opened after the spin, so a short version (about 2.5 seconds). */
function playReveal(quick = false) {
  revealing = true;
  const winnerId = session.winnerID;
  store.set(revealKey(), "1");
  const winner = (session.options || []).find((o) => o.id === winnerId);
  const pool = (session.options || []).filter((o) => !ruledOut.has(o.id)).map((o) => o.name);
  const names = pool.length > 1 ? pool : (session.options || []).map((o) => o.name);
  const reduce = window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches;

  const overlay = document.createElement("div");
  overlay.className = "reveal";
  overlay.setAttribute("role", "dialog");
  overlay.setAttribute("aria-live", "assertive");
  overlay.setAttribute("aria-label", "Spinning");
  overlay.innerHTML = `<div><div class="icon" aria-hidden="true">✨</div><div class="label">SPINNING…</div>`
    + `<div class="name"></div><div class="skip">Tap to skip</div></div>`;
  document.body.append(overlay);
  const nameBox = overlay.querySelector(".name");
  const showName = (text, ms) => {
    const span = document.createElement("span");
    span.textContent = text;
    // Slides in about as fast as the wheel is turning (like the app).
    if (ms) span.style.animationDuration = `${Math.min(220, Math.round(ms * 0.7))}ms`;
    nameBox.replaceChildren(span);
  };

  let finished = false;
  const finish = () => {
    if (finished) return;
    finished = true;
    overlay.remove();
    revealing = false;
    revealedFor = winnerId;
    render();
  };
  overlay.addEventListener("click", finish);

  const land = () => {
    if (finished) return;
    overlay.classList.add("landed");
    overlay.querySelector(".icon").textContent = "🎉";
    overlay.querySelector(".label").textContent = "THE WHEEL PICKED";
    overlay.setAttribute("aria-label", `The wheel picked ${winner ? winner.name : "a place"}`);
    showName(winner ? winner.name : "");
    if (navigator.vibrate) navigator.vibrate(30);
    setTimeout(finish, quick ? 1400 : 2000);
  };

  if (reduce || names.length < 2) { land(); return; }
  // Live: the app's pacing, 20 steps easing out (about 8 seconds).
  // Quick: 8 faster steps (about 1 second), then the landing.
  const steps = quick ? 8 : 20;
  const growth = quick ? 1.25 : 1.17;
  let index = Math.floor(Math.random() * names.length);
  let delay = quick ? 50 : 60;
  let step = 0;
  const tick = () => {
    if (finished) return;
    if (step++ >= steps) { land(); return; }
    index = (index + 1) % names.length;
    showName(names[index], delay);
    setTimeout(tick, delay);
    delay *= growth;
  };
  tick();
}

// A live update rebuilds the place buttons. While a finger is on one, wait,
// so a tap in a busy group doesn't land on a button that just got replaced.
let pressing = false;
let renderWaiting = false;
document.addEventListener("pointerdown", (e) => {
  if (e.target.closest && e.target.closest("#options")) pressing = true;
}, true);
const endPress = () => {
  if (!pressing) return;
  pressing = false;
  // After the click has fired on the button that was pressed.
  if (renderWaiting) setTimeout(() => { renderWaiting = false; render(); }, 0);
};
document.addEventListener("pointerup", endPress, true);
document.addEventListener("pointercancel", endPress, true);

// The browser tab (not the link preview, which never changes once sent).
function updateTabTitle() {
  const decided = session.status === "decided" && session.winnerID && session.announced !== false;
  const stage = decided ? "Results" : isPlan() ? "Plan" : isSpin() ? "Spin" : "Vote";
  document.title = `Tablewhere · ${stage}`;
}

function render() {
  if (!session) return;
  updateTabTitle();
  if (pressing) { renderWaiting = true; return; }
  $("code").textContent = formatCode(session.joinCode);
  $("footer").hidden = false;

  // The organizer has the result but hasn't shared it yet (watching the spin,
  // or setting the time in iMessage): show the places, locked, for a moment.
  const held = session.status === "decided" && session.announced === false;

  // Anyone opening the link after the group decided sees the result right away.
  if (session.status === "decided" && session.winnerID && !held) {
    // Watching when the spin landed: play the wheel first (the places stay behind it).
    if (shouldReveal()) { playReveal(!sawUndecided); return; }
    if (revealing) return;
    // Tapped I'm in / Can't make it without a name yet: ask for it first.
    if (pendingRSVP && !myName()) {
      $("name-title").textContent = session.title || "The plan";
      $("name-sub").textContent = `Your name, so ${session.createdByName || "the organizer"} knows who’s coming.`;
      show("name-step");
      return;
    }
    renderDecided();
    if (pendingRSVP && myName()) {
      const { going, guests } = pendingRSVP;
      pendingRSVP = null;
      answerRSVP(going, guests);
    }
    return;
  }

  sawUndecided = true;
  const name = myName();
  if (!name) {
    $("name-title").textContent = session.title || "Help pick where to eat";
    // What happens next, so a first-timer knows why they're typing a name.
    const next = isSurprise() ? "The wheel picks from places nearby, and the winner shows up right here."
      : isSpin() ? "Add your pick to the wheel, and the winner shows up right here."
      : "Vote for a place, and the winner shows up right here.";
    $("name-sub").textContent = `${session.createdByName || "A friend"} wants help deciding where to eat. ${next}`;
    show("name-step");
    return;
  }

  renderVote();
  if (held) {
    $("vote-help").textContent = `${session.createdByName || "The organizer"} is locking it in. The result shows here in a moment.`;
  }
}

function tally() {
  const ids = new Set((session.options || []).map((o) => o.id));
  const counts = {}, voters = {};
  for (const v of votes) {
    if (!ids.has(v.optionID)) continue;
    counts[v.optionID] = (counts[v.optionID] || 0) + 1;
    (voters[v.optionID] = voters[v.optionID] || []).push(v.voterName);
  }
  // The leader only counts places that can still win.
  const eligible = Object.keys(counts).filter((id) => !ruledOut.has(id));
  const top = Math.max(0, ...eligible.map((id) => counts[id]));
  const leaders = top === 0 ? [] : eligible.filter((id) => counts[id] === top);
  return { counts, voters, leader: leaders.length === 1 ? leaders[0] : null, total: Object.values(counts).reduce((a, b) => a + b, 0) };
}

function isSpin() { return session.mode === "spin"; }
// "Surprise us": a spin whose wheel is places nearby; nobody adds a pick.
function isSurprise() { return isSpin() && session.surprise === true; }
function isPlan() { return session.mode === "plan"; }

function statusText() {
  if (isSurprise()) {
    const n = (session.options || []).length;
    return `${n} places nearby on the wheel · ${session.createdByName || "the organizer"} spins when everyone’s here`;
  }
  if (isSpin()) {
    const n = (session.options || []).length;
    const picks = session.picksBy || {};
    // A full wheel can't take more picks, so nobody is waited on.
    const waiting = n >= MAX_OPTIONS ? []
      : members.filter((m) => !picks[m.id] && !(session.options || []).some((o) => o.addedByID === m.id));
    const names = waiting.map((m) => m.name);
    const tail = n >= MAX_OPTIONS ? "the wheel is full" : !waiting.length ? "everyone’s pick is in"
      : `waiting on picks from ${names.length <= 3 ? names.join(", ") : names.slice(0, 3).join(", ") + ` + ${names.length - 3} more`}`;
    return `${n} place${n === 1 ? "" : "s"} in the wheel · ${tail}`;
  }
  const voted = new Set(votes.map((v) => v.voterID));
  const names = members.filter((m) => !voted.has(m.id)).map((m) => (m.id === uid ? "you" : m.name));
  let text = `${members.length} in the group · ` +
    (!names.length ? "everyone has voted"
      : `waiting on ${names.length <= 3 ? names.join(", ") : names.slice(0, 3).join(", ") + ` + ${names.length - 3} more`}`);
  const closes = session.closesAt && session.closesAt.toDate ? session.closesAt.toDate() : null;
  if (closes) {
    const left = Math.max(0, Math.floor((closes - Date.now()) / 1000));
    text += left > 0 ? ` · closes in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : " · voting closed";
  }
  return text;
}

// Keep the countdown ticking without rebuilding the buttons.
let wasTimeUp = false;
setInterval(() => {
  if (!session || $("vote-step").hidden) return;
  $("status").textContent = statusText();
  const up = isTimeUp();
  if (up !== wasTimeUp) { wasTimeUp = up; render(); }  // lock the buttons when time runs out
}, 1000);

function renderVote() {
  $("you-are").textContent = myName() ? `You’re ${myName()}.` : "";
  if (isSpin()) return renderSpin();
  const t = tally();
  const mine = votes.find((v) => v.voterID === uid)?.optionID;
  const slots = Math.max(members.length, t.total, 1);

  $("title").textContent = session.title;
  showMeetLine();
  $("status").textContent = statusText();
  const closed = !acceptsChanges();
  const notes = [];
  if (isTimeUp()) notes.push(`Time’s up! ${session.createdByName || "The organizer"} will lock it in.`);
  if (everythingRuledOut) notes.push("Someone has every place here blacklisted, so they’re all back in.");
  if (mine && ruledOut.has(mine) && !closed) notes.push("Your vote is on a place someone ruled out, so it can’t win. Tap another place.");
  if (!closed) notes.push("Tap a place to vote. Tap it again to take your vote back. The winner shows up right here, and ties are broken fairly.");
  $("vote-help").textContent = notes.join(" ");

  const list = $("options");
  list.replaceChildren();
  for (const option of session.options || []) {
    const count = t.counts[option.id] || 0;
    const lead = t.leader === option.id;
    const button = document.createElement("button");
    button.type = "button";
    const out = ruledOut.has(option.id);
    button.className = "option" + (mine === option.id ? " mine" : "") + (lead && !out ? " lead" : "") + (out ? " ruled-out" : "");
    button.disabled = busy || closed || (out && mine !== option.id);
    button.setAttribute("aria-pressed", mine === option.id ? "true" : "false");
    button.setAttribute("aria-label", `${option.name}, ${count} vote${count === 1 ? "" : "s"}${mine === option.id ? ", your vote" : ""}`);

    const row = document.createElement("div");
    row.className = "row";
    const [bg, ink] = tileColors(option.name);
    const tile = document.createElement("div");
    tile.className = "tile";
    tile.style.background = bg;
    tile.style.color = ink;
    tile.textContent = option.name.charAt(0).toUpperCase();
    const text = document.createElement("div");
    const nameEl = document.createElement("div");
    nameEl.className = "name";
    nameEl.textContent = option.name;
    if (out || lead) {
      const pill = document.createElement("span");
      pill.className = out ? "pill muted-pill" : "pill";
      pill.textContent = out ? "RULED OUT" : "LEADING";
      nameEl.append(pill);
    }
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = out ? "Someone in the group blacklisted it, so it can’t win"
      : (t.voters[option.id] || []).join(", ") || `${option.category} · added by ${option.addedBy}`;
    text.append(nameEl, sub);
    const countEl = document.createElement("div");
    countEl.className = "count";
    countEl.textContent = String(count);
    row.append(tile, text, countEl);

    const bar = document.createElement("div");
    bar.className = "bar";
    const fill = document.createElement("span");
    fill.style.width = `${Math.min(100, (count / slots) * 100)}%`;
    bar.append(fill);

    button.append(row, bar);
    button.addEventListener("click", () => vote(option.id, mine));
    list.append(button);
  }
  updateSuggest();
  show("vote-step");
}

// Group spin: everyone adds their pick, then whoever started it spins the
// wheel in the app and one is picked at random. Nothing to vote on here.
// A date & time set up front: everyone sees when while deciding where.
function showMeetLine() {
  const el = $("meet-line");
  const meet = toDate(session.meetTime);
  el.hidden = !meet;
  if (meet) {
    const day = meet.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
    const time = meet.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    el.textContent = `📅 ${day} · ${time}`;
  }
}

function renderSpin() {
  $("title").textContent = session.title;
  showMeetLine();
  $("status").textContent = statusText();
  const me = (myName() || "").trim().toLowerCase();
  const creator = session.createdByName || "Whoever started it";
  const options = session.options || [];
  const havePick = !!myPick();
  $("vote-help").textContent = isSurprise()
    ? `${creator} let the wheel fill itself with places nearby. When they spin, it picks one at random and the result shows up right here.`
    : havePick
    ? `You’re in the wheel. ${creator} spins when everyone’s ready, and the app picks one at random.`
    : mapkitToken
      ? `Add your pick to the wheel. ${creator} spins when everyone’s ready, and the app picks one at random.`
      : `${creator} spins when everyone’s ready, and the app picks one at random. To add a pick, join in the Tablewhere app with the code below.`;

  const list = $("options");
  list.replaceChildren();
  if (!options.length) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "The wheel is empty. Add the first pick!";
    list.append(empty);
  }
  for (const option of options) {
    const mine = !isSurprise() && (option.addedByID ? option.addedByID === uid
      : (option.addedBy || "").trim().toLowerCase() === me);
    const card = document.createElement("div");
    card.className = "option static" + (mine ? " mine-pick" : "");
    card.setAttribute("role", "listitem");
    const row = document.createElement("div");
    row.className = "row";
    const [bg, ink] = tileColors(option.name);
    const tile = document.createElement("div");
    tile.className = "tile";
    tile.style.background = bg;
    tile.style.color = ink;
    tile.textContent = option.name.charAt(0).toUpperCase();
    const text = document.createElement("div");
    const nameEl = document.createElement("div");
    nameEl.className = "name";
    nameEl.textContent = option.name;
    const out = ruledOut.has(option.id);
    if (mine || out) {
      const pill = document.createElement("span");
      pill.className = out ? "pill muted-pill" : "pill soft";
      pill.textContent = out ? "RULED OUT" : "YOUR PICK";
      nameEl.append(pill);
    }
    if (out) card.classList.add("ruled-out");
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = out ? `Added by ${option.addedBy} · someone in the group blacklisted it, so the spin skips it`
      : isSurprise() ? option.category : `${option.category} · added by ${option.addedBy}`;
    text.append(nameEl, sub);
    row.append(tile, text);
    card.append(row);
    list.append(card);
  }
  list.setAttribute("role", "list");
  updateSuggest();
  show("vote-step");
}

async function vote(optionId, currentVote) {
  if (busy) return;
  busy = true;
  renderVote();
  const ref = doc(sessionRef, "votes", uid);
  try {
    if (currentVote === optionId) {
      await deleteDoc(ref);
    } else {
      await ensureJoined();
      await setDoc(ref, { voterID: uid, voterName: myName(), optionID: optionId, votedAt: serverTimestamp() });
      bumpStat("webVotes");
    }
  } catch {
    $("vote-help").textContent = navigator.onLine === false
      ? "You’re offline. Check your connection and try again."
      : "That didn’t go through. Voting may have closed. Reload to see the latest.";
  } finally {
    busy = false;
    render();
  }
}

// A small map of where you're going, on the result. Tap it for directions.
let winnerMap = null;
let winnerMapFor = "";
async function showWinnerMap(winner) {
  const box = $("winner-map");
  const lat = Number(winner.latitude), lon = Number(winner.longitude);
  if (!mapkitToken || !Number.isFinite(lat) || !Number.isFinite(lon) || (lat === 0 && lon === 0)) {
    box.hidden = true;
    return;
  }
  const key = `${winner.id}|${lat}|${lon}`;
  if (key === winnerMapFor) return;  // live updates re-render; don't rebuild the map
  winnerMapFor = key;
  let mk;
  try { mk = await loadMapKit(); } catch { box.hidden = true; winnerMapFor = ""; return; }
  if (winnerMapFor !== key) return;  // the plan changed while MapKit loaded
  box.hidden = false;
  const spot = new mk.Coordinate(lat, lon);
  const region = new mk.CoordinateRegion(spot, new mk.CoordinateSpan(0.008, 0.008));
  if (!winnerMap) {
    winnerMap = new mk.Map(box, {
      region,
      colorScheme: mk.Map.ColorSchemes.Dark,
      isZoomEnabled: false,
      isScrollEnabled: false,
      isRotationEnabled: false,
      showsCompass: mk.FeatureVisibility.Hidden,
      showsZoomControl: false,
      showsMapTypeControl: false,
      showsPointsOfInterest: true,
    });
    box.addEventListener("click", () => {
      const link = isApple ? $("apple-maps") : $("google-maps");
      if (link.href) window.open(link.href, "_blank", "noopener");
    });
  } else {
    winnerMap.removeAnnotations(winnerMap.annotations);
    winnerMap.region = region;
  }
  winnerMap.addAnnotation(new mk.MarkerAnnotation(spot, {
    color: "#FFB23F",
    glyphText: "🍴",
    title: winner.name,
  }));
  box.setAttribute("aria-label", `Map of ${winner.name}. Tap for directions.`);
}

function renderDecided() {
  const winner = (session.options || []).find((o) => o.id === session.winnerID);
  if (!winner) return renderVote();
  $("winner-name").textContent = winner.name;
  $("winner-label").textContent = isPlan() ? "THE PLAN" : isSpin() ? "THE WHEEL PICKED" : "THE GROUP PICKED";
  const time = formatTime(session.meetTime);
  const how = isPlan() ? `Picked by ${session.createdByName || "the organizer"} · ${winner.category}`
    : isSurprise() ? `Picked by the spin · ${winner.category}`
    : isSpin() ? `Picked by the spin · ${winner.addedBy ? winner.addedBy + "’s pick" : winner.category}` : winner.category;
  $("winner-detail").textContent = time ? `Meet ${time} · ${how}` : how;

  const q = encodeURIComponent(winner.name);
  $("apple-maps").href = `https://maps.apple.com/?daddr=${winner.latitude},${winner.longitude}&q=${q}`;
  $("google-maps").href = `https://www.google.com/maps/dir/?api=1&destination=${winner.latitude},${winner.longitude}`;
  if (!isApple) {
    // Google Maps is the main button on Android.
    $("google-maps").className = "btn light";
    $("apple-maps").className = "btn ghost";
    $("google-maps").after($("apple-maps"));
  }
  const site = $("website");
  if (winner.websiteURL && /^https?:\/\//i.test(winner.websiteURL)) {
    site.href = winner.websiteURL;
    site.hidden = false;
  } else {
    site.hidden = true;
  }

  // The creator's note ("Bring a gift!"), if there is one.
  const note = typeof session.note === "string" ? session.note.trim() : "";
  $("note").hidden = !note;
  $("note-text").textContent = note;
  $("note-by").textContent = note ? `— ${session.createdByName || "the organizer"}` : "";

  const meet = toDate(session.meetTime);
  $("calendar").hidden = !meet || meet.getTime() < Date.now() - 15 * 60 * 1000;
  // With a time to be somewhere, the app's leave-by reminder is worth a mention.
  $("app-pitch").hidden = !meet || meet.getTime() < Date.now();
  showWinnerMap(winner);
  renderRSVP();
  renderBreakdown(winner.id);
  show("decided-step");
}

function toDate(ts) {
  if (!ts) return null;
  return ts.toDate ? ts.toDate() : new Date(ts);
}

// ---------------------------------------------------------------------------
// RSVPs ("I'll pick" plans). Same rules as the app: one answer each, guests
// 0–4 when you're in, until the reply-by time. The organizer counts as coming.

const MAX_GUESTS = 4;

function rsvpOpen() {
  if (session.asksRSVP !== true) return false;
  const by = toDate(session.rsvpBy);
  return !by || by.getTime() > Date.now();
}

function headcount() {
  const all = [...rsvps];
  if (session.createdBy && !all.some((r) => r.userID === session.createdBy)) {
    all.push({ userID: session.createdBy, name: session.createdByName || "Host", going: true, guests: 0 });
  }
  const byName = (a, b) => String(a.name).localeCompare(String(b.name));
  const going = all.filter((r) => r.going).sort(byName);
  const notGoing = all.filter((r) => !r.going).sort(byName);
  const people = going.length;
  const guests = going.reduce((n, r) => n + (r.guests || 0), 0);
  let summary = `${people + guests} coming`;
  if (guests) summary += ` (${people} + ${guests} guest${guests === 1 ? "" : "s"})`;
  if (notGoing.length) summary += ` · ${notGoing.length} can’t make it`;
  return { going, notGoing, summary };
}

function renderRSVP() {
  const box = $("rsvp");
  if (session.asksRSVP !== true) { box.hidden = true; return; }
  box.hidden = false;
  const count = headcount();
  $("rsvp-count").textContent = count.summary;

  const open = rsvpOpen();
  const by = toDate(session.rsvpBy);
  $("rsvp-deadline").textContent = by ? (open ? `Reply by ${formatTime(by).replace(/^at /, "today at ")}` : "Replies are closed") : "";

  const isOrganizer = uid === session.createdBy;
  const mine = rsvps.find((r) => r.userID === uid);
  $("rsvp-actions").hidden = !open || isOrganizer;
  $("rsvp-in").setAttribute("aria-pressed", mine?.going ? "true" : "false");
  $("rsvp-out").setAttribute("aria-pressed", mine && !mine.going ? "true" : "false");
  $("rsvp-in").disabled = $("rsvp-out").disabled = busy;

  const showGuests = open && !isOrganizer && !!mine?.going;
  $("rsvp-guests").hidden = !showGuests;
  if (showGuests) {
    const g = mine.guests || 0;
    $("rsvp-guests-text").textContent = g ? `Bringing ${g} guest${g === 1 ? "" : "s"}` : "Just me";
    $("guests-minus").disabled = busy || g <= 0;
    $("guests-plus").disabled = busy || g >= MAX_GUESTS;
  }

  const names = $("rsvp-names");
  names.replaceChildren();
  const group = (title, list) => {
    if (!list.length) return;
    const who = document.createElement("div");
    who.className = "who";
    who.textContent = title.toUpperCase();
    const line = document.createElement("div");
    line.textContent = list.join(", ");
    names.append(who, line);
  };
  group("Coming", count.going.map((r) => r.name + (r.guests ? ` +${r.guests}` : "")));
  group("Can’t make it", count.notGoing.map((r) => r.name));

  if (!open && !isOrganizer && mine) {
    $("rsvp-help").textContent = mine.going ? "You said you’re in." : "You said you can’t make it.";
  } else if (!$("rsvp-help").dataset.error) {
    $("rsvp-help").textContent = "";
  }
}

async function answerRSVP(going, guests) {
  if (busy || !rsvpOpen()) return;
  const name = myName();
  if (!name) {
    pendingRSVP = { going, guests };
    render();
    $("name-input").focus();
    return;
  }
  busy = true;
  delete $("rsvp-help").dataset.error;
  renderRSVP();
  try {
    if (!members.some((m) => m.id === uid)) await join(name);
    await setDoc(doc(sessionRef, "rsvps", uid), {
      userID: uid,
      name: String(myName() || name).slice(0, 40),
      going,
      guests: going ? Math.max(0, Math.min(MAX_GUESTS, guests)) : 0,
      answeredAt: serverTimestamp(),
    });
    bumpStat("rsvps");
  } catch {
    $("rsvp-help").dataset.error = "1";
    $("rsvp-help").textContent = navigator.onLine === false
      ? "You’re offline. Check your connection and try again."
      : "That didn’t go through. Replies may have closed. Reload to see the latest.";
  } finally {
    busy = false;
    render();
  }
}

// ---------------------------------------------------------------------------
// Add to Calendar: an .ics file, which phones and computers open in their
// calendar app. 90 minutes, like the app's.

function icsDate(date) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

function icsText(text) {
  return String(text).replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/([,;])/g, "\\$1");
}

// Android and other non-Apple devices: Google Maps first, and Google
// Calendar instead of an .ics file (which often won't open there).
const isApple = /iPhone|iPad|iPod|Macintosh/.test(navigator.userAgent);

function downloadCalendar() {
  const winner = (session.options || []).find((o) => o.id === session.winnerID);
  const start = toDate(session.meetTime);
  if (!winner || !start) return;
  const end = new Date(start.getTime() + 90 * 60 * 1000);
  const note = typeof session.note === "string" && session.note.trim()
    ? `Note from ${session.createdByName || "the organizer"}: ${session.note.trim()}\n` : "";
  if (!isApple) {
    const params = new URLSearchParams({
      action: "TEMPLATE",
      text: `${winner.name} · ${session.title || "Dinner"}`,
      dates: `${icsDate(start)}/${icsDate(end)}`,
      details: `${note}Details: ${location.href}`,
      location: winner.address || winner.name,
    });
    window.open(`https://calendar.google.com/calendar/render?${params}`, "_blank", "noopener");
    return;
  }
  const lines = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Tablewhere//Plan//EN", "BEGIN:VEVENT",
    `UID:${sessionId}@forkroad`,
    `DTSTAMP:${icsDate(new Date())}`,
    `DTSTART:${icsDate(start)}`,
    `DTEND:${icsDate(end)}`,
    `SUMMARY:${icsText(`${winner.name} · ${session.title || "Dinner"}`)}`,
    `LOCATION:${icsText(winner.address || winner.name)}`,
    `GEO:${winner.latitude};${winner.longitude}`,
    `DESCRIPTION:${icsText(`${note}Details: ${location.href}`)}`,
    `URL:${location.href}`,
    "END:VEVENT", "END:VCALENDAR",
  ];
  const blob = new Blob([lines.join("\r\n")], { type: "text/calendar" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "tablewhere-plan.ics";
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

// After the vote closes: every place, who voted for it, and who didn't vote.
function renderBreakdown(winnerId) {
  const wrap = $("breakdown-wrap");
  // Nobody votes in a spin or an "I'll pick" plan.
  if (session.mode === "spin" || session.mode === "plan") { wrap.hidden = true; return; }
  const t = tally();
  const options = (session.options || []).map((o, i) => ({ o, i, n: t.counts[o.id] || 0 }));
  options.sort((a, b) =>
    (b.o.id === winnerId) - (a.o.id === winnerId) || b.n - a.n || a.i - b.i);

  const list = $("breakdown");
  list.replaceChildren();
  for (const { o, n } of options) {
    const item = document.createElement("div");
    item.className = "item" + (o.id === winnerId ? " won" : "");
    const [bg, ink] = tileColors(o.name);
    const tile = document.createElement("div");
    tile.className = "tile";
    tile.style.background = bg;
    tile.style.color = ink;
    tile.textContent = o.name.charAt(0).toUpperCase();
    const text = document.createElement("div");
    const name = document.createElement("div");
    name.className = "name";
    name.textContent = o.name;
    if (o.id === winnerId) {
      const crown = document.createElement("span");
      crown.className = "crown";
      crown.textContent = "★ WINNER";
      name.append(crown);
    }
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = (t.voters[o.id] || []).join(", ") || "No votes";
    text.append(name, sub);
    const count = document.createElement("div");
    count.className = "count";
    count.textContent = String(n);
    item.append(tile, text, count);
    list.append(item);
  }

  const voted = new Set(votes.map((v) => v.voterID));
  const skipped = members.filter((m) => !voted.has(m.id)).map((m) => m.name);
  if (skipped.length) {
    const item = document.createElement("div");
    item.className = "item sub";
    item.textContent = `Didn’t vote: ${skipped.join(", ")}`;
    list.append(item);
  }
  wrap.hidden = false;
}


// ---------------------------------------------------------------------------
// Suggest a place (friends without the app). Searches Apple Maps with
// MapKit JS around the places already in the vote, and adds the pick the
// same way the app does: one transaction, no duplicates, at most 12 places.

const MAX_OPTIONS = 12;

// The place you added with your one pick, if any.
function myPick() {
  const options = session.options || [];
  const id = (session.picksBy || {})[uid];
  return (id && options.find((o) => o.id === id)) || options.find((o) => o.addedByID === uid) || null;
}
let suggestWired = false;
let searchTimer = null;
let searchSeq = 0;
let adding = false;

function updateSuggest() {
  const open = acceptsChanges();
  const full = (session.options || []).length >= MAX_OPTIONS;
  const mine = myPick();
  $("suggest").hidden = !mapkitToken || !open || isSurprise();
  const button = $("suggest-open");
  button.style.width = "100%";
  if (mine) {
    // One pick each: once yours is in, the button shows it and lets you swap it.
    button.className = "btn ghost wide";
    button.textContent = `✓ Your pick: ${mine.name} · Change`;
    button.disabled = false;
  } else {
    button.className = isSpin() && !full ? "btn primary wide" : "btn ghost wide";
    button.textContent = full
      ? (isSpin() ? "The wheel is full (12 places)" : "This vote is full (12 places)")
      : (isSpin() ? "+ Add your pick" : "+ Suggest a place (one each)");
    button.disabled = full;
    if (full) $("suggest-panel").hidden = true;
  }
  if (!suggestWired && mapkitToken) wireSuggest();
}

function wireSuggest() {
  suggestWired = true;
  $("suggest-open").addEventListener("click", async () => {
    const near = session.area?.name ? ` near ${session.area.name}` : "";
    $("suggest-input").placeholder = myPick() ? `Search for a place to swap in${near}` : `A name or craving${near}, like “tacos”`;
    $("suggest-panel").hidden = false;
    $("suggest-open").hidden = true;
    $("suggest-input").focus();
    try {
      await loadMapKit();
      setStatus("");
    } catch {
      setStatus("Search isn’t available right now. You can still vote.");
    }
  });
  $("suggest-close").addEventListener("click", closeSuggest);
  $("suggest-input").addEventListener("input", () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(runSearch, 350);
  });
  $("suggest-input").addEventListener("keydown", (event) => {
    if (event.key === "Enter") { event.preventDefault(); clearTimeout(searchTimer); runSearch(); }
  });
}

function closeSuggest() {
  $("suggest-panel").hidden = true;
  $("suggest-open").hidden = false;
  $("suggest-input").value = "";
  $("suggest-results").replaceChildren();
  setStatus("");
}

function setStatus(text, isError = false) {
  const el = $("suggest-status");
  el.textContent = text;
  el.classList.toggle("error", isError);
  el.hidden = !text;
}

let mapkitReady = null;
function loadMapKit() {
  if (mapkitReady) return mapkitReady;
  mapkitReady = new Promise((resolve, reject) => {
    window.__forkroadMapKitLoaded = () => {
      try {
        mapkit.init({ authorizationCallback: (done) => done(mapkitToken) });
        mapkit.addEventListener("error", () => setStatus("Search isn’t available right now. You can still vote.", true));
        resolve(window.mapkit);
      } catch (e) { reject(e); }
    };
    const script = document.createElement("script");
    script.src = "https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.core.js";
    script.crossOrigin = "anonymous";
    script.async = true;
    script.dataset.callback = "__forkroadMapKitLoaded";
    script.dataset.libraries = "map,annotations,services";
    script.onerror = () => { mapkitReady = null; reject(new Error("MapKit JS failed to load")); };
    document.head.append(script);
  });
  return mapkitReady;
}

// Where the group is eating: the area its creator set, else the middle of
// the places already in the vote (older plans have no area).
function groupCenter() {
  const area = session.area;
  if (area && Number.isFinite(area.latitude) && Number.isFinite(area.longitude)) {
    return { lat: area.latitude, lon: area.longitude };
  }
  const opts = (session.options || []).filter((o) => Number.isFinite(o.latitude) && Number.isFinite(o.longitude));
  if (!opts.length) return null;
  const lat = opts.reduce((a, o) => a + o.latitude, 0) / opts.length;
  const lon = opts.reduce((a, o) => a + o.longitude, 0) / opts.length;
  return { lat, lon };
}

function milesBetween(a, b) {
  const r = 3958.8, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

async function runSearch() {
  const query = $("suggest-input").value.trim();
  const seq = ++searchSeq;
  if (query.length < 2) { $("suggest-results").replaceChildren(); setStatus(""); return; }
  const center = groupCenter();
  if (!center) { setStatus("Couldn’t tell where this group is eating.", true); return; }

  setStatus("Searching…");
  let mk;
  try { mk = await loadMapKit(); } catch { setStatus("Search isn’t available right now. You can still vote.", true); return; }

  // Apple returns only about two dozen places per search, so a word like
  // "burgers" over a big area can skip the ones closest to the group. Search
  // twice at once (about 3 miles around the group, and about 15) and merge.
  const span = (degLat) => new mk.CoordinateSpan(degLat, degLat / Math.max(0.2, Math.cos(center.lat * Math.PI / 180)));
  const regions = [0.09, 0.44].map((d) => new mk.CoordinateRegion(new mk.Coordinate(center.lat, center.lon), span(d)));
  let filter = null;
  try {
    const C = mk.PointOfInterestCategory;
    filter = mk.PointOfInterestFilter.including(
      [C.Restaurant, C.Cafe, C.Bakery, C.Brewery, C.Winery].filter(Boolean));
  } catch { /* older MapKit JS: search everything */ }

  const searchIn = (region) => new Promise((resolve) => {
    const options = { region, includeAddresses: false, includeQueries: false, includePointsOfInterest: true };
    if (filter) options.pointOfInterestFilter = filter;
    try {
      new mk.Search(options).search(query, (error, data) => resolve(error ? null : (data?.places || [])), { region });
    } catch { resolve(null); }
  });
  const batches = await Promise.all(regions.map(searchIn));
  if (seq !== searchSeq) return;  // a newer search took over
  if (batches.every((b) => b === null)) { setStatus("Couldn’t search right now. Try again in a moment.", true); return; }

  const seen = new Set();
  const places = batches.flatMap((b) => b || [])
    .filter((p) => p.coordinate && p.name)
    .filter((p) => {
      const key = `${p.name.toLowerCase()}|${p.coordinate.latitude.toFixed(3)}|${p.coordinate.longitude.toFixed(3)}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .map((p) => ({ p, miles: milesBetween(center, { lat: p.coordinate.latitude, lon: p.coordinate.longitude }) }))
    .sort((a, b) => a.miles - b.miles)
    .slice(0, 20);
  renderResults(places, query);
}

async function renderResults(places, query) {
  const blocked = globalThis.crypto?.subtle ? groupBlocked() : new Set();
  const outIDs = new Set();
  if (blocked.size) {
    for (const { p } of places) {
      const id = toOption(p).id;
      if (blocked.has(await blockedHash(id))) outIDs.add(id);
    }
  }
  const list = $("suggest-results");
  list.replaceChildren();
  if (!places.length) {
    setStatus(`No restaurants found for “${query}”. Try a broader word like “pizza.”`);
    return;
  }
  setStatus("");
  for (const { p, miles } of places) {
    const option = toOption(p);
    const out = outIDs.has(option.id);
    const taken = isTaken(option) || out;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "result";
    button.disabled = taken || adding;
    button.dataset.taken = taken ? "1" : "0";

    const [bg, ink] = tileColors(option.name);
    const tile = document.createElement("div");
    tile.className = "tile";
    tile.style.background = bg;
    tile.style.color = ink;
    tile.textContent = option.name.charAt(0).toUpperCase();
    const text = document.createElement("div");
    const name = document.createElement("div");
    name.className = "name";
    name.textContent = option.name;
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = `${option.category} · ${miles < 10 ? miles.toFixed(1) : Math.round(miles)} mi${option.address ? " · " + option.address : ""}`;
    text.append(name, sub);
    const add = document.createElement("span");
    add.className = "add";
    const mine = myPick();
    add.textContent = out ? "Ruled out"
      : taken ? (isSpin() ? "In the wheel" : "In the vote")
      : mine ? "Swap" : "Add";
    button.append(tile, text, add);
    button.addEventListener("click", () => addOption(option));
    list.append(button);
  }
}

function categoryLabel(place) {
  switch (place.pointOfInterestCategory) {
    case "Cafe": return "Café";
    case "Bakery": return "Bakery";
    case "Brewery": return "Brewery";
    case "Winery": return "Winery";
    case "FoodMarket": return "Market";
    default: return "Restaurant";
  }
}

// Same ID the app makes (Place.makeID in PickerCore): name + coordinates
// rounded to 4 places, written the way Swift prints a Double.
function swiftDouble(x) {
  if (Object.is(x, -0)) return "-0.0";
  return Number.isInteger(x) ? x.toFixed(1) : String(x);
}
function roundAway(x) { return Math.sign(x) * Math.round(Math.abs(x)); }
function makeID(name, lat, lon) {
  const rLat = roundAway(lat * 10000) / 10000;
  const rLon = roundAway(lon * 10000) / 10000;
  return `${name.toLowerCase()}|${swiftDouble(rLat)}|${swiftDouble(rLon)}`;
}

function toOption(place) {
  const lat = place.coordinate.latitude, lon = place.coordinate.longitude;
  const option = {
    id: makeID(place.name, lat, lon),
    name: place.name,
    category: categoryLabel(place),
    latitude: lat,
    longitude: lon,
    addedBy: myName() || "A friend",
    addedByID: uid,
  };
  // Optional fields are left out when missing, matching the app.
  if (place.formattedAddress) option.address = place.formattedAddress;
  if (place.telephone) option.phoneNumber = place.telephone;
  const url = Array.isArray(place.urls) ? place.urls[0] : place.url;
  if (typeof url === "string" && /^https?:\/\//i.test(url)) option.websiteURL = url;
  return option;
}

// Apple Maps on the web and on iPhone can disagree by a few meters, so a
// place with the same name within ~150 m also counts as already added.
function sameOption(a, b) {
  if (a.id === b.id) return true;
  return a.name.trim().toLowerCase() === b.name.trim().toLowerCase()
    && milesBetween({ lat: a.latitude, lon: a.longitude }, { lat: b.latitude, lon: b.longitude }) < 0.1;
}
function isTaken(option) {
  return (session.options || []).some((o) => sameOption(o, option));
}

async function addOption(option) {
  if (adding) return;
  adding = true;
  setStatus(myPick() ? `Swapping your pick for ${option.name}…` : `Adding ${option.name}…`);
  [...$("suggest-results").children].forEach((b) => { b.disabled = true; });
  try {
    await ensureJoined();
    await runTransaction(db, async (tx) => {
      const snap = await tx.get(sessionRef);
      if (!snap.exists()) throw new Error("ended");
      const data = snap.data();
      const options = data.options || [];
      const closes = data.closesAt?.toDate ? data.closesAt.toDate() : null;
      if (data.status !== "open" || (closes && closes <= Date.now())) throw new Error("closed");
      const oldPick = (data.picksBy || {})[uid];
      const others = options.filter((o) => !oldPick || o.id !== oldPick);
      if (others.some((o) => sameOption(o, option))) throw new Error("duplicate");
      const index = oldPick ? options.findIndex((o) => o.id === oldPick) : -1;
      if (index >= 0) {
        // Change my pick: swap it in place (the rules check only yours moved).
        const next = options.slice();
        next[index] = option;
        tx.update(sessionRef, { options: next, [`picksBy.${uid}`]: option.id });
        return;
      }
      if (options.length >= MAX_OPTIONS) throw new Error("full");
      // Everyone gets one pick; it's recorded under your ID (the rules check it).
      tx.update(sessionRef, { options: [...options, option], [`picksBy.${uid}`]: option.id });
    });
    bumpStat("webPicks");
    closeSuggest();
  } catch (error) {
    const messages = {
      duplicate: isSpin() ? "That place is already in the wheel." : "That place is already in the vote.",
      full: "This pick already has 12 places, the most it can hold.",
      closed: "Voting has closed, so places can’t be added.",
      ended: "This group plan has ended.",
      picked: "You’ve already added your pick. Everyone gets one.",
    };
    setStatus(messages[error?.message] || "Couldn’t add it. Check your connection and try again.", true);
    // Let them pick something else (places already in the vote stay disabled).
    [...$("suggest-results").children].forEach((b) => { b.disabled = b.dataset.taken === "1"; });
  } finally {
    adding = false;
  }
}
