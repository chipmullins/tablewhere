# ForkRoad

**Every dinner is a fork in the road.** ForkRoad helps you decide where to eat: browse what's nearby, spin for a random pick, vote with friends in iMessage or on the web, and plan where to eat on trips.

Built with SwiftUI, SwiftData + CloudKit, MapKit, and Firebase. iOS 17+. Type is Outfit (headings) and DM Sans (body), bundled under the SIL Open Font License (see `Licenses/`).

## Features

- **Onboarding:** a short welcome that explains location before asking (or lets you pick a city instead) and asks your name for group votes
- **Discover:** search restaurants by name or craving, a live map with your search radius (0.5 to 10 mi), multi-select cuisine filters (mix up to 4), dietary filters (vegetarian, vegan, gluten-free), and a "No fast food" toggle
- **Spin:** a slot-machine pick from Nearby, Favorites, or Interested with a landing burst, skipping blacklisted places and repeats from the past week
- **Restaurant screen:** Look Around, call, directions, menu and hours (their website, in the app), Favorite, Try, Blacklist, and your own notes
- **Lists:** Favorites (places you love), Interested (places to try), and Blacklisted (one place or a whole category). Any saved place can be left out of spins while staying on its list. Saved places are grouped into metro areas (cities within about 25 miles join the biggest one), so lists and spins show the area you're in, any other area, or all of them. Syncs with iCloud.
- **"How was it?":** after you get directions somewhere, ForkRoad asks how it went (in the app and with a quiet notification). Loved it → Favorites, Never again → Blacklist.
- **Group picks:** vote or spin together, with a live tally, fair tie-breaks, a meeting time, "send everyone the plan," and push alerts ("Maya voted," "It's decided")
- **iMessage app:** start and vote on a dinner pick right in a group text
- **Web voting:** friends without ForkRoad vote from a link in any browser
- **Trips:** pick a city, browse its restaurants, and save spots for the trip
- **Siri and Shortcuts:** "Pick dinner with ForkRoad" and "Spin ForkRoad"
- **Widget:** "Tonight's Pick" on the Home Screen or Lock Screen, with a Spin again button
- **Settings:** your name, search defaults, appearance (System, Light, Dark), notifications, clear spin history
- **Looks:** dark and light mode, custom cuisine icons, Outfit and DM Sans type

## Run it

You need a Mac with a current version of Xcode.

1. Install [Homebrew](https://brew.sh), then XcodeGen:
   ```sh
   brew install xcodegen
   ```
2. Generate and open the project:
   ```sh
   cd forkroad
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
3. **Create the database:** left sidebar → **Databases & Storage → Firestore Database** → **Create database**. Pick the **Standard** edition if asked, a US location (can't be changed later), and **production mode**. ForkRoad's rules replace the defaults when you deploy in step 6.
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

Friends without ForkRoad can suggest places on the vote page, using Apple Maps search (MapKit JS). It needs a token, made on your Mac from your MapKit JS key:

1. Apple Developer → **Certificates, Identifiers & Profiles** → **Keys** → your MapKit JS key (Key ID `6GP6SL584A`). Keep its `.p8` file on your Mac; never commit or share it.
2. Run `node web/tools/make-mapkit-token.mjs /path/to/AuthKey_6GP6SL584A.p8`. It writes `web/public/mapkit-token.js`, which only works on forkroad-app.web.app and lasts a year.
3. `cd web && firebase deploy --only hosting`.

The token is safe to commit (it's origin-restricted, and MapKit JS tokens are meant to sit in web pages). Without it, the page still works for voting; the Suggest button just doesn't appear.

### Group push notifications (optional)

"Maya voted" and "It's decided" alerts come from Cloud Functions in `web/functions/`.

1. Upgrade the Firebase project to the **Blaze (pay-as-you-go) plan**. Cloud Functions require it, but the free monthly allowance covers light use, so this usually costs nothing. Set a budget alert in Google Cloud if you want peace of mind.
2. In the Apple Developer site, create an **APNs Auth Key** (.p8). In Firebase console → **Project settings → Cloud Messaging → Apple app configuration**, upload it with its Key ID and your Team ID.
3. Deploy:
   ```sh
   cd web/functions && npm install
   cd .. && firebase deploy --only functions
   ```
4. Check delivery with `firebase functions:log`.

Without this step, group picks still work. People just don't get alerts.

### How group picks work

- Sessions live in Firestore (`sessions/{id}`, with `votes` and `members` subcollections). Everyone signs in anonymously, so there are no accounts.
- `web/firestore.rules` lets anyone with the link see a session, but nobody can list sessions. Join codes are looked up one at a time through `joinCodes/{code}`. Only you can write your own vote, and only until the timer runs out. Only the creator can lock in the result or set the meeting time. Other people get **one pick each** while it's open (recorded in `picksBy`): in a Spin everyone, creator included, adds one place; in a Vote the creator can add up to 12 and everyone else can suggest one. After changing the rules, deploy them with `firebase deploy --only firestore`.
- Ties and spins are decided by a fair, repeatable pick seeded by the session ID, so every device agrees.

## Run the tests

```sh
cd Packages/PickerCore
swift test
```

## Project layout

```
project.yml                 XcodeGen project definition (targets, entitlements, Info.plists)
ForkRoad/                   The iPhone app
  App/                      Entry point and shared AppModel
  Features/                 Discover, Spin, Detail, Lists, Group, Trips
  Models/                   SwiftData models (CloudKit-ready), list actions
  Services/                 Location, MapKit search, Maps/phone links
  UI/                       In-app browser
MessagesExtension/          The iMessage app
Shared/                     Code and fonts compiled into both the app and the iMessage app
  Group/                    Firebase setup, GroupService, LiveSession
  Support/                  App config, shared preferences and caches
  UI/                       Theme and shared components
Packages/PickerCore/        Pure logic + tests: Place, randomizer, fast food, tally, join codes
ForkRoadWidgets/            Home Screen and Lock Screen widget
web/                        Firebase Hosting vote page, Firestore rules, Cloud Functions (pushes)
Design/                     Source artwork (app icon SVG, plus an alternate fork icon)
Licenses/                   Font and library licenses (shown in Settings → Acknowledgements)
Config/                     Your GoogleService-Info.plist (not committed)
```

## Known limits

- **MapKit has no cuisine data.** Cuisine chips search for phrases like "Mexican restaurant."
- **MapKit has no hours, photos, or menus.** The restaurant screen links to the restaurant's website, and Look Around stands in for photos.
- **"No fast food" matches a list of chain names** (`PickerCore/FastFood.swift`). Add names to it as you find gaps.
- **iMessage voting needs ForkRoad installed.** Friends without it use the web link, which is sent along with the vote.

## Roadmap

- [x] Phase 1: Discover, search radius, spin, lists, menu links, Look Around
- [x] Phase 2: Group picks in the app, iMessage app, web voting
- [x] Phase 3: Trips
- [x] iCloud sync of lists and trips
- [x] Outfit + DM Sans type
- [x] Push notifications for group picks
- [x] Onboarding, settings, light mode, cuisine icons, spin animation
- [x] Siri, Shortcuts, and a Home Screen widget
- [x] "How was it?" follow-ups, notes, dietary filters
- [ ] Hours and "Open now" (needs Google Places)
- [ ] Universal links, so vote links open the app when it's installed
