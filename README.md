# ForkRoad

**Every dinner is a fork in the road.** ForkRoad helps you decide where to eat: browse what's nearby, spin for a random pick, keep an Interested list, and block places or whole cuisines you never want suggested.

Built with SwiftUI, SwiftData, and MapKit. iOS 17+.

## Run it

You need a Mac with a current version of Xcode.

1. Install [Homebrew](https://brew.sh) if you don't have it, then install XcodeGen:
   ```sh
   brew install xcodegen
   ```
2. Clone the repo and generate the Xcode project:
   ```sh
   git clone https://github.com/chipmullins/forkroad.git
   cd forkroad
   xcodegen generate
   open ForkRoad.xcodeproj
   ```
3. In Xcode, select the **ForkRoad** target → **Signing & Capabilities** → choose your Team (your Apple ID works).
4. Pick an iPhone simulator or your phone and press **Run**.

The `.xcodeproj` is generated from `project.yml` and isn't committed. Run `xcodegen generate` again after pulling changes that add or move files.

**Simulator tip:** set a location with **Features → Location** in the Simulator menu, or the app falls back to Lexington, KY.

## Run the tests

```sh
cd Packages/PickerCore
swift test
```

## Project layout

```
project.yml                 XcodeGen project definition
ForkRoad/
  App/                      App entry point and shared AppModel
  Features/
    Discover/               Home screen, map, radius slider
    Spin/                   The randomizer reel
    Detail/                 Restaurant screen, menu, Look Around
    Lists/                  Interested and Blocked lists
  Models/                   SwiftData models and list actions
  Services/                 Location, MapKit search, Maps/phone links
  UI/                       Theme, shared components, in-app browser
  Resources/                Asset catalog (app icon, accent color)
Packages/PickerCore/        Shared logic: Place, cuisine filters, randomizer (+ tests)
Design/                     Source artwork (app icon SVG)
```

`PickerCore` has no UI or network code, so the important logic is unit tested and can be shared with the iMessage extension in Phase 2.

## Known limits of MapKit

- **No cuisine data.** Cuisine chips work by searching for phrases like "Mexican restaurant."
- **No hours, photos, or menus.** The restaurant screen links to the restaurant's website for menus and hours, and uses Look Around street imagery in place of photos.
- **Limited results per search.** Fine for picking dinner, not a full directory.

## Roadmap

- [x] **Phase 1 — Solo:** Discover, search radius, cuisine filters, spin, Interested and Blocked lists, menu links, Look Around
- [ ] iCloud sync of lists (CloudKit)
- [ ] **Phase 2 — Groups:** iMessage extension voting, then an in-app group lobby
- [ ] **Phase 3 — Trips:** explore other cities and keep trip lists
- [ ] Light mode, custom display font
