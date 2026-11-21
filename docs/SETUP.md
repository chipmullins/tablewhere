# Setup

Everything needed to build and run Tablewhere yourself. For what the project is, see the [README](../README.md).

## Run it

You need a Mac with a current version of Xcode.

1. Install [Homebrew](https://brew.sh), then XcodeGen:
   ```sh
   brew install xcodegen
   ```
2. Generate and open the project:
   ```sh
   cd tablewhere
   xcodegen generate
   open ForkRoad.xcodeproj
   ```
3. Set signing for **all three** targets (ForkRoad, ForkRoadMessages, ForkRoadWidgets): **Signing & Capabilities** → Team.
4. Pick an iPhone simulator or your phone and press **Run**.

The project file, Info.plists, and entitlements are generated from `project.yml`, so edit that instead of changing them in Xcode. Run `xcodegen generate` again after pulling changes.

**Simulator tip:** set a location with **Features → Location**, or the app uses Lexington, KY.

### Apple Developer Program

iCloud sync, the shared sign-in between the app and the iMessage extension, and TestFlight need a paid Apple Developer Program membership on your team. On a free account, the app still runs, but lists stay on the device. If signing complains about iCloud or Keychain Sharing, check that your paid team is selected for both targets.

## Firebase setup (for group voting)

Everything except group picks works without this, and the project builds without it (you'll see a warning). It takes about 10 minutes and is free on Firebase's Spark plan.

1. Go to [console.firebase.google.com](https://console.firebase.google.com) → **Create a project** (e.g. `forkroad-app`). Analytics is optional. The free **Spark plan** is all you need here.
2. **Turn on anonymous sign-in:** left sidebar → **Authentication** (also under **Security**) → **Get started** if shown → **Sign-in method** tab → **Anonymous** → **Enable** → **Save**.
3. **Create the database:** left sidebar → **Databases & Storage → Firestore Database** → **Create database**. Pick the **Standard** edition if asked, a US location (can't be changed later), and **production mode**. Tablewhere's rules replace the defaults when you deploy in step 6.
4. **Add the iPhone app:** **Project Overview → + Add app → Apple (iOS)**. Bundle ID: `com.chipmullins.forkroad`. Download **GoogleService-Info.plist** and put it in `Config/` (it's ignored by Git). Skip the "Add Firebase SDK" and "initialization code" steps; the app already does both.
5. **Add the web app** (for the voting page): **Project Overview → + Add app → Web (`</>`)**. Copy the `firebaseConfig` it shows into `web/public/firebase-config.js` (start from `firebase-config.example.js`). You don't need Firebase Hosting setup from that screen; step 6 handles it.
6. Deploy the web page and security rules:
   ```sh
   npm install -g firebase-tools
   cd web
   firebase login
   firebase use --add          # pick your project
   firebase deploy --only hosting,firestore
   ```
7. In `Shared/Support/AppConfig.swift`, set `webHost` to `<your-project-id>.web.app`.
8. Run `xcodegen generate` again and rebuild.

### Adding places from the web vote page (optional)

Friends without the app can suggest places on the vote page, using Apple Maps search (MapKit JS). It needs a token, made on your Mac from your MapKit JS key:

1. Apple Developer → **Certificates, Identifiers & Profiles** → **Keys** → your MapKit JS key (Key ID `6GP6SL584A`). Keep its `.p8` file on your Mac; never commit or share it.
2. Run `node web/tools/make-mapkit-token.mjs /path/to/AuthKey_6GP6SL584A.p8`. It writes `web/public/mapkit-token.js`, which only works on forkroad-app.web.app and lasts a year.
3. `cd web && firebase deploy --only hosting`.

The token is safe to commit (it's origin-restricted, and MapKit JS tokens are meant to sit in web pages). Without it, the page still works for voting; the Suggest button just doesn't appear.

### Usage stats (private)

Tablewhere counts anonymous daily totals in `stats/{yyyy-mm-dd}` (UTC): active and new devices, spins (and eat-in spins), groups started, places added, RSVPs, On my way and Running late taps, tour finished or skipped, and web visitors, votes and picks. Cloud Functions add three counts only the server sees: Lock Screen countdowns started, plans that got a meet time, and plans where everyone arrived. Nothing about who, where, or which places. Users can turn the app's counts off in Settings.

New count names have to be added in three places: `UsageStat` in `Shared/Group/UsageStats.swift` (or `web/functions/src/stats.ts` for server counts), `statFields()` in `web/firestore.rules` (app and web counts only), and `FIELDS` in `web/public/stats.js`.

See them at **https://forkroad-app.web.app/stats**. One-time setup:

1. Firebase console → **Authentication → Sign-in method → Add new provider → Google** → Enable → Save.
2. Open the stats page and sign in with Google. It shows your user ID.
3. Firebase console → **Firestore** → start a collection **`admins`** → add a document whose **ID is that user ID** (any field, e.g. `name` = `Chip`). Reload the page.

Downloads, retention, and crashes come from App Store Connect → Analytics.

### Push notifications and Lock Screen countdowns (optional)

"Maya voted" and "It's decided" alerts, the Lock Screen countdowns, and the server-side stats come from Cloud Functions in `web/functions/`.

1. Upgrade the Firebase project to the **Blaze (pay-as-you-go) plan**. Cloud Functions require it, but the free monthly allowance covers light use, so this usually costs nothing. Set a budget alert in Google Cloud if you want peace of mind.
2. In the Apple Developer site, create an **APNs Auth Key** (.p8). In Firebase console → **Project settings → Cloud Messaging → Apple app configuration**, upload it with its Key ID and your Team ID.
3. Lock Screen countdowns are sent to APNs directly, so the functions need the same key as secrets (run in `web/`):
   ```sh
   firebase functions:secrets:set APNS_KEY_P8 < /path/to/AuthKey_XXXXXXXXXX.p8
   firebase functions:secrets:set APNS_KEY_ID      # the 10-character Key ID
   ```
4. Deploy (from `web/`):
   ```sh
   firebase deploy --only functions,firestore,hosting
   ```
   If the predeploy step fails with `Cannot read properties of undefined (reading 'stdin')`, the standalone Firebase CLI's bundled npm is the problem. Install the CLI with `npm install -g firebase-tools` instead.
5. Check delivery with `firebase functions:log`. If a countdown never appears, look for `liveActivityTick` and `Live Activity start` lines first.

Without this step, group picks still work. People just don't get alerts or countdowns.

### How group picks work

- Sessions live in Firestore (`sessions/{id}`, with `votes` and `members` subcollections). Everyone signs in anonymously, so there are no accounts.
- `web/firestore.rules` lets anyone with the link see a session, but nobody can list sessions. Join codes are looked up one at a time through `joinCodes/{code}`. Only you can write your own vote, and only until the timer runs out. Only the creator can lock in the result or set the meeting time. Other people get **one pick each** while it's open (recorded in `picksBy`): in a Spin everyone, creator included, adds one place; in a Vote the creator can add up to 12 and everyone else can suggest one. After changing the rules, deploy them with `firebase deploy --only firestore`.
- Ties and spins are decided by a fair, repeatable pick seeded by the session ID, so every device agrees.

## Run the tests

```sh
(cd Packages/PickerCore && swift test)   # app logic
node web/tests/run.mjs                   # web page, in a headless browser (needs Playwright)
node web/tools/test-food-filters.mjs     # Swift and web filter lists match
```

The fast-food, coffee-and-sweets and not-a-restaurant lists live in Swift (`Packages/PickerCore`). After editing them, run `node web/tools/make-food-filters.mjs` to regenerate the web page's copy.

## Known limits

- **MapKit has no cuisine data.** Cuisine chips search for phrases like "Mexican restaurant." Once a place has been labeled by a cuisine search, the app remembers that label (`Shared/Search/LabelMemory.swift`).
- **MapKit has no hours, photos, or menus.** The restaurant screen links to the restaurant's website, and Look Around stands in for photos.
- **"No fast food" matches a list of chain names** (`PickerCore/FastFood.swift`). Add names to it as you find gaps, with a test in `FastFoodTests.swift`.
- **iMessage voting needs Tablewhere installed.** Friends without it use the web link, which is sent along with the vote.

