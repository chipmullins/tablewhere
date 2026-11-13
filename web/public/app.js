// Tablewhere web vote page: https://<host>/v/<sessionId>
// Same Firestore data as the app and iMessage extension.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth, signInAnonymously, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import {
  getFirestore, doc, collection, onSnapshot, setDoc, deleteDoc, serverTimestamp, runTransaction, increment
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";
import { isFastFood, isCoffeeOrSweets, isNotARestaurant, guessCuisine } from "./food-filters.js?v=43";

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
let filteredOut = new Set();   // the part of ruledOut that's the group's filters
let everythingRuledOut = false;

// A timed vote whose time is up (it stays "open" until the creator locks it in).
function isTimeUp() {
  const closes = session?.closesAt?.toDate ? session.closesAt.toDate() : null;
  return !!closes && session.status === "open" && closes <= Date.now();
}
function acceptsChanges() { return session.status === "open" && !isTimeUp(); }
async function refreshRuledOut() {
  if (!session) return;
  // Places that break the organizer's group filters (added on an older app or
  // a page opened before the filter was turned on): ruled out, like the app.
  const filtered = new Set((session.options || []).filter((o) => groupFilterRule(o)).map((o) => o.id));
  const next = new Set(filtered);
  const blocked = globalThis.crypto?.subtle ? groupBlocked() : new Set();  // hashing needs https; the live page always is
  if (blocked.size) {
    for (const o of session.options || []) {
      if (blocked.has(await blockedHash(o.id))) next.add(o.id);
    }
  }
  // If every place is ruled out, they all count again.
  const all = next.size > 0 && next.size === (session.options || []).length;
  const effective = all ? new Set() : next;
  const changed = all !== everythingRuledOut || effective.size !== ruledOut.size
    || [...effective].some((id) => !ruledOut.has(id))
    || filtered.size !== filteredOut.size || [...filtered].some((id) => !filteredOut.has(id));
  ruledOut = effective;
  filteredOut = all ? new Set() : filtered;
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
let etas = [];          // "On my way" (sessions/{id}/eta)
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

  onSnapshot(collection(sessionRef, "eta"), (snap) => {
    etas = snap.docs.map((d) => d.data());
    render();
  }, () => {});
  wireOnMyWay();

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
  schedulePrefetch();
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
    // Tapped I'm in / Can't make it / On my way without a name yet: ask for it first.
    if ((pendingRSVP || pendingOMW) && !myName()) {
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
    if (pendingOMW && myName()) {
      const next = pendingOMW;
      pendingOMW = null;
      next();
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

// "How many are eating?" (the creator's count, or the iMessage chat's size).
// Joins can only raise it. Null when unknown: count people as they join.
function groupSize() {
  const n = session.expectedCount;
  if (typeof n !== "number" || !Number.isFinite(n) || isSurprise() || isPlan()) return null;
  return Math.max(n, members.length);
}
// Expected people who haven't opened the link yet.
function notJoinedYet() {
  const h = groupSize();
  return h === null ? 0 : Math.max(0, h - members.length);
}
// "Sam, Alex, Jo + 2 more"; `extra` unnamed people add to the "more".
function whoList(names, extra = 0) {
  const shown = names.slice(0, 3);
  const more = names.length - shown.length + extra;
  if (!shown.length) return `${more} more`;
  return shown.join(", ") + (more > 0 ? ` + ${more} more` : "");
}
function groupCountText() {
  const h = groupSize();
  return h !== null && h > members.length ? `${members.length} of ${h} here` : `${members.length} in the group`;
}

function statusText() {
  if (isSurprise()) {
    const n = (session.options || []).length;
    return `${n} places nearby on the wheel · ${session.createdByName || "the organizer"} spins when everyone’s here`;
  }
  const h = groupSize();
  if (isSpin()) {
    const n = (session.options || []).length;
    const picks = session.picksBy || {};
    const hasPick = (m) => !!picks[m.id] || (session.options || []).some((o) => o.addedByID === m.id);
    // A full wheel can't take more picks, so nobody is waited on.
    const full = n >= MAX_OPTIONS;
    const waiting = full ? [] : members.filter((m) => !hasPick(m));
    const extra = full ? 0 : notJoinedYet();
    const names = waiting.map((m) => (m.id === uid ? "you" : m.name));
    const tail = full ? "the wheel is full" : !waiting.length && !extra ? "everyone’s pick is in"
      : h !== null ? `${members.filter(hasPick).length} of ${h} picks in · waiting on ${whoList(names, extra)}`
      : `waiting on picks from ${whoList(names)}`;
    return `${n} place${n === 1 ? "" : "s"} in the wheel · ${tail}`;
  }
  const voted = new Set(votes.map((v) => v.voterID));
  const names = members.filter((m) => !voted.has(m.id)).map((m) => (m.id === uid ? "you" : m.name));
  const extra = notJoinedYet();
  let text = `${groupCountText()} · ` +
    (!names.length && !extra ? "everyone has voted"
      : h !== null ? `${voted.size} of ${h} voted · waiting on ${whoList(names, extra)}`
      : `waiting on ${whoList(names)}`);
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
  const slots = Math.max(groupSize() || 0, members.length, t.total, 1);

  $("title").textContent = session.title;
  showMeetLine();
  showFiltersLine();
  $("status").textContent = statusText();
  const closed = !acceptsChanges();
  const notes = [];
  if (isTimeUp()) notes.push(`Time’s up! ${session.createdByName || "The organizer"} will lock it in.`);
  if (everythingRuledOut) notes.push("Every place here is ruled out (a blacklist or the group’s filters), so they’re all back in.");
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
    sub.textContent = out ? (filteredOut.has(option.id) ? "Doesn’t fit the group’s filters, so it can’t win" : "Someone in the group blacklisted it, so it can’t win")
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
  showFiltersLine();
  $("status").textContent = statusText();
  const me = (myName() || "").trim().toLowerCase();
  const creator = session.createdByName || "Whoever started it";
  const options = session.options || [];
  const havePick = !!myPick();
  $("vote-help").textContent = isSurprise()
    ? `${creator} let the wheel fill itself with places nearby. When they spin, it picks one at random and the result shows up right here.`
    : havePick
    ? `${creator} spins when everyone’s ready, and the app picks one at random.`
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
    sub.textContent = out ? `Added by ${option.addedBy} · ${filteredOut.has(option.id) ? "doesn’t fit the group’s filters" : "someone in the group blacklisted it"}, so the spin skips it`
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
  renderOnMyWay(winner);
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
// "On my way" (1.1): share when you'll get there, never where you are. One
// arrival time from here (browser location + Apple Maps directions); a
// browser can't keep updating it once the page is closed, so it's one-shot
// (the app updates as you drive). Same doc as the app: sessions/{id}/eta/{uid}.

let pendingOMW = null;   // an "On my way" tap waiting on your name
let omwBusy = false;

function omwRelevant(meet) {
  if (!meet) return false;
  const until = meet.getTime() - Date.now();
  return until < 4 * 3600 * 1000 && until > -45 * 60 * 1000;
}

const shortTime = (d) => d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
const firstName = (n) => String(n || "Someone").trim().split(/\s+/)[0];

/** "Sam ~7:05", "Sam arrived", "Sam ~15 min late" (same as GroupETA.short in the app). */
function etaShort(e, isMe) {
  const who = isMe ? "You" : firstName(e.name);
  const at = toDate(e.eta);
  if (e.status === "arrived") return `${who} arrived`;
  if (e.status === "late") {
    if (typeof e.lateMinutes === "number") return `${who} ~${e.lateMinutes} min late`;
    return at ? `${who} late, ~${shortTime(at)}` : `${who} running late`;
  }
  return at ? `${who} ~${shortTime(at)}` : `${who} on the way`;
}

/** "Sam ~7:05 · Alex ~7:12 · Jo hasn't left" (ArrivalBoard in the app). */
function arrivalLine() {
  const sorted = [...etas].sort((a, b) => {
    if ((a.status === "arrived") !== (b.status === "arrived")) return a.status === "arrived" ? -1 : 1;
    const ta = toDate(a.eta)?.getTime() ?? Infinity, tb = toDate(b.eta)?.getTime() ?? Infinity;
    return ta - tb;
  });
  const parts = sorted.map((e) => etaShort(e, e.userID === uid));
  const shared = new Set(etas.map((e) => e.userID));
  const notYet = members.filter((m) => !shared.has(m.id)).map((m) => (m.id === uid ? "you" : firstName(m.name)));
  if (notYet.length) {
    parts.push(notYet.length === 1 && notYet[0] === "you" ? "you haven’t left"
      : notYet.length === 1 ? `${notYet[0]} hasn’t left`
      : notYet.length <= 3 ? `${notYet.join(", ")} haven’t left` : `${notYet.length} haven’t left`);
  }
  return parts.join(" · ");
}

function renderOnMyWay(winner) {
  const box = $("omw");
  const meet = toDate(session.meetTime);
  if (!omwRelevant(meet)) { box.hidden = true; return; }
  box.hidden = false;
  const mine = etas.find((e) => e.userID === uid);
  $("omw-line").textContent = etas.length ? arrivalLine() : "Nobody’s left yet";
  $("omw-go").hidden = !!mine;
  $("omw-go").disabled = omwBusy;
  $("omw-going").hidden = !mine || mine.status === "arrived";
  for (const chip of document.querySelectorAll("#omw [data-late]")) {
    const v = chip.dataset.late;
    const on = mine?.status === "late" && (v === "text" ? mine.lateNote === "text" : mine.lateMinutes === Number(v));
    chip.setAttribute("aria-pressed", on ? "true" : "false");
    chip.disabled = omwBusy;
  }
  $("omw-here").disabled = $("omw-stop").disabled = omwBusy;
  if (!$("omw-help").dataset.error) {
    $("omw-help").textContent = mine?.status === "arrived" ? "You’re here. Enjoy!"
      : "Shares when you’ll get there, never where you are. The Tablewhere app keeps it updated as you drive.";
  }
  box.dataset.winner = winner.id;
}

function omwError(text) {
  $("omw-help").dataset.error = "1";
  $("omw-help").textContent = text;
}

/** Your position, once (null if you say no or it times out). */
function hereOnce() {
  return new Promise((resolve) => {
    if (!navigator.geolocation) return resolve(null);
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lon: p.coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 60000 });
  });
}

/** Driving time from `from` to `to`, in seconds (null when there's no route). */
async function driveSeconds(from, to) {
  if (!mapkitToken) return null;
  let mk;
  try { mk = await loadMapKit(); } catch { return null; }
  if (typeof mk.Directions !== "function") return null;
  return new Promise((resolve) => {
    try {
      new mk.Directions().route({
        origin: new mk.Coordinate(from.lat, from.lon),
        destination: new mk.Coordinate(to.lat, to.lon),
        transportType: mk.Directions.Transport.Automobile,
      }, (error, data) => resolve(error ? null : (data?.routes?.[0]?.expectedTravelTime ?? null)));
    } catch { resolve(null); }
  });
}

async function writeETA(fields) {
  await ensureJoined();
  const data = {
    userID: uid,
    name: String(myName() || "Someone").slice(0, 40),
    updatedAt: serverTimestamp(),
    ...fields,
  };
  if (data.eta instanceof Date) data.etaLabel = shortTime(data.eta);
  await setDoc(doc(sessionRef, "eta", uid), data);
}

async function omwAction(work) {
  if (omwBusy) return;
  if (!myName()) {
    pendingOMW = () => omwAction(work);
    render();
    $("name-input").focus();
    return;
  }
  omwBusy = true;
  delete $("omw-help").dataset.error;
  render();
  try {
    await work();
  } catch {
    omwError(navigator.onLine === false ? "You’re offline. Check your connection and try again."
      : "That didn’t go through. Reload to see the latest.");
  } finally {
    omwBusy = false;
    render();
  }
}

function wireOnMyWay() {
  $("omw-go").addEventListener("click", () => omwAction(async () => {
    const winner = (session.options || []).find((o) => o.id === session.winnerID);
    if (!winner) return;
    const place = { lat: Number(winner.latitude), lon: Number(winner.longitude) };
    const here = await hereOnce();
    if (here && milesBetween(here, place) * 1609.34 <= 100) {
      await writeETA({ status: "arrived", eta: new Date(), leftAt: new Date() });
      return;
    }
    const secs = here ? await driveSeconds(here, place) : null;
    const eta = typeof secs === "number" ? new Date(Date.now() + secs * 1000) : null;
    await writeETA({ status: "onTheWay", leftAt: new Date(), ...(eta ? { eta } : {}) });
    if (!here) omwError("Location is off, so friends see that you’re on the way, without a time.");
  }));
  for (const chip of document.querySelectorAll("#omw [data-late]")) {
    chip.addEventListener("click", () => omwAction(async () => {
      const meet = toDate(session.meetTime);
      const v = chip.dataset.late;
      const mine = etas.find((e) => e.userID === uid);
      const keep = mine?.leftAt ? { leftAt: toDate(mine.leftAt) } : {};
      if (v === "text") await writeETA({ status: "late", lateNote: "text", ...keep });
      else await writeETA({ status: "late", lateMinutes: Number(v), eta: new Date(meet.getTime() + Number(v) * 60000), ...keep });
    }));
  }
  $("omw-here").addEventListener("click", () => omwAction(() => writeETA({ status: "arrived", eta: new Date() })));
  $("omw-stop").addEventListener("click", () => omwAction(() => deleteDoc(doc(sessionRef, "eta", uid))));
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
let panelOpen = false;
let justAdded = null;     // option id added on this page a moment ago (pops the card once)

// "Your pick is in" card at the top while waiting on the others. It replaces
// the add button; "Change my pick" opens the picker again (swaps in place).
function renderPickConfirm(mine, open) {
  const card = $("pick-confirm");
  const showIt = !!mine && open && !isSurprise();
  card.hidden = !showIt;
  if (!showIt) return;
  const head = $("pick-confirm-head");
  head.replaceChildren(isSpin() ? "Your pick is in: " : "Your place is in the vote: ");
  const b = document.createElement("b");
  b.textContent = mine.name;
  head.append(b, ".");
  $("pick-confirm-sub").textContent = isSpin()
    ? "We’ll show the result here when the wheel spins. Keep this page open to watch it, or get the Tablewhere app and we’ll let you know."
    : "Now tap a place below to vote. The winner shows up right here.";
  const change = $("pick-change");
  change.textContent = isSpin() ? "Change my pick" : "Change my place";
  change.hidden = !mapkitToken || panelOpen;
  if (justAdded === mine.id) {
    justAdded = null;
    card.classList.remove("pop");
    void card.offsetWidth;  // restart the animation
    card.classList.add("pop");
  }
}

function updateSuggest() {
  const open = acceptsChanges();
  const full = (session.options || []).length >= MAX_OPTIONS;
  const mine = myPick();
  renderPickConfirm(mine, open);
  $("suggest").hidden = !mapkitToken || !open || isSurprise() || (!!mine && !panelOpen);
  const button = $("suggest-open");
  button.style.width = "100%";
  button.hidden = panelOpen || !!mine;
  button.className = isSpin() && !full ? "btn primary wide" : "btn ghost wide";
  button.textContent = full
    ? (isSpin() ? "The wheel is full (12 places)" : "This vote is full (12 places)")
    : (isSpin() ? "+ Add your pick" : "+ Suggest a place (one each)");
  button.disabled = full;
  if (full && !mine && panelOpen) closeSuggest();
  if (!suggestWired && mapkitToken) wireSuggest();
}

async function openSuggest() {
  $("suggest-input").placeholder = myPick() ? "Search for a place to swap in" : "Search by name or craving, like “tacos”";
  panelOpen = true;
  updateSuggest();
  $("suggest-panel").hidden = false;
  if (myPick()) $("suggest").scrollIntoView({ behavior: "smooth", block: "start" });
  // Phones: don't pop the keyboard over the map and list; the nearby list needs no typing.
  if (!matchMedia("(pointer: coarse)").matches) $("suggest-input").focus();
  // Usually already found in the background (or cached): show it now.
  prefetchNearby();
  if (!nearby || (!nearby.done && !nearby.places.length)) showSkeleton();
  showNearby();
  let mk;
  try {
    mk = await loadMapKit();
  } catch {
    setStatus("Search isn’t available right now. You can still vote.");
    return;
  }
  if (!panelOpen) return;
  const center = groupCenter();
  if (center) showPickMap(mk, center);
  if (!$("suggest-input").value.trim()) showNearby();
}

function wireSuggest() {
  suggestWired = true;
  $("suggest-open").addEventListener("click", openSuggest);
  $("pick-change").addEventListener("click", openSuggest);
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
  panelOpen = false;
  ++searchSeq;
  ++renderSeq;
  $("suggest-panel").hidden = true;
  $("suggest-input").value = "";
  $("suggest-results").replaceChildren();
  $("suggest-list-label").hidden = true;
  setStatus("");
  clearPickMap();
  if (session) updateSuggest();
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
  if (query.length < 2) { showNearby(); return; }
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

  const places = mergePlaces(batches.filter(Array.isArray).map((b) => b.map((p) => fromMapKit(p, null)).filter(Boolean)), center)
    .slice(0, 20);
  renderResults(places, query);
}

// ---------------------------------------------------------------------------
// Nearby: what's around the group area, nearest first, no typing needed.
// Searched like the app (MapKitPlaceSearch): Apple's category lookup plus
// "restaurant" and a few types it leaves out, all at once, merged (same name
// within ~60 m is one place). Started in the background as soon as the page
// shows a plan that takes picks, so the panel opens with the list ready, and
// kept for 10 minutes per group area (like the app's SearchCache), so
// reopening it or "Change my pick" is instant. 5 searches per area.

const NEARBY_RADIUS_M = 3219;   // 2 miles, the group picker's default
const NEARBY_TTL_MS = 10 * 60 * 1000;
// Same as MapKitPlaceSearch.typeQueries, trimmed to the ones that bring back
// the most (MapKit JS has a daily quota). The label becomes the place's type
// when Apple's category is just "restaurant".
const NEARBY_TYPES = [["burgers", "Burgers"], ["pizza", "Pizza"], ["fast food", "Fast food"]];

// { key, center, batches: [places[] | null | undefined], places: [...], done, failed }
let nearby = null;

function nearbyKey(center) {
  const r = (x) => Math.round(x * 2000) / 2000;   // about 50 m, like SearchCache.key
  return `forkroad.nearby.${r(center.lat)}|${r(center.lon)}`;
}

function readNearbyCache(key) {
  try {
    const saved = JSON.parse(sessionStorage.getItem(key) || "null");
    if (!saved || !Array.isArray(saved.places) || Date.now() - saved.savedAt > NEARBY_TTL_MS) return null;
    return saved.places;
  } catch { return null; }
}

function writeNearbyCache(key, places) {
  try { sessionStorage.setItem(key, JSON.stringify({ savedAt: Date.now(), places })); } catch { /* full or blocked */ }
}

/** Starts the Nearby search for this plan's area (once per area, or from the cache). */
function prefetchNearby() {
  if (!session || !mapkitToken || isSurprise() || !acceptsChanges()) return;
  const center = groupCenter();
  if (!center) return;
  const key = nearbyKey(center);
  if (nearby && nearby.key === key && !nearby.failed) return;
  const cached = readNearbyCache(key);
  if (cached) {
    nearby = { key, center, batches: [], places: cached, done: true, failed: false };
    onNearbyChange();
    return;
  }
  const mine = { key, center, batches: [], places: [], done: false, failed: false };
  nearby = mine;
  onNearbyChange();
  loadMapKit()
    .then((mk) => runNearby(mk, mine))
    .catch(() => {
      mine.done = true;
      mine.failed = true;
      if (nearby === mine) onNearbyChange();
    });
}

// Once per page, when the browser is idle (the plan shows first).
let prefetchScheduled = false;
function schedulePrefetch() {
  if (prefetchScheduled || !mapkitToken) return;
  if (!session || isSurprise() || !acceptsChanges()) return;
  prefetchScheduled = true;
  const go = () => { prefetchScheduled = false; prefetchNearby(); };
  if ("requestIdleCallback" in window) requestIdleCallback(go, { timeout: 1500 });
  else setTimeout(go, 300);
}

function runNearby(mk, mine) {
  const { center } = mine;
  const coord = new mk.Coordinate(center.lat, center.lon);
  const filter = restaurantFilter(mk);
  const degLat = (NEARBY_RADIUS_M * 2) / 111000;
  const region = new mk.CoordinateRegion(coord,
    new mk.CoordinateSpan(degLat, degLat / Math.max(0.2, Math.cos(center.lat * Math.PI / 180))));

  // Apple's category lookup (places by category, not words).
  const poi = () => new Promise((resolve) => {
    if (typeof mk.PointsOfInterestSearch !== "function") return resolve(null);
    try {
      const options = { center: coord, radius: NEARBY_RADIUS_M };
      if (filter) options.pointOfInterestFilter = filter;
      new mk.PointsOfInterestSearch(options).search((error, data) => resolve(error ? null : (data?.places || [])));
    } catch { resolve(null); }
  });
  const text = (query) => new Promise((resolve) => {
    try {
      const options = { region, includeAddresses: false, includeQueries: false, includePointsOfInterest: true };
      if (filter) options.pointOfInterestFilter = filter;
      new mk.Search(options).search(query, (error, data) => resolve(error ? null : (data?.places || [])), { region });
    } catch { resolve(null); }
  });

  // Job order (not finish order) decides a place's type, like the app.
  const jobs = [
    { run: () => text("restaurant"), label: null },
    { run: poi, label: null },
    ...NEARBY_TYPES.map(([query, label]) => ({ run: () => text(query), label })),
  ];
  mine.batches = jobs.map(() => undefined);   // undefined: still searching
  const finished = jobs.map((job, index) => job.run().then((raw) => {
    mine.batches[index] = raw === null ? null
      : raw.map((p) => fromMapKit(p, job.label))
        .filter((p) => p && !isNotARestaurant(p.name))
        .filter((p) => milesBetween(center, { lat: p.latitude, lon: p.longitude }) * 1609.34 <= NEARBY_RADIUS_M);
    mine.places = mergePlaces(mine.batches.filter(Array.isArray), center);
    if (nearby === mine) onNearbyChange();
  }));
  Promise.all(finished).then(() => {
    mine.done = true;
    mine.failed = mine.batches.every((b) => b === null);
    // Don't keep a partial list for 10 minutes (one search failed).
    if (!mine.batches.includes(null)) writeNearbyCache(mine.key, mine.places);
    if (nearby === mine) onNearbyChange();
  });
}

/** A MapKit JS place as a plain object (kept in the cache). */
function fromMapKit(p, label) {
  if (!p || !p.name || !p.coordinate) return null;
  const lat = p.coordinate.latitude, lon = p.coordinate.longitude;
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  const place = { name: p.name, latitude: lat, longitude: lon, category: categoryLabel(p, label) };
  if (p.formattedAddress) place.address = p.formattedAddress;
  if (p.telephone) place.phone = p.telephone;
  const url = Array.isArray(p.urls) ? p.urls[0] : p.url;
  if (typeof url === "string" && /^https?:\/\//i.test(url)) place.url = url;
  return place;
}

/** MapKitPlaceSearch.merge: one entry per place, the most specific type, nearest first. */
function mergePlaces(batches, center) {
  const out = [];
  for (const place of batches.flat()) {
    const name = place.name.toLowerCase();
    const match = out.find((o) => o.name.toLowerCase() === name
      && milesBetween({ lat: o.latitude, lon: o.longitude }, { lat: place.latitude, lon: place.longitude }) * 1609.34 < 60);
    if (match) {
      if (match.category === "Restaurant" && place.category !== "Restaurant") match.category = place.category;
    } else {
      out.push({ ...place });
    }
  }
  for (const p of out) p.miles = milesBetween(center, { lat: p.latitude, lon: p.longitude });
  return out.sort((a, b) => a.miles - b.miles);
}

function restaurantFilter(mk) {
  try {
    const C = mk.PointOfInterestCategory;
    return mk.PointOfInterestFilter.including([C.Restaurant, C.Cafe, C.Bakery, C.Brewery, C.Winery].filter(Boolean));
  } catch { return null; }
}

/** New Nearby results (or done): redraw the list if it's showing. */
function onNearbyChange() {
  if (!panelOpen || $("suggest-input").value.trim().length >= 2) return;
  if (pressingResults) { nearbyWaiting = true; return; }
  showNearby();
}

// Rebuilding the list under a finger moves rows; wait until it lifts.
let pressingResults = false;
let nearbyWaiting = false;
document.addEventListener("pointerdown", (e) => {
  if (e.target.closest && e.target.closest("#suggest-results")) pressingResults = true;
}, true);
const endResultsPress = () => {
  if (!pressingResults) return;
  pressingResults = false;
  if (nearbyWaiting) setTimeout(() => { nearbyWaiting = false; onNearbyChange(); }, 0);
};
document.addEventListener("pointerup", endResultsPress, true);
document.addEventListener("pointercancel", endResultsPress, true);

function showNearby() {
  ++searchSeq;  // a search still in flight shouldn't replace the nearby list
  if (!nearby) {
    if (!groupCenter()) { $("suggest-results").replaceChildren(); setStatus("Search for a place by name or craving."); }
    return;
  }
  if (nearby.done && nearby.failed && !nearby.places.length) {
    $("suggest-results").replaceChildren();
    $("suggest-list-label").hidden = true;
    setStatus("Couldn’t load places nearby. Search by name instead.", true);
    return;
  }
  renderResults(nearby.places, null, !nearby.done);
}

function showSkeleton(rows = 5) {
  const list = $("suggest-results");
  list.replaceChildren();
  for (let i = 0; i < rows; i++) {
    const row = document.createElement("div");
    row.className = "result skeleton";
    row.setAttribute("aria-hidden", "true");
    row.innerHTML = `<div class="tile"></div><div class="lines"><span></span><span></span></div>`;
    list.append(row);
  }
  $("suggest-list-label").textContent = "Nearby";
  $("suggest-list-label").hidden = false;
}

// A small map of the group area with a pin per place in the list. Tap a pin,
// then Add (or Swap) in its bubble: same as tapping the row. Pins are kept
// and only added or removed as the list changes; the map fits them once.
let pickMap = null;
let pins = new Map();          // key → { pin, state }
let fittedFor = null;          // the list the map last fit (once per open / search)
function showPickMap(mk, center) {
  const box = $("suggest-map");
  box.hidden = false;
  const coord = new mk.Coordinate(center.lat, center.lon);
  const region = new mk.CoordinateRegion(coord, new mk.CoordinateSpan(0.045, 0.045));
  if (!pickMap) {
    pickMap = new mk.Map(box, {
      region,
      colorScheme: mk.Map.ColorSchemes.Dark,
      isRotationEnabled: false,
      showsCompass: mk.FeatureVisibility.Hidden,
      showsMapTypeControl: false,
      showsZoomControl: false,
      showsPointsOfInterest: false,
    });
    pickMap.addEventListener("select", (event) => {
      const id = event.annotation?.data?.optionID;
      if (!id) return;
      const row = [...$("suggest-results").children].find((r) => r.dataset.id === id);
      if (row) {
        row.scrollIntoView({ behavior: "smooth", block: "nearest" });
        row.classList.add("flash");
        setTimeout(() => row.classList.remove("flash"), 1200);
      }
    });
  } else if (fittedFor === null) {
    pickMap.region = region;
  }
}

function clearPickMap() {
  if (pickMap) pickMap.removeAnnotations(pickMap.annotations);
  pins = new Map();
  fittedFor = null;
}

async function updatePickMap(rows, listId, final) {
  if (!pickMap) return;
  let mk;
  try { mk = await loadMapKit(); } catch { return; }
  const wanted = new Map();
  for (const { option, out, taken } of rows) {
    if (out) continue;
    wanted.set(option.id, { option, taken, state: taken ? "taken" : myPick() ? "swap" : "add" });
  }
  // The places already in the wheel, as grey checks, so you can see what's taken.
  for (const o of session.options || []) {
    if (!Number.isFinite(o.latitude) || !Number.isFinite(o.longitude) || rows.some((r) => sameOption(r.option, o))) continue;
    wanted.set(`in|${o.id}`, { option: o, taken: true, state: "taken" });
  }
  const remove = [];
  for (const [key, held] of pins) {
    if (wanted.get(key)?.state !== held.state) { remove.push(held.pin); pins.delete(key); }
  }
  if (remove.length) pickMap.removeAnnotations(remove);
  const add = [];
  for (const [key, { option, taken, state }] of wanted) {
    if (pins.has(key)) continue;
    const pin = new mk.MarkerAnnotation(new mk.Coordinate(option.latitude, option.longitude), {
      color: taken ? "#5C5A66" : "#FFB23F",
      glyphText: taken ? "✓" : "🍴",
      title: option.name,
      subtitle: taken ? (isSpin() ? "In the wheel" : "In the vote") : option.category,
      data: taken ? {} : { optionID: option.id },
      displayPriority: taken ? 250 : 750,
    });
    if (!taken) {
      pin.callout = {
        calloutRightAccessoryForAnnotation: () => {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "pin-add";
          button.textContent = state === "swap" ? "Swap" : "Add";
          button.addEventListener("click", (e) => { e.stopPropagation(); addOption(option); });
          return button;
        },
      };
    }
    pins.set(key, { pin, state });
    add.push(pin);
  }
  if (add.length) pickMap.addAnnotations(add);
  // Fit once per list, when it's complete, so the map doesn't jump as batches land.
  if (final && fittedFor !== listId) {
    fittedFor = listId;
    const open = [...pins.values()].filter((h) => h.state !== "taken").map((h) => h.pin).slice(0, 12);
    if (open.length) {
      try { pickMap.showItems(open, { animate: false, padding: new mk.Padding(36, 28, 24, 28) }); } catch { /* keep the area */ }
    }
  }
}

let renderSeq = 0;
/** `loading`: Nearby is still searching (more rows may come). */
async function renderResults(places, query, loading = false) {
  const seq = ++renderSeq;
  const blocked = globalThis.crypto?.subtle ? groupBlocked() : new Set();
  const outIDs = new Set();
  if (blocked.size) {
    for (const p of places) {
      const id = toOption(p).id;
      if (blocked.has(await blockedHash(id))) outIDs.add(id);
    }
  }
  if (seq !== renderSeq) return;   // a newer list took over while hashing
  const isNearby = query === null;
  const rows = places.map((p) => {
    const option = toOption(p);
    const out = outIDs.has(option.id);
    const rule = groupFilterRule(option);
    return { option, miles: p.miles, out, rule, taken: isTaken(option) };
  }).filter((r) => !isNearby || (!r.out && !r.taken && !r.rule)).slice(0, isNearby ? 15 : 20);
  const list = $("suggest-results");
  $("suggest-list-label").textContent = isNearby ? "Nearby" : "Results";
  if (isNearby && loading && !rows.length) {
    showSkeleton();
    setStatus("Finding places nearby…");
    return;
  }
  list.replaceChildren();
  $("suggest-list-label").hidden = !rows.length;
  updatePickMap(rows.filter((r) => !r.rule), isNearby ? `nearby|${nearby?.key}` : `q|${query}|${seq}`, !loading);
  if (!rows.length) {
    setStatus(isNearby ? "Couldn’t find restaurants near the group area. Search by name above."
      : `No restaurants found for “${query}”. Try a broader word like “pizza.”`);
    return;
  }
  setStatus(isNearby ? (loading ? "Finding more places…" : "Tap one to add it, or search above.") : "");
  for (const { option, miles, out, rule, taken: inIt } of rows) {
    const taken = inIt || out || !!rule;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "result" + (rule ? " not-allowed" : "");
    button.disabled = taken || adding;
    button.dataset.taken = taken ? "1" : "0";
    button.dataset.id = option.id;

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
    sub.textContent = rule ? `Not allowed in this group (${rule})`
      : `${option.category} · ${miles < 0.1 ? "<0.1" : miles < 10 ? miles.toFixed(1) : Math.round(miles)} mi${option.address ? " · " + option.address : ""}`;
    text.append(name, sub);
    const add = document.createElement("span");
    add.className = "add";
    const mine = myPick();
    add.textContent = rule ? "" : out ? "Ruled out"
      : taken ? (isSpin() ? "In the wheel" : "In the vote")
      : mine ? "Swap" : "Add";
    button.append(tile, text, add);
    button.addEventListener("click", () => addOption(option));
    list.append(button);
  }
  if (isNearby && loading) {
    // More are coming: a couple of skeleton rows at the bottom.
    for (let i = 0; i < 2; i++) {
      const row = document.createElement("div");
      row.className = "result skeleton";
      row.setAttribute("aria-hidden", "true");
      row.innerHTML = `<div class="tile"></div><div class="lines"><span></span><span></span></div>`;
      list.append(row);
    }
  }
}

/** Apple's category, or (when it only says "restaurant") the type search that found it or the name. */
function categoryLabel(place, label = null) {
  switch (place.pointOfInterestCategory) {
    case "Cafe": return "Café";
    case "Bakery": return "Bakery";
    case "Brewery": return "Brewery";
    case "Winery": return "Winery";
    case "FoodMarket": return "Market";
    default: return label || guessCuisine(place.name || "") || "Restaurant";
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

/** A plain place (see fromMapKit) as a vote/wheel option. */
function toOption(place) {
  const lat = place.latitude, lon = place.longitude;
  const option = {
    id: makeID(place.name, lat, lon),
    name: place.name,
    category: place.category || "Restaurant",
    latitude: lat,
    longitude: lon,
    addedBy: myName() || "A friend",
    addedByID: uid,
  };
  // Optional fields are left out when missing, matching the app.
  if (place.address) option.address = place.address;
  if (place.phone) option.phoneNumber = place.phone;
  if (place.url) option.websiteURL = place.url;
  return option;
}

// Apple Maps on the web and on iPhone can disagree by a few meters, so a
// place with the same name within ~150 m also counts as already added.
function sameOption(a, b) {
  if (a.id === b.id) return true;
  return a.name.trim().toLowerCase() === b.name.trim().toLowerCase()
    && milesBetween({ lat: a.latitude, lon: a.longitude }, { lat: b.latitude, lon: b.longitude }) < 0.1;
}
/** Why the group's filters don't allow this place ("no fast food"), or null.
 * Same as GroupFilters.rule in the app (food-filters.js is generated from its lists). */
function groupFilterRule(option, plan = session) {
  const f = plan?.groupFilters;
  if (!f || typeof f !== "object" || plan.mode === "plan" || (plan.mode === "spin" && plan.surprise === true)) return null;
  if (f.noFastFood === true && (isFastFood(option.name) || option.category === "Fast food")) return "no fast food";
  if (f.noCoffeeSweets === true && isCoffeeOrSweets(option.name, option.category || "")) return "no coffee & sweets";
  return null;
}

/** "No fast food in this group", or null. */
function groupFiltersSummary() {
  const f = session?.groupFilters;
  if (!f || isSurprise() || isPlan() || !acceptsChanges()) return null;
  if (f.noFastFood === true && f.noCoffeeSweets === true) return "No fast food or coffee & sweets in this group";
  if (f.noFastFood === true) return "No fast food in this group";
  if (f.noCoffeeSweets === true) return "No coffee & sweets in this group";
  return null;
}

function showFiltersLine() {
  const text = groupFiltersSummary();
  $("filters-line").hidden = !text;
  $("filters-line").textContent = text ? `⛔︎ ${text}` : "";
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
      // The organizer may have turned a filter on after this page loaded.
      const rule = groupFilterRule(option, data);
      if (rule) throw Object.assign(new Error("notAllowed"), { rule });
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
    justAdded = option.id;
    closeSuggest();
    $("pick-confirm").scrollIntoView({ behavior: "smooth", block: "center" });
  } catch (error) {
    const messages = {
      duplicate: isSpin() ? "That place is already in the wheel." : "That place is already in the vote.",
      full: "This pick already has 12 places, the most it can hold.",
      closed: "Voting has closed, so places can’t be added.",
      ended: "This group plan has ended.",
      picked: "You’ve already added your pick. Everyone gets one.",
      notAllowed: `That place isn’t allowed in this group (${error?.rule}).`,
    };
    setStatus(messages[error?.message] || "Couldn’t add it. Check your connection and try again.", true);
    // Let them pick something else (places already in the vote stay disabled).
    [...$("suggest-results").children].forEach((b) => { b.disabled = b.dataset.taken === "1"; });
  } finally {
    adding = false;
  }
}
