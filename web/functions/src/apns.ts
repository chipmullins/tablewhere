/**
 * Sends Live Activity pushes straight to APNs (FCM can't start Live
 * Activities). Token-based auth with the same .p8 key that's in Firebase
 * for regular pushes: one APNs auth key works for every topic of the team,
 * including <bundle id>.push-type.liveactivity.
 *
 * Secrets (set once, see the 1.1 plan doc):
 *   firebase functions:secrets:set APNS_KEY_P8 < AuthKey_XXXXXXXXXX.p8
 *   firebase functions:secrets:set APNS_KEY_ID          (the 10-character Key ID)
 */
import { connect, constants, type ClientHttp2Session } from "node:http2";
import { createSign } from "node:crypto";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";

export const APNS_KEY_P8 = defineSecret("APNS_KEY_P8");
export const APNS_KEY_ID = defineSecret("APNS_KEY_ID");
/** Apple Developer team (DEVELOPMENT_TEAM in project.yml). */
const TEAM_ID = "4XK3F69URN";
/** The app's bundle ID; Live Activity pushes go to <bundle>.push-type.liveactivity. */
const BUNDLE_ID = "com.chipmullins.forkroad";
export const LIVE_ACTIVITY_TOPIC = `${BUNDLE_ID}.push-type.liveactivity`;

export type ApnsEnv = "sandbox" | "production";

export interface ApnsResult {
  ok: boolean;
  status: number;
  reason?: string;
  /** The token will never work again (remove it). */
  dead: boolean;
}

// A JWT is good for an hour; APNs rejects refreshing more than every 20 minutes.
let jwt: { token: string; madeAt: number } | null = null;

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function authToken(): string {
  const now = Date.now();
  if (jwt && now - jwt.madeAt < 40 * 60 * 1000) return jwt.token;
  const header = base64url(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID.value().trim() }));
  const claims = base64url(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(now / 1000) }));
  const signer = createSign("SHA256");
  signer.update(`${header}.${claims}`);
  // JOSE wants the raw r||s signature, not DER.
  const signature = signer.sign({ key: APNS_KEY_P8.value(), dsaEncoding: "ieee-p1363" });
  jwt = { token: `${header}.${claims}.${base64url(signature)}`, madeAt: now };
  return jwt.token;
}

const sessions = new Map<ApnsEnv, ClientHttp2Session>();

function client(env: ApnsEnv): ClientHttp2Session {
  const existing = sessions.get(env);
  if (existing && !existing.closed && !existing.destroyed) return existing;
  const host = env === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const session = connect(host);
  session.on("error", (err) => logger.warn("APNs connection error", { env, err: String(err) }));
  session.on("close", () => sessions.delete(env));
  // Don't keep the function instance alive just for this connection.
  session.unref();
  sessions.set(env, session);
  return session;
}

/** One Live Activity push. Never throws. */
export async function sendLiveActivity(
  token: string,
  env: ApnsEnv,
  payload: Record<string, unknown>,
  opts: { priority?: 5 | 10 } = {},
): Promise<ApnsResult> {
  if (!/^[0-9a-f]{16,400}$/i.test(token)) return { ok: false, status: 0, reason: "BadDeviceToken", dead: true };
  const body = JSON.stringify(payload);
  try {
    return await new Promise<ApnsResult>((resolve) => {
      const req = client(env).request({
        [constants.HTTP2_HEADER_METHOD]: "POST",
        [constants.HTTP2_HEADER_PATH]: `/3/device/${token}`,
        authorization: `bearer ${authToken()}`,
        "apns-topic": LIVE_ACTIVITY_TOPIC,
        "apns-push-type": "liveactivity",
        "apns-priority": String(opts.priority ?? 10),
        "content-type": "application/json",
      });
      let status = 0;
      let data = "";
      const timer = setTimeout(() => { req.close(); resolve({ ok: false, status: 0, reason: "Timeout", dead: false }); }, 10000);
      req.setEncoding("utf8");
      req.on("response", (headers) => { status = Number(headers[constants.HTTP2_HEADER_STATUS]) || 0; });
      req.on("data", (chunk: string) => { data += chunk; });
      req.on("end", () => {
        clearTimeout(timer);
        let reason: string | undefined;
        try { reason = data ? JSON.parse(data).reason : undefined; } catch { /* not JSON */ }
        // Not DeviceTokenNotForTopic: that's a setup problem, not a dead token.
        const dead = status === 410 || reason === "BadDeviceToken" || reason === "Unregistered";
        if (status !== 200) logger.warn("APNs push not accepted", { env, status, reason });
        resolve({ ok: status === 200, status, reason, dead });
      });
      req.on("error", (err) => {
        clearTimeout(timer);
        logger.warn("APNs request failed", { env, err: String(err) });
        resolve({ ok: false, status: 0, reason: "RequestError", dead: false });
      });
      req.end(body);
    });
  } catch (err) {
    logger.error("APNs send threw", { env, err: String(err) });
    return { ok: false, status: 0, reason: "Exception", dead: false };
  }
}

/** Seconds since 2001-01-01, how Swift's default JSONDecoder reads a Date. */
export function swiftDate(ms: number): number {
  return ms / 1000 - 978307200;
}
