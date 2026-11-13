// Shared setup for the web page tests: serves web/public, swaps Firebase and
// MapKit JS for stubs (web/tests/stubs), and opens /v/<id> with a seeded plan.
//
//   cd web/tests && npm i --no-save playwright && node run.mjs
// (or set PLAYWRIGHT_PATH to an existing playwright module.)
import http from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { dirname, join, extname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pub = join(here, "..", "public");
const stub = (f) => readFileSync(join(here, "stubs", f), "utf8");

export async function loadPlaywright() {
  const tries = [process.env.PLAYWRIGHT_PATH, "playwright", "/opt/npm-tools/node_modules/playwright/index.js"].filter(Boolean);
  for (const t of tries) { try { const m = await import(t); return m.chromium ? m : m.default; } catch { /* next */ } }
  throw new Error("Playwright not found");
}

export function serve() {
  const types = { ".html": "text/html", ".js": "text/javascript", ".png": "image/png", ".json": "application/json" };
  const server = http.createServer((req, res) => {
    let path = decodeURIComponent(new URL(req.url, "http://x").pathname);
    if (path.startsWith("/v/")) path = "/index.html";
    if (path === "/firebase-config.js") {
      res.writeHead(200, { "content-type": "text/javascript" });
      return res.end('export const firebaseConfig = { projectId: "test" };');
    }
    const file = join(pub, path);
    if (!file.startsWith(pub) || !existsSync(file)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "content-type": types[extname(file)] || "application/octet-stream" });
    res.end(readFileSync(file));
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve({ server, base: `http://127.0.0.1:${server.address().port}` })));
}

/** A new page with the stubs routed in. `before` runs in the page before app.js (seed data there). */
export async function openPlan(browser, base, { id = "s1", setup = "", storage = {}, context: existing } = {}) {
  const context = existing || await browser.newContext({ viewport: { width: 420, height: 900 } });
  await context.route(/gstatic\.com\/firebasejs/, (r) => r.fulfill({ contentType: "text/javascript", body: stub("firebase.js") }));
  await context.route(/apple-mapkit\.com/, (r) => r.fulfill({ contentType: "text/javascript", body: stub("mapkit.js") }));
  await context.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.fulfill({ body: "" }));
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.addInitScript(({ storage }) => {
    for (const [k, v] of Object.entries(storage)) localStorage.setItem(k, v);
  }, { storage });
  if (setup) await page.addInitScript(setup);
  await page.goto(`${base}/v/${id}`);
  return { page, context, errors };
}

// Seeds the fake Firestore once the stub module has loaded (it defines __fake).
export const seedScript = (fn) => `
  (function wait() {
    if (!window.__fake) return setTimeout(wait, 0);
    (${fn.toString()})(window.__fake);
  })();`;

let failures = 0, passed = 0;
export async function test(name, fn) {
  try { await fn(); passed++; console.log("✓", name); }
  catch (e) { failures++; console.error("✗", name, "\n  ", e.message.split("\n").slice(0, 4).join("\n   ")); }
}
export function assert(ok, msg) { if (!ok) throw new Error(msg); }
export function summary() {
  console.log(failures ? `\n${failures} failed, ${passed} passed` : `\nAll ${passed} tests pass`);
  return failures;
}
