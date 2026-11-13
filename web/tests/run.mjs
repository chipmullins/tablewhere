// Web page tests (Playwright, stubbed Firebase + MapKit JS). node web/tests/run.mjs
import { loadPlaywright, serve, openPlan, test, assert, summary } from "./harness.mjs";

const { chromium } = await loadPlaywright();
const browser = await chromium.launch();
const { server, base } = await serve();

const LEX = { lat: 38.0406, lon: -84.5037 };
const near = (dLat, dLon) => ({ lat: LEX.lat + dLat, lon: LEX.lon + dLon });
const HOUR = 3600 * 1000;

/** A plan in the fake Firestore plus MapKit results, set before the page loads. */
function setupScript({ session = {}, members = {}, places = {}, delay = {}, extra = {} } = {}) {
  const now = Date.now();
  const s = {
    title: "Friday dinner", joinCode: "K7Q4MZ", createdBy: "host", createdByName: "Chip",
    createdAt: { __ts: now }, mode: "spin", status: "open", options: [],
    area: { name: "Lexington", latitude: LEX.lat, longitude: LEX.lon },
    ...session,
  };
  const seed = { "sessions/s1": s, "sessions/s1/members/host": { id: "host", name: "Chip" } };
  for (const [id, m] of Object.entries(members)) seed[`sessions/s1/members/${id}`] = m;
  Object.assign(seed, extra);
  return `window.__seed = ${JSON.stringify(seed)};
    window.__mk = { places: ${JSON.stringify(places)}, delay: ${JSON.stringify(delay)}, calls: [] };`;
}

const P = (name, at, extra = {}) => ({ name, lat: at.lat, lon: at.lon, pointOfInterestCategory: "Restaurant", ...extra });
const basePlaces = {
  restaurant: [P("Sora Ramen", near(0.002, 0.001)), P("McDonald's", near(0.004, 0)), P("Kroger Deli", near(0.001, 0))],
  __poi: [P("Sora Ramen", near(0.002, 0.001)), P("Starbucks", near(0.003, 0.002), { pointOfInterestCategory: "Cafe" })],
  burgers: [P("Five Guys", near(0.006, 0.001))],
  pizza: [P("Goodfellas Pizzeria", near(0.008, 0.002))],
  // Same McDonald's, a few meters off: one place, typed "Fast food".
  "fast food": [P("McDonald's", near(0.0042, 0)), P("Far Away Burger", near(0.2, 0.2))],
};
const named = { "forkroad.name": "Sam" };

// ---------------------------------------------------------------------------
// #2 Web map / Nearby

await test("Nearby searches start in the background, before Add your pick", async () => {
  const { page, context, errors } = await openPlan(browser, base, { setup: setupScript({ places: basePlaces }), storage: named });
  await page.waitForSelector("#vote-step:not([hidden])");
  await page.waitForFunction(() => window.__mk.calls.length >= 5, null, { timeout: 4000 });
  const calls = await page.evaluate(() => window.__mk.calls.slice().sort());
  assert(JSON.stringify(calls) === JSON.stringify(["__poi", "burgers", "fast food", "pizza", "restaurant"]), `calls: ${calls}`);
  assert(await page.isHidden("#suggest-panel"), "panel stays closed");
  assert(!errors.length, errors.join("; "));
  await context.close();
});

await test("Panel opens with the list ready, merged and nearest first", async () => {
  const { page, context, errors } = await openPlan(browser, base, { setup: setupScript({ places: basePlaces }), storage: named });
  await page.waitForFunction(() => window.__mk.calls.length >= 5);
  await page.waitForTimeout(50);
  await page.click("#suggest-open");
  const names = await page.$$eval("#suggest-results .result:not(.skeleton) .name", (els) => els.map((e) => e.textContent));
  assert(names.join("|") === "Sora Ramen|Starbucks|McDonald's|Five Guys|Goodfellas Pizzeria", `rows: ${names.join("|")}`);
  const sub = await page.$eval("#suggest-results .result[data-id^=\"mcdonald\"] .sub", (e) => e.textContent);
  assert(sub.startsWith("Fast food"), `McDonald's typed from the fast food search: ${sub}`);
  const pizza = await page.$eval("#suggest-results .result[data-id^=\"goodfellas\"] .sub", (e) => e.textContent);
  assert(pizza.startsWith("Pizza"), `pizza label: ${pizza}`);
  assert(!names.includes("Kroger Deli"), "stores dropped");
  assert(!names.includes("Far Away Burger"), "outside the 2-mile circle dropped");
  await page.waitForFunction(() => window.__mk.map && window.__mk.annotations.length === 5);
  assert(await page.evaluate(() => window.__mk.fits) === 1, "map fit once");
  assert(!errors.length, errors.join("; "));
  await context.close();
});

