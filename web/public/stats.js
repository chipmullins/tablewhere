// ForkRoad stats page: https://forkroad-app.web.app/stats
// Reads stats/{yyyy-mm-dd} (anonymous daily counts written by the app, the
// iMessage app, and the vote page). Only admins can read them; an admin is a
// Google account with a document at admins/{uid} (see firestore.rules).
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import {
  getAuth, onAuthStateChanged, signInWithPopup, GoogleAuthProvider, signOut
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import {
  getFirestore, doc, getDoc, collection, query, where, getDocs, documentId
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";

const $ = (id) => document.getElementById(id);
const sections = ["loading", "signin", "not-admin", "error", "dashboard"];
const show = (id) => sections.forEach((s) => { $(s).hidden = s !== id; });
const fail = (message) => { $("error-text").textContent = message; show("error"); };

let firebaseConfig;
try {
  ({ firebaseConfig } = await import("./firebase-config.js"));
} catch {
  fail("This page isn’t set up yet. (Missing firebase-config.js — see the README.)");
  throw new Error("Missing firebase-config.js");
}

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

// What's counted, in the order the table shows it. Matches UsageStat in the app.
const FIELDS = [
  ["activeDevices", "Active devices"],
  ["newDevices", "New devices"],
  ["spins", "Spins"],
  ["groupsVote", "Group votes"],
  ["groupsSpin", "Group spins"],
  ["groupPicks", "Places added to groups"],
  ["customPlaces", "Own restaurants added"],
  ["webVisitors", "Web visitors"],
  ["webVotes", "Web votes"],
  ["webPicks", "Web picks"],
];

let days = 30;
let rows = [];  // [{ day: "2026-10-31", activeDevices: 3, ... }], oldest first

// ---------------------------------------------------------------- auth

$("sign-in").addEventListener("click", async () => {
  $("signin-error").textContent = "";
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
  } catch (e) {
    $("signin-error").textContent = e?.code === "auth/operation-not-allowed"
      ? "Google sign-in isn’t turned on yet: Firebase console → Authentication → Sign-in method → Google."
      : "Couldn’t sign in. Try again.";
  }
});
$("sign-out").addEventListener("click", () => signOut(auth));
$("copy-uid").addEventListener("click", () => {
  navigator.clipboard?.writeText($("my-uid").textContent);
  $("copy-uid").textContent = "Copied";
});

onAuthStateChanged(auth, async (user) => {
  if (!user || user.isAnonymous) {
    $("who").hidden = true;
    show("signin");
    return;
  }
  $("who").hidden = false;
  $("who-email").textContent = user.email || "Signed in";
  try {
    const admin = await getDoc(doc(db, "admins", user.uid));
    if (!admin.exists()) {
      $("my-uid").textContent = user.uid;
      show("not-admin");
      return;
    }
  } catch {
    $("my-uid").textContent = user.uid;
    show("not-admin");
    return;
  }
  show("dashboard");
  await load();
});

// ---------------------------------------------------------------- data

const isoDay = (date) => date.toISOString().slice(0, 10);
function lastDays(n) {
  const out = [];
  const today = new Date();
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() - i));
    out.push(isoDay(d));
  }
  return out;
}

async function load() {
  $("updated").textContent = "Loading…";
  const range = lastDays(days);
  try {
    const snap = await getDocs(query(collection(db, "stats"), where(documentId(), ">=", range[0])));
    const byDay = new Map(snap.docs.map((d) => [d.id, d.data()]));
    rows = range.map((day) => {
      const data = byDay.get(day) || {};
      const row = { day };
      for (const [key] of FIELDS) row[key] = Number(data[key] || 0);
      return row;
    });
    render();
    $("updated").textContent = `Updated ${new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`;
  } catch {
    $("updated").textContent = "";
    fail("Couldn’t load stats. Check that this account is an admin and the latest rules are deployed.");
  }
}

