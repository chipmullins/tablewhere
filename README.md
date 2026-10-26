# ForkRoad

**Every dinner is a fork in the road.** ForkRoad helps you decide where to eat: browse what's nearby, spin for a random pick, vote with friends in iMessage or on the web, and plan where to eat on trips.

Built with SwiftUI, SwiftData + CloudKit, MapKit, and Firebase. iOS 17+. Type is Outfit (headings) and DM Sans (body), bundled under the SIL Open Font License (see `Licenses/`).

## Features

- **Discover:** search restaurants by name or craving, plus a live map with your search radius (0.5 to 10 mi), multi-select cuisine filters (mix up to 4), and a "No fast food" toggle
- **Spin:** a slot-machine pick from Nearby, Favorites, or Interested that skips blacklisted places and avoids repeats from the past week
- **Restaurant screen:** Look Around, call, directions, menu and hours (their website, in the app), save, block
- **Lists:** Favorites (places you love), Interested (places to try), and Blacklisted (one place or a whole category). Any saved place can be left out of spins while staying on its list. Saved places are grouped into metro areas (cities within about 25 miles join the biggest one), so the lists and spins show the area you're in, any other area, or all of them. Syncs with iCloud.
- **Group picks:** vote or spin together, with a live tally, fair tie-breaks, a meeting time, and "send everyone the plan"
- **iMessage app:** start and vote on a dinner pick right in a group text
- **Web voting:** friends without ForkRoad vote from a link in any browser
- **Trips:** pick a city, browse its restaurants, and save spots for the trip

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
3. Set signing for **both** targets (ForkRoad and ForkRoadMessages): **Signing & Capabilities** → Team.
4. Pick an iPhone simulator or your phone and press **Run**.

The project file, Info.plists, and entitlements are generated from `project.yml`, so edit that instead of changing them in Xcode. Run `xcodegen generate` again after pulling changes.

**Simulator tip:** set a location with **Features → Location**, or the app uses Lexington, KY.

### Apple Developer Program

iCloud sync, the shared sign-in between the app and the iMessage extension, and TestFlight need a paid Apple Developer Program membership on your team. On a free account, the app still runs, but lists stay on the device. If signing complains about iCloud or Keychain Sharing, check that your paid team is selected for both targets.

## Firebase setup (for group voting)

Everything except group picks works without this, and the project builds without it (you'll see a warning). It takes about 10 minutes and is free on Firebase's Spark plan.

1. Go to [console.firebase.google.com](https://console.firebase.google.com) → **Add project** (e.g. `forkroad-app`). Analytics is optional.
2. **Build → Authentication → Get started → Sign-in method →** enable **Anonymous**.
3. **Build → Firestore Database → Create database →** production mode, pick a nearby region.
4. **Project settings → Your apps → Add app → iOS.** Bundle ID: `com.chipmullins.forkroad`. Download **GoogleService-Info.plist** and put it in `Config/`. (It's ignored by Git.)
5. **Add app → Web.** Copy the `firebaseConfig` it shows into `web/public/firebase-config.js` (start from `firebase-config.example.js`).
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

### How group picks work

- Sessions live in Firestore (`sessions/{id}`, with `votes` and `members` subcollections). Everyone signs in anonymously, so there are no accounts.
- `web/firestore.rules` lets anyone with the link see a session, but nobody can list sessions. Join codes are looked up one at a time through `joinCodes/{code}`. Only you can write your own vote, and only until the timer runs out. Only the creator can lock in the result or set the meeting time. Other people can only add places while the vote is open.
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
web/                        Firebase Hosting vote page and Firestore rules
Design/                     Source artwork (app icon SVG)
Licenses/                   Font licenses (SIL OFL)
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
- [ ] Light mode
- [ ] Push notifications when a group pick is decided
- [ ] Universal links, so vote links open the app when it's installed
