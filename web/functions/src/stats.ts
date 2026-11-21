/**
 * Server-side counts for the stats page: the same anonymous daily totals the
 * apps write (stats/{yyyy-mm-dd}, UTC), for things only the server sees.
 * Counted here, they include every app version, with no app update needed.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

export type ServerStat = "countdownsStarted" | "everyoneHere" | "plansWithTime";

export async function bumpStat(field: ServerStat): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  try {
    await getFirestore().collection("stats").doc(day).set({ [field]: FieldValue.increment(1) }, { merge: true });
  } catch (err) {
    logger.warn("bumpStat failed", { field, err: String(err) });
  }
}
