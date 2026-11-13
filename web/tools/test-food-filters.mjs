#!/usr/bin/env node
// Checks that web/public/food-filters.js agrees with the app:
// 1. it's up to date with the Swift lists (same as make-food-filters.mjs --check), and
// 2. it gives the same answer as every name in the Swift tests
//    (FastFoodTests, CoffeeAndSweetsTests, NotARestaurantTests), read straight
//    from those files, so a new Swift test is checked here too.
//
//   node web/tools/test-food-filters.mjs
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { generate } from "./make-food-filters.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const file = join(root, "web/public/food-filters.js");
const f = await import(pathToFileURL(file).href);
let failures = 0, checks = 0;
const check = (ok, what) => { checks++; if (!ok) { failures++; console.error("✗", what); } };

check(readFileSync(file, "utf8") === generate(), "food-filters.js is out of date: run node web/tools/make-food-filters.mjs");

const tests = join(root, "Packages/PickerCore/Tests/PickerCoreTests");
const src = (name) => readFileSync(join(tests, name), "utf8");
const lit = (s) => JSON.parse(`"${s}"`);

for (const m of src("FastFoodTests.swift").matchAll(/XCTAssert(True|False)\(FastFood\.isFastFood\("((?:[^"\\]|\\.)*)"\)\)/g)) {
  check(f.isFastFood(lit(m[2])) === (m[1] === "True"), `isFastFood("${m[2]}") should be ${m[1]}`);
}
for (const m of src("FastFoodTests.swift").matchAll(/XCTAssertEqual\(CuisineLabel\.guess\(name: "((?:[^"\\]|\\.)*)"\), "([^"]+)"\)/g)) {
  check(f.guessCuisine(lit(m[1])) === m[2], `guessCuisine("${m[1]}") should be ${m[2]}`);
}
for (const m of src("FastFoodTests.swift").matchAll(/XCTAssertNil\(CuisineLabel\.guess\(name: "((?:[^"\\]|\\.)*)"\)\)/g)) {
  check(f.guessCuisine(lit(m[1])) === null, `guessCuisine("${m[1]}") should be null`);
}
for (const m of src("NotARestaurantTests.swift").matchAll(/XCTAssert(True|False)\(NotARestaurant\.matches\("((?:[^"\\]|\\.)*)"\)\)/g)) {
  check(f.isNotARestaurant(lit(m[2])) === (m[1] === "True"), `isNotARestaurant("${m[2]}") should be ${m[1]}`);
}
// CoffeeAndSweets tests loop over a list of names per test.
const sweets = src("CoffeeAndSweetsTests.swift");
for (const [fn, want] of [["testCoffeeAndSweetsAreCaught", true], ["testRealMealsStay", false]]) {
  const body = sweets.slice(sweets.indexOf(fn));
  const list = body.slice(body.indexOf("["), body.indexOf("]") + 1);
  const names = [...list.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => lit(m[1]));
  check(names.length > 0, `found names in ${fn}`);
  for (const name of names) check(f.isCoffeeOrSweets(name) === want, `isCoffeeOrSweets("${name}") should be ${want}`);
}

if (checks < 30) { failures++; console.error(`✗ only ${checks} checks ran; did the Swift tests move?`); }
console.log(failures ? `${failures} of ${checks} checks failed` : `All ${checks} food-filter checks pass`);
process.exit(failures ? 1 : 0);