await test("Skeleton rows while loading, then rows as batches land; pins added once", async () => {
  const delay = { restaurant: 150, __poi: 400, burgers: 700, pizza: 700, "fast food": 700 };
  const { page, context, errors } = await openPlan(browser, base, { setup: setupScript({ places: basePlaces, delay }), storage: named });
  await page.waitForSelector("#suggest-open:not([hidden])");
  await page.click("#suggest-open");
  assert(await page.locator("#suggest-results .skeleton").count() >= 3, "skeleton while searching");
  await page.waitForFunction(() => document.querySelectorAll("#suggest-results .result:not(.skeleton)").length === 2, null, { timeout: 2000 });
  assert(await page.locator("#suggest-results .skeleton").count() > 0, "still loading: skeletons at the bottom");
  await page.waitForFunction(() => document.querySelectorAll("#suggest-results .result:not(.skeleton)").length === 5, null, { timeout: 3000 });
  assert(await page.locator("#suggest-results .skeleton").count() === 0, "skeletons gone when done");
  await page.waitForTimeout(50);
  const { removed, fits } = await page.evaluate(() => ({ removed: window.__mk.removed || 0, fits: window.__mk.fits }));
  assert(removed === 0, `pins kept as batches arrive (removed ${removed})`);
  assert(fits === 1, `fit once (${fits})`);
  assert(!errors.length, errors.join("; "));
  await context.close();
});

await test("Cached for the area: reload doesn't search again", async () => {
  const { page, context } = await openPlan(browser, base, { setup: setupScript({ places: basePlaces }), storage: named });
  await page.waitForFunction(() => window.__mk.calls.length >= 5);
  await page.waitForTimeout(100);
  await page.reload();
  await page.waitForSelector("#suggest-open:not([hidden])");
  await page.click("#suggest-open");
  await page.waitForSelector("#suggest-results .result:not(.skeleton)");
  await page.waitForTimeout(100);
  const calls = await page.evaluate(() => window.__mk.calls.length);
  assert(calls === 0, `no searches after reload (${calls})`);
  assert(await page.locator("#suggest-results .result").count() === 5, "same list from the cache");
  await context.close();
});

await test("Adding from the list works; Change my pick reopens instantly", async () => {
  const { page, context, errors } = await openPlan(browser, base, { setup: setupScript({ places: basePlaces }), storage: named });
  await page.waitForFunction(() => window.__mk.calls.length >= 5);
  await page.click("#suggest-open");
  await page.click("#suggest-results .result[data-id^=\"sora\"]");
  await page.waitForSelector("#pick-confirm:not([hidden])");
  const opt = await page.evaluate(() => window.__fake.get("sessions/s1").options[0]);
  assert(opt.name === "Sora Ramen" && opt.addedBy === "Sam" && opt.id.startsWith("sora ramen|"), JSON.stringify(opt));
  const before = await page.evaluate(() => window.__mk.calls.length);
  await page.click("#pick-change");
  await page.waitForSelector("#suggest-results .result:not(.skeleton)");
  assert(await page.evaluate(() => window.__mk.calls.length) === before, "no new searches");
  const names = await page.$$eval("#suggest-results .result .name", (els) => els.map((e) => e.textContent));
  assert(!names.includes("Sora Ramen"), "the place in the wheel isn't offered again");
  assert(!errors.length, errors.join("; "));
  await context.close();
});

await test("Name search still works and clearing it brings Nearby back", async () => {
  const places = { ...basePlaces, tacos: [P("Kroger Deli", near(0.001, 0)), P("Taco Tico", near(0.01, 0))] };
  const { page, context, errors } = await openPlan(browser, base, { setup: setupScript({ places }), storage: named });
  await page.waitForFunction(() => window.__mk.calls.length >= 5);
  await page.click("#suggest-open");
  await page.fill("#suggest-input", "tacos");
  await page.press("#suggest-input", "Enter");
  await page.waitForFunction(() => document.querySelector("#suggest-list-label").textContent === "Results");
  const names = await page.$$eval("#suggest-results .result .name", (els) => els.map((e) => e.textContent));
  assert(names.join("|") === "Kroger Deli|Taco Tico", `a name search finds stores too: ${names}`);
  const sub = await page.$eval("#suggest-results .result[data-id^=\"taco tico\"] .sub", (e) => e.textContent);
  assert(sub.startsWith("Mexican"), `labeled from the name: ${sub}`);
  await page.fill("#suggest-input", "");
  await page.press("#suggest-input", "Enter");
  await page.waitForFunction(() => document.querySelector("#suggest-list-label").textContent === "Nearby");
  if (process.env.SHOTS) await page.screenshot({ path: "/tmp/shot-nearby.png", fullPage: true });
  assert(!errors.length, errors.join("; "));
  await context.close();
});

await test("No prefetch for Surprise us or decided plans", async () => {
  const { page, context } = await openPlan(browser, base, { setup: setupScript({ places: basePlaces, session: { surprise: true, options: [{ id: "a|1.0|1.0", name: "A", category: "Restaurant", latitude: 1, longitude: 1, addedBy: "Chip" }] } }), storage: named });
  await page.waitForSelector("#vote-step:not([hidden])");
  await page.waitForTimeout(400);
  assert(await page.evaluate(() => (window.__mk?.calls || []).length) === 0, "no searches");
  await context.close();
});

export { browser, base, setupScript, basePlaces, named, P, near, LEX, HOUR };
if (!process.env.MORE_TESTS) {
  const failed = summary();
  await browser.close();
  server.close();
  process.exit(failed ? 1 : 0);
}