$("range").addEventListener("click", (e) => {
  const button = e.target.closest("button[data-days]");
  if (!button) return;
  days = Number(button.dataset.days);
  for (const b of $("range").querySelectorAll("button")) b.setAttribute("aria-pressed", String(b === button));
  load();
});
$("refresh").addEventListener("click", load);

// ---------------------------------------------------------------- render

const fmt = (n) => n.toLocaleString();
const plural = (n, word) => `${fmt(n)} ${word}${n === 1 ? "" : "s"}`;
const sum = (key) => rows.reduce((a, r) => a + r[key], 0);
const shortDate = (day) => new Date(day + "T12:00:00Z").toLocaleDateString([], { month: "short", day: "numeric", timeZone: "UTC" });

function render() {
  renderTiles();
  renderCharts();
  renderTable();
}

function tile(label, value, sub) {
  const el = document.createElement("div");
  el.className = "card tile";
  const l = document.createElement("div"); l.className = "label"; l.textContent = label;
  const v = document.createElement("div"); v.className = "value"; v.textContent = value;
  const s = document.createElement("div"); s.className = "sub"; s.textContent = sub;
  el.append(l, v, s);
  return el;
}

function renderTiles() {
  const today = rows[rows.length - 1] || {};
  const avg = rows.length ? sum("activeDevices") / rows.length : 0;
  const range = `last ${days} days`;
  $("tiles").replaceChildren(
    tile("Active today", fmt(today.activeDevices || 0), "devices that opened ForkRoad"),
    tile("Daily active", avg < 10 ? avg.toFixed(1) : fmt(Math.round(avg)), `average, ${range}`),
    tile("New devices", fmt(sum("newDevices")), range),
    tile("Spins", fmt(sum("spins")), range),
    tile("Groups started", fmt(sum("groupsVote") + sum("groupsSpin")),
      `${plural(sum("groupsVote"), "vote")} · ${plural(sum("groupsSpin"), "spin")}`),
    tile("Web visitors", fmt(sum("webVisitors")), `friends without the app, ${range}`),
  );
}

// One small bar chart per measure: a single series, so the title names it
// and there's no legend. Same scale rules everywhere; hover for exact values.
const CHARTS = [
  { title: "Active devices", key: "activeDevices" },
  { title: "Spins", key: "spins" },
  { title: "Groups started", key: (r) => r.groupsVote + r.groupsSpin, note: "votes + spins" },
  { title: "Web visitors", key: "webVisitors" },
];

function niceMax(max) {
  if (max <= 4) return 4;
  const pow = 10 ** Math.floor(Math.log10(max));
  for (const step of [1, 2, 5, 10]) {
    if (step * pow >= max) return step * pow;
  }
  return 10 * pow;
}

function renderCharts() {
  const host = $("charts");
  host.replaceChildren();
  for (const chart of CHARTS) {
    const value = typeof chart.key === "function" ? chart.key : (r) => r[chart.key];
    const values = rows.map(value);
    const total = values.reduce((a, b) => a + b, 0);
    const card = document.createElement("div");
    card.className = "card chart";
    const h = document.createElement("h2"); h.textContent = chart.title;
    const t = document.createElement("div"); t.className = "total";
    t.textContent = `${fmt(total)} in the last ${days} days${chart.note ? ` (${chart.note})` : ""}`;
    card.append(h, t);
    card.dataset.title = chart.title;
    card._values = values;
    host.append(card);
  }
  // Measure after every card is in the grid, so each chart is drawn at its
  // real width (text stays the same size in every chart).
  for (const card of host.children) {
    card.append(barChart(card._values, card.clientWidth - 34, card.dataset.title));
  }
}

