// ForkRoad web vote page: https://<host>/v/<sessionId>
// Same Firestore data as the app and iMessage extension.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth, signInAnonymously, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import {
  getFirestore, doc, collection, onSnapshot, setDoc, deleteDoc, serverTimestamp, runTransaction
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

function isSpin() { return session.mode === "spin"; }

function statusText() {
  if (isSpin()) {
    const n = (session.options || []).length;
    return `${members.length} in the group · ${n} place${n === 1 ? "" : "s"} in the wheel`;
  }
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
  if (isSpin()) return renderSpin();
  const t = tally();
  const mine = votes.find((v) => v.voterID === uid)?.optionID;
  const slots = Math.max(members.length, t.total, 1);

  $("title").textContent = session.title;
  $("status").textContent = statusText();
  $("vote-help").textContent = "Tap a place to vote. Tap it again to take your vote back. Ties are broken fairly by the app.";

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
  updateSuggest();
  show("vote-step");
}

// Group spin: everyone adds their pick, then whoever started it spins the
// wheel in the app and one is picked at random. Nothing to vote on here.
function renderSpin() {
  $("title").textContent = session.title;
  $("status").textContent = statusText();
  const me = (myName() || "").trim().toLowerCase();
  const creator = session.createdByName || "Whoever started it";
  const options = session.options || [];
  const havePick = options.some((o) => (o.addedBy || "").trim().toLowerCase() === me);
  $("vote-help").textContent = havePick
    ? `You’re in the wheel. ${creator} spins when everyone’s ready, and the app picks one at random.`
    : mapkitToken
      ? `Add your pick to the wheel. ${creator} spins when everyone’s ready, and the app picks one at random.`
      : `${creator} spins when everyone’s ready, and the app picks one at random. To add a pick, join in the ForkRoad app with the code below.`;

  const list = $("options");
  list.replaceChildren();
  if (!options.length) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "The wheel is empty. Add the first pick!";
    list.append(empty);
  }
  for (const option of options) {
    const mine = (option.addedBy || "").trim().toLowerCase() === me;
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
    if (mine) {
      const pill = document.createElement("span");
      pill.className = "pill soft";
      pill.textContent = "YOUR PICK";
      nameEl.append(pill);
    }
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = `${option.category} · added by ${option.addedBy}`;
    text.append(nameEl, sub);
    row.append(tile, text);
    card.append(row);
    list.append(card);
  }
  list.setAttribute("role", "list");
  updateSuggest(havePick);
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
  const how = isSpin() ? `Picked by the spin · ${winner.addedBy ? winner.addedBy + "’s pick" : winner.category}` : winner.category;
  $("winner-detail").textContent = time ? `Meet at ${time} · ${how}` : how;

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

  // The creator's note ("Bring a gift!"), if there is one.
  const note = typeof session.note === "string" ? session.note.trim() : "";
  $("note").hidden = !note;
  $("note-text").textContent = note;
  $("note-by").textContent = note ? `— ${session.createdByName || "the organizer"}` : "";

  renderBreakdown(winner.id);
  show("decided-step");
}

// After the vote closes: every place, who voted for it, and who didn't vote.
function renderBreakdown(winnerId) {
  const wrap = $("breakdown-wrap");
  if (session.mode === "spin") { wrap.hidden = true; return; }
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
let suggestWired = false;
let searchTimer = null;
let searchSeq = 0;
let adding = false;

function updateSuggest(havePick = false) {
  const open = session.status === "open";
  const full = (session.options || []).length >= MAX_OPTIONS;
  $("suggest").hidden = !mapkitToken || !open;
  // In a spin, adding your pick is the main thing to do, so make it the big button.
  const primary = isSpin() && !havePick && !full;
  $("suggest-open").className = primary ? "btn primary wide" : "btn ghost wide";
  $("suggest-open").textContent = full
    ? "The wheel is full (12 places)"
    : isSpin() ? (havePick ? "+ Add another pick" : "+ Add your pick") : "+ Suggest a place";
  if (!isSpin() && full) $("suggest-open").textContent = "This vote is full (12 places)";
  $("suggest-open").disabled = full;
  $("suggest-open").style.width = "100%";
  if (full) $("suggest-panel").hidden = true;
  if (!suggestWired && mapkitToken) wireSuggest();
}

function wireSuggest() {
  suggestWired = true;
  $("suggest-open").addEventListener("click", async () => {
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
    script.dataset.libraries = "services";
    script.onerror = () => { mapkitReady = null; reject(new Error("MapKit JS failed to load")); };
    document.head.append(script);
  });
  return mapkitReady;
}

// The middle of the places already in the vote: that's where the group is eating.
function groupCenter() {
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

  // About 15 miles each way, like a name search in the app.
  const region = new mk.CoordinateRegion(
    new mk.Coordinate(center.lat, center.lon),
    new mk.CoordinateSpan(0.44, 0.44 / Math.max(0.2, Math.cos(center.lat * Math.PI / 180)))
  );
  const options = { region, includeAddresses: false, includeQueries: false, includePointsOfInterest: true };
  try {
    const C = mk.PointOfInterestCategory;
    options.pointOfInterestFilter = mk.PointOfInterestFilter.including(
      [C.Restaurant, C.Cafe, C.Bakery, C.Brewery, C.Winery, C.FoodMarket].filter(Boolean));
  } catch { /* older MapKit JS: search everything */ }

  new mk.Search(options).search(query, (error, data) => {
    if (seq !== searchSeq) return;  // a newer search took over
    if (error) { setStatus("Couldn’t search right now. Try again in a moment.", true); return; }
    const places = (data?.places || [])
      .filter((p) => p.coordinate && p.name)
      .map((p) => ({ p, miles: milesBetween(center, { lat: p.coordinate.latitude, lon: p.coordinate.longitude }) }))
      .sort((a, b) => a.miles - b.miles)
      .slice(0, 15);
    renderResults(places, query);
  }, { region });
}

function renderResults(places, query) {
  const list = $("suggest-results");
  list.replaceChildren();
  if (!places.length) {
    setStatus(`No restaurants found for “${query}”. Try a broader word like “pizza.”`);
    return;
  }
  setStatus("");
  for (const { p, miles } of places) {
    const option = toOption(p);
    const taken = isTaken(option);
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
    add.textContent = taken ? (isSpin() ? "In the wheel" : "In the vote") : "Add";
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
  setStatus(`Adding ${option.name}…`);
  [...$("suggest-results").children].forEach((b) => { b.disabled = true; });
  try {
    await runTransaction(db, async (tx) => {
      const snap = await tx.get(sessionRef);
      if (!snap.exists()) throw new Error("ended");
      const data = snap.data();
      const options = data.options || [];
      if (data.status !== "open") throw new Error("closed");
      if (options.some((o) => sameOption(o, option))) throw new Error("duplicate");
      if (options.length >= MAX_OPTIONS) throw new Error("full");
      tx.update(sessionRef, { options: [...options, option] });
    });
    closeSuggest();
  } catch (error) {
    const messages = {
      duplicate: isSpin() ? "That place is already in the wheel." : "That place is already in the vote.",
      full: "This pick already has 12 places, the most it can hold.",
      closed: "Voting has closed, so places can’t be added.",
      ended: "This group pick has ended.",
    };
    setStatus(messages[error?.message] || "Couldn’t add it. Check your connection and try again.", true);
    // Let them pick something else (places already in the vote stay disabled).
    [...$("suggest-results").children].forEach((b) => { b.disabled = b.dataset.taken === "1"; });
  } finally {
    adding = false;
  }
}
