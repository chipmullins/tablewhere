// ForkRoad web vote page: https://<host>/v/<sessionId>
// Same Firestore data as the app and iMessage extension.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth, signInAnonymously, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import {
  getFirestore, doc, collection, onSnapshot, setDoc, deleteDoc, serverTimestamp
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";

const $ = (id) => document.getElementById(id);
const sections = ["loading", "error", "name-step", "vote-step", "decided-step"];

function show(id) {
  sections.forEach((s) => { $(s).hidden = s !== id; });
}

function fail(message) {
  $("error-text").textContent = message;
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

function formatTime(ts) {
  if (!ts) return null;
  const date = ts.toDate ? ts.toDate() : new Date(ts);
  return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

const sessionId = (location.pathname.match(/^\/v\/([^/]+)/) || [])[1];
if (!sessionId) {
  fail("This link is missing its vote ID. Ask whoever sent it to share it again.");
  throw new Error("No session id");
}

// Loaded dynamically so a missing config shows a message instead of hanging on "Loading…".
let firebaseConfig;
try {
  ({ firebaseConfig } = await import("./firebase-config.js"));
} catch {
  fail("This vote page isn’t set up yet. (Missing firebase-config.js — see the README.)");
  throw new Error("Missing firebase-config.js");
}

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const sessionRef = doc(db, "sessions", sessionId);

let uid = null;
let session = null;
let votes = [];
let members = [];
let busy = false;
const NAME_KEY = "forkroad.name";

onAuthStateChanged(auth, (user) => {
  if (user) { uid = user.uid; start(); }
});
signInAnonymously(auth).catch(() => fail("Couldn’t connect. Check your connection and reload."));

let started = false;
function start() {
  if (started) return;
  started = true;

  onSnapshot(sessionRef, (snap) => {
    if (!snap.exists()) return fail("This vote doesn’t exist anymore.");
    session = snap.data();
    render();
  }, () => fail("Couldn’t load this vote."));

  onSnapshot(collection(sessionRef, "votes"), (snap) => {
    votes = snap.docs.map((d) => d.data());
    render();
  });

  onSnapshot(collection(sessionRef, "members"), (snap) => {
    members = snap.docs.map((d) => d.data());
    render();
  });

  $("name-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const name = $("name-input").value.trim().slice(0, 30);
    if (!name) return;
    localStorage.setItem(NAME_KEY, name);
    await join(name);
    render();
  });
}

async function join(name) {
  await setDoc(doc(sessionRef, "members", uid), { id: uid, name, joinedAt: serverTimestamp() });
}

function myName() {
  return localStorage.getItem(NAME_KEY);
}

let joinedOnce = false;
function render() {
  if (!session) return;
  $("code").textContent = formatCode(session.joinCode);
  $("footer").hidden = false;

  // Anyone opening the link after the group decided sees the result right away.
  if (session.status === "decided" && session.winnerID) {
    renderDecided();
    return;
  }

  const name = myName();
  if (!name) {
    $("name-title").textContent = session.title || "Help pick dinner";
    $("name-sub").textContent = `${session.createdByName || "A friend"} wants help deciding where to eat.`;
    show("name-step");
    return;
  }
  if (!joinedOnce && !members.some((m) => m.id === uid)) {
    joinedOnce = true;
    join(name).catch(() => {});
  }

  renderVote();
}

function tally() {
  const ids = new Set((session.options || []).map((o) => o.id));
  const counts = {}, voters = {};
  for (const v of votes) {
    if (!ids.has(v.optionID)) continue;
    counts[v.optionID] = (counts[v.optionID] || 0) + 1;
    (voters[v.optionID] = voters[v.optionID] || []).push(v.voterName);
  }
  const top = Math.max(0, ...Object.values(counts));
  const leaders = top === 0 ? [] : Object.keys(counts).filter((id) => counts[id] === top);
  return { counts, voters, leader: leaders.length === 1 ? leaders[0] : null, total: Object.values(counts).reduce((a, b) => a + b, 0) };
}

function statusText() {
  const waiting = Math.max(0, members.length - votes.length);
  let text = `${members.length} in the group · ` +
    (waiting === 0 ? "everyone has voted" : `waiting on ${waiting} vote${waiting === 1 ? "" : "s"}`);
  const closes = session.closesAt && session.closesAt.toDate ? session.closesAt.toDate() : null;
  if (closes) {
    const left = Math.max(0, Math.floor((closes - Date.now()) / 1000));
    text += left > 0 ? ` · closes in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : " · voting closed";
  }
  return text;
}

// Keep the countdown ticking without rebuilding the buttons.
setInterval(() => {
  if (session && !$("vote-step").hidden) $("status").textContent = statusText();
}, 1000);

function renderVote() {
  const t = tally();
  const mine = votes.find((v) => v.voterID === uid)?.optionID;
  const slots = Math.max(members.length, t.total, 1);

  $("title").textContent = session.title;
  $("status").textContent = statusText();

  const list = $("options");
  list.replaceChildren();
  for (const option of session.options || []) {
    const count = t.counts[option.id] || 0;
    const lead = t.leader === option.id;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "option" + (mine === option.id ? " mine" : "") + (lead ? " lead" : "");
    button.disabled = busy;
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
    if (lead) {
      const pill = document.createElement("span");
      pill.className = "pill";
      pill.textContent = "LEADING";
      nameEl.append(pill);
    }
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = (t.voters[option.id] || []).join(", ") || `${option.category} · added by ${option.addedBy}`;
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
      await setDoc(ref, { voterID: uid, voterName: myName(), optionID: optionId, votedAt: serverTimestamp() });
    }
  } catch {
    alert("Couldn’t save your vote. The vote may have closed.");
  } finally {
    busy = false;
    render();
  }
}

function renderDecided() {
  const winner = (session.options || []).find((o) => o.id === session.winnerID);
  if (!winner) return renderVote();
  $("winner-name").textContent = winner.name;
  const time = formatTime(session.meetTime);
  $("winner-detail").textContent = time ? `Meet at ${time}` : winner.category;

  const q = encodeURIComponent(winner.name);
  $("apple-maps").href = `https://maps.apple.com/?daddr=${winner.latitude},${winner.longitude}&q=${q}`;
  $("google-maps").href = `https://www.google.com/maps/dir/?api=1&destination=${winner.latitude},${winner.longitude}`;
  const site = $("website");
  if (winner.websiteURL && /^https?:\/\//i.test(winner.websiteURL)) {
    site.href = winner.websiteURL;
    site.hidden = false;
  } else {
    site.hidden = true;
  }
  show("decided-step");
}
