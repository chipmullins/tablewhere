// Test stub for the Firebase JS SDK modules app.js imports from gstatic
// (app, auth, firestore all point here). An in-memory Firestore the test
// drives through window.__fake: seed(path, data), get(path), set(path, data).
const docs = new Map();          // path → data
const listeners = new Set();     // { path, collection, cb }
const writes = [];               // every write, for assertions

const clone = (v) => JSON.parse(JSON.stringify(v, (k, x) => (x && x.__ts ? { __ts: x.__ts } : x)));
function revive(v) {
  if (Array.isArray(v)) return v.map(revive);
  if (v && typeof v === "object") {
    if (v.__ts) { const d = new Date(v.__ts); return { toDate: () => d, toMillis: () => d.getTime() }; }
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = revive(x);
    return out;
  }
  return v;
}
const parentOf = (path) => path.split("/").slice(0, -1).join("/");

function notify() {
  for (const l of listeners) fire(l);
}
function fire(l) {
  if (l.collection) {
    const list = [...docs.entries()].filter(([p]) => parentOf(p) === l.path)
      .map(([p, d]) => ({ id: p.split("/").pop(), data: () => revive(clone(d)) }));
    l.cb({ docs: list });
  } else {
    const d = docs.get(l.path);
    l.cb({ exists: () => d !== undefined, data: () => (d === undefined ? undefined : revive(clone(d))), id: l.path.split("/").pop() });
  }
}

function setPath(obj, dotted, value) {
  const keys = dotted.split(".");
  let o = obj;
  for (const k of keys.slice(0, -1)) o = (o[k] = o[k] && typeof o[k] === "object" ? o[k] : {});
  o[keys.at(-1)] = value;
}
function resolveValue(old, v) {
  if (v && v.__op === "serverTimestamp") return { __ts: Date.now() };
  if (v && v.__op === "increment") return (typeof old === "number" ? old : 0) + v.by;
  if (v && v.__op === "delete") return undefined;
  return v;
}
function write(path, data, merge) {
  if (window.__fake.denyWrites?.(path, data)) throw Object.assign(new Error("permission-denied"), { code: "permission-denied" });
  const base = merge ? clone(docs.get(path) || {}) : {};
  for (const [k, v] of Object.entries(data)) {
    const old = k.split(".").reduce((o, x) => (o ? o[x] : undefined), base);
    const val = resolveValue(old, v);
    if (val === undefined) { delete base[k]; continue; }
    if (k.includes(".")) setPath(base, k, val); else base[k] = val;
  }
  docs.set(path, base);
  writes.push({ path, data: clone(base) });
}

window.__fake = {
  docs, writes,
  seed(path, data) { docs.set(path, clone(data)); notify(); },
  set(path, data) { docs.set(path, clone(data)); notify(); },
  get(path) { return docs.has(path) ? clone(docs.get(path)) : undefined; },
  remove(path) { docs.delete(path); notify(); },
  ts(ms) { return { __ts: ms }; },
  uid: "web-user",
  denyWrites: null,
};
// Data the test put in place before the page loaded.
for (const [path, data] of Object.entries(window.__seed || {})) docs.set(path, clone(data));

// --- firebase-app
export function initializeApp(config) { return { config }; }
// --- firebase-auth
export function getAuth() { return {}; }
export function signInAnonymously() { return Promise.resolve({ user: { uid: window.__fake.uid } }); }
export function onAuthStateChanged(auth, cb) { setTimeout(() => cb({ uid: window.__fake.uid }), 0); return () => {}; }
// --- firebase-firestore
export function getFirestore() { return {}; }
export function doc(base, ...parts) {
  const prefix = base && base.path ? base.path : "";
  return { path: [prefix, ...parts].filter(Boolean).join("/"), id: parts.at(-1) };
}
export function collection(base, ...parts) {
  const prefix = base && base.path ? base.path : "";
  return { path: [prefix, ...parts].filter(Boolean).join("/"), collection: true };
}
export function onSnapshot(ref, cb, onError) {
  const l = { path: ref.path, collection: !!ref.collection, cb };
  listeners.add(l);
  setTimeout(() => fire(l), 0);
  return () => listeners.delete(l);
}
export async function setDoc(ref, data, opts) { write(ref.path, data, !!opts?.merge); notify(); }
export async function updateDoc(ref, data) { write(ref.path, data, true); notify(); }
export async function deleteDoc(ref) { docs.delete(ref.path); writes.push({ path: ref.path, deleted: true }); notify(); }
export async function getDoc(ref) {
  const d = docs.get(ref.path);
  return { exists: () => d !== undefined, data: () => revive(clone(d)) };
}
export function serverTimestamp() { return { __op: "serverTimestamp" }; }
export function increment(by) { return { __op: "increment", by }; }
export function deleteField() { return { __op: "delete" }; }
export function arrayUnion(...items) { return items; }
export class Timestamp {
  static fromDate(d) { return { __ts: d.getTime() }; }
  static fromMillis(ms) { return { __ts: ms }; }
}
export async function runTransaction(db, fn) {
  const pending = [];
  const tx = {
    async get(ref) { const d = docs.get(ref.path); return { exists: () => d !== undefined, data: () => revive(clone(d)) }; },
    update(ref, data) { pending.push([ref.path, data, true]); },
    set(ref, data, opts) { pending.push([ref.path, data, !!opts?.merge]); },
  };
  const result = await fn(tx);
  for (const [p, d, m] of pending) write(p, d, m);
  notify();
  return result;
}
