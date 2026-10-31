#!/usr/bin/env node
// Makes the MapKit JS token the web vote page uses for "Suggest a place".
//
//   node web/tools/make-mapkit-token.mjs ~/Keys/AuthKey_6GP6SL584A.p8
//
// Run it on your Mac. The .p8 private key never leaves your computer: this
// script signs a token with it and writes web/public/mapkit-token.js.
// The token only works on the vote page's website (the "origin" below), so
// it's safe to publish; Apple designed MapKit JS tokens to sit in web pages.
// Tokens last a year; run this again before it expires.
import { readFileSync, writeFileSync } from "node:fs";
import { createPrivateKey, sign } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const KEY_ID = "6GP6SL584A";
const TEAM_ID = "4XK3F69URN";
const ORIGIN = "https://forkroad-app.web.app";
const DAYS = 365;

const keyPath = process.argv[2];
if (!keyPath) {
  console.error("Usage: node web/tools/make-mapkit-token.mjs /path/to/AuthKey_" + KEY_ID + ".p8");
  process.exit(1);
}

const b64url = (data) => Buffer.from(data).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
const payload = { iss: TEAM_ID, iat: now, exp: now + DAYS * 24 * 60 * 60, origin: ORIGIN };

const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
const key = createPrivateKey(readFileSync(keyPath));
// JWT wants the raw r||s signature, not DER.
const signature = sign("sha256", Buffer.from(unsigned), { key, dsaEncoding: "ieee-p1363" });
const token = `${unsigned}.${b64url(signature)}`;

const expires = new Date((now + DAYS * 86400) * 1000).toISOString().slice(0, 10);
const out = join(dirname(fileURLToPath(import.meta.url)), "..", "public", "mapkit-token.js");
writeFileSync(out,
  `// MapKit JS token for "Suggest a place" on the vote page. Made by\n` +
  `// web/tools/make-mapkit-token.mjs. Only works on ${ORIGIN}. Expires ${expires}.\n` +
  `export const mapkitToken = "${token}";\n`);

console.log(`Wrote ${out}`);
console.log(`Token works on ${ORIGIN} until ${expires}.`);
console.log(`Next: cd web && firebase deploy --only hosting`);