const SVG = "http://www.w3.org/2000/svg";
function el(name, attrs) {
  const node = document.createElementNS(SVG, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
}

function barChart(values, width, title) {
  const height = 150, left = 30, bottom = 20, top = 8;
  const plotW = Math.max(100, width - left), plotH = height - bottom - top;
  const max = niceMax(Math.max(0, ...values));
  const svg = el("svg", { viewBox: `0 0 ${width} ${height}`, width, height, role: "img",
    "aria-label": `${title} per day. The table below has every value.` });

  // Recessive grid: 0, half, max.
  for (const f of [0, 0.5, 1]) {
    const y = top + plotH - f * plotH;
    svg.append(el("line", { class: "grid", x1: left, x2: left + plotW, y1: y, y2: y }));
    const label = el("text", { class: "axis", x: left - 6, y: y + 4, "text-anchor": "end" });
    label.textContent = fmt(Math.round(max * f));
    svg.append(label);
  }

  const band = plotW / values.length;
  const gap = 2;
  const barW = Math.min(24, Math.max(2, band - gap));
  values.forEach((v, i) => {
    const x = left + i * band + (band - barW) / 2;
    const h = v === 0 ? 0 : Math.max(2, (v / max) * plotH);
    const y = top + plotH - h;
    // Hit target is the whole column, bigger than the bar.
    const hit = el("rect", { class: "hit", x: left + i * band, y: top, width: band, height: plotH });
    const r = Math.min(4, barW / 2, h);
    const bar = el("path", { class: "bar", d: roundedTop(x, y, barW, h, r) });
    hit.addEventListener("pointermove", (e) => showTip(e, rows[i].day, v, title, bar));
    hit.addEventListener("pointerleave", () => hideTip(bar));
    // The hit target sits on top of the bar so hovering the bar itself works.
    svg.append(bar, hit);
  });

  // A few date labels along the bottom.
  const ticks = values.length <= 7 ? values.map((_, i) => i) : [0, Math.floor(values.length / 2), values.length - 1];
  for (const i of ticks) {
    const label = el("text", { class: "axis", x: left + i * band + band / 2, y: height - 4,
      "text-anchor": i === 0 && values.length > 7 ? "start" : i === values.length - 1 && values.length > 7 ? "end" : "middle" });
    label.textContent = shortDate(rows[i].day);
    svg.append(label);
  }
  return svg;
}

// Bar with a 4px rounded top and a square base on the baseline.
function roundedTop(x, y, w, h, r) {
  if (h <= 0) return "";
  return `M${x},${y + h} V${y + r} Q${x},${y} ${x + r},${y} H${x + w - r} Q${x + w},${y} ${x + w},${y + r} V${y + h} Z`;
}

function showTip(e, day, value, title, bar) {
  const tip = $("tip");
  tip.replaceChildren();
  const b = document.createElement("b"); b.textContent = fmt(value);
  const s = document.createElement("span"); s.textContent = `${title} · ${shortDate(day)}`;
  tip.append(b, s);
  tip.hidden = false;
  const x = Math.min(e.clientX + 12, window.innerWidth - tip.offsetWidth - 8);
  tip.style.left = `${x}px`;
  tip.style.top = `${e.clientY - tip.offsetHeight - 10}px`;
  document.querySelectorAll(".bar.on").forEach((n) => n.classList.remove("on"));
  bar.classList.add("on");
}
function hideTip(bar) {
  $("tip").hidden = true;
  bar.classList.remove("on");
}

function renderTable() {
  const table = $("table");
  table.replaceChildren();
  const head = document.createElement("tr");
  for (const label of ["Day (UTC)", ...FIELDS.map(([, l]) => l)]) {
    const th = document.createElement("th"); th.textContent = label; head.append(th);
  }
  const thead = document.createElement("thead"); thead.append(head);
  const tbody = document.createElement("tbody");
  for (const row of [...rows].reverse()) {
    const tr = document.createElement("tr");
    const d = document.createElement("td"); d.textContent = row.day; tr.append(d);
    for (const [key] of FIELDS) {
      const td = document.createElement("td"); td.textContent = fmt(row[key]); tr.append(td);
    }
    tbody.append(tr);
  }
  table.append(thead, tbody);
}

let resizeTimer;
window.addEventListener("resize", () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => { if (rows.length) renderCharts(); }, 150);
});
