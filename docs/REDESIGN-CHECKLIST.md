# Sleek redesign: functionality checklist (1.2.0)

Written from the code at `pre-redesign` (`30771c9`, 1.1.1 build 45) before any
UI changed. Every item is something a person can see, tap, or get today. Each
one is ticked only after it was carried into the new layout on the `redesign`
branch, with where it lives now. Nothing ships unticked.

## How to revert
- Nothing to undo while it's only on `redesign`: `main` is untouched. Build from `main` or `pre-redesign`.
- If it was merged and you want it gone: `git checkout main && git reset --hard pre-redesign` then a force push (only with your OK), or just build from `pre-redesign`.

## Status
All items carried over and ticked. Compile review (read-only, no Swift toolchain in the sandbox) found no compile errors; its eight behavior notes were fixed in "Review fixes". Still to check on a device: the system tab bar never flashes back on push/pop, and nothing sits under the floating pill.

## App shell (RootTabView)
_Now: `FloatingTabBar` over a `TabView` with the system bar hidden; every tab gets `floatingTabBarClearance()`. Undo toast moved above the pill. Deep links, caches, follow-up unchanged._
- [x] Four tabs: Discover, Spin, Lists, Group (now the floating pill bar; VoiceOver labels on icon-only tabs, selected trait on the active one)
- [x] Reopens on the last tab used (`lastTab`)
- [x] Undo toast above the tab bar; hidden when switching tabs
- [x] Dynamic Type capped at accessibility2
- [x] Deep links: `https://<webHost>/v/<id>` (Universal Link), `forkroad://place?d=`, `forkroad://spin?go=1`, `forkroad://spin|discover|lists|group/<id>`
- [x] `DeepLink` notification hand-off (notifications, Live Activity, widget)
- [x] On foreground: usage stats active device, leave-by refresh, "How was it?" follow-up
- [x] "How was it?" sheet: Loved it / It was fine / Never again / We didn't go; swipe away counts as skipped
- [x] Shared caches for widget, Siri, iMessage refresh when lists change

## Spin (SpinView, PickedWheel)
_Now: `SpinView` (map hero + pills + sheet), `SpinStage` (button, quick reel, reveal, rules), `SpinResultView` (full-screen pick), `SearchFiltersSheet` (moved out of SpinView). Spin again without skipping: ↻ in the result header (and a VoiceOver action). New: "Make it a group plan" opens New group plan as I'll pick with the place._
- [x] Eat out / Eat in switch
- [x] Sources: Nearby, Custom, Favorites, To try
- [x] Nearby filters sheet: location (search), Use my location, Choose on map, radius, cuisines (up to 4), diet, No fast food / No coffee & sweets
- [x] Favorites / To try: area menu (CityMenu) and No fast food chip
- [x] Custom wheel editor: add places, type your own, remove, clear, max 20, needs 2 to spin
- [x] Eat in: empty state "Add a meal", meal count, Add, Edit (opens Lists → Home)
- [x] Late-night note
- [x] Pool rules: skips blacklist (place + category), favors places not spun lately (last week), radius only for Nearby, coffee filter off for saved lists, "Not tonight" places sit out 6 h, Leave out of spins honored
- [x] Spin button (disabled under the minimum), footnote ("N places · favors ones you haven't spun lately", left-out count, area)
- [x] Full-screen reveal (sparkles, names flying) when "Full-screen spin" is on; quick reel when off; Reduce Motion fade
- [x] Landing haptic, burst, VoiceOver announcement "Your pick: …"
- [x] Records spin history and usage stats (spins, eatInSpins)
- [x] Pending spin from other tabs, widget, Siri, Control Center (`pendingSpin`), waits for search results
- [x] Reel resets when source, area, location, radius, or wheel changes
- [x] Empty reel messages (location off, no location, offline, loading, none in range, empty lists)
- [x] Hints: spinFirst, myWheel, eatIn
- [x] Result: "Picked from N places"
- [x] Result actions: Call (disabled without phone), Go / directions + visit follow-up, Favorite, Try, Blacklist (with Undo; also off a Custom wheel)
- [x] Result: See details (zoom transition on iOS 18), Share your pick (share card)
- [x] Result: "Not tonight · spin again" (Undo; last-one message)
- [x] Result: Spin again (without skipping)
- [x] Typed wheel picks show "From your wheel" with no actions
- [x] Eat in result: "Tonight you're making", note, Open the recipe, "Missing something? Not tonight · spin again", swipe left, VoiceOver action

## Discover (DiscoverView, NearbyMap, RestaurantSearch, LocationPickerView)
_Now: "Find a place" + Settings, search first, cuisine chips, location and Filters pills (radius, diet, cuisines in `SearchFiltersSheet`), slim Spin for it row, clean rows with initial tiles and a Favorite heart. The inline map moved to Spin's hero; Discover's "Map" link opens the full map (radius circle, tap to search, Search this area)._
- [x] Location: change (LocationPickerView: search cities, recent, remove recent), Use my location
- [x] Settings button
- [x] Search by name or craving (2+ characters), clear search, results open details
- [x] Where-to-look card when there's no location (Use my location / Pick a city / Open Settings when denied)
- [x] Map of results with radius circle; full-screen map: tap a place (card with Details + Directions), tap elsewhere to search there, Search this area, My location, Done
- [x] Radius slider 0.5–10 mi with presets
- [x] Cuisine chips (multi, up to 4, "Mixing …" line), diet chips, Filters chip (No fast food, No coffee & sweets)
- [x] Label memory (search remembers what a place is called)
- [x] "Spin for it" banner with the filter summary
- [x] Nearby list (nearest first, Show more · N left), loading skeleton, pull to refresh
- [x] States: location off, can't reach Apple Maps (Try again), empty with "Search N mi instead" / "Clear filters"
- [x] Hint: discoverMap
- [x] Widget pick opens its details (`pendingPlace`)

## Place detail (PlaceDetailView)
_Now: cream sheet over Look Around, icon actions (Call, Favorite, Try later, Blacklist/Edit, Share), one primary "Let's go · directions", menu as a row._
- [x] Look Around (or map) hero; no-address state for your own places
- [x] Name, category, distance, "added by you"
- [x] Call, Go (Apple/Google per PlaceLinks), Favorite, Try, Blacklist (just this place / all of the category) or Edit for your own places
- [x] Leave out of spins toggle, Your note
- [x] View menu & hours (in-app Safari), address (selectable)
- [x] Share (added in 1.2: was only on the Spin result)

## Lists (ListsView, AddToListSheet, CustomPlaceForm, RecipeForm, CityMenu)
_Now: pill segmented tabs, initial tiles, compact sections. Forms unchanged apart from theme._
- [x] Favorites, To try, Home, Blacklist with counts
- [x] Add a place (search or your own: CustomPlaceForm with area, list, type, Leave out of spins, delete)
- [x] Area menu, metro grouping on All areas, "Show all areas"
- [x] Spin these (per list and area)
- [x] Swipe actions (move to Favorites/To try, leave out of spins, remove) with haptics; left-out and recipe-link badges
- [x] Home meals: add, edit, delete, recipe link, Spin what to make
- [x] Blacklist: places and categories, remove
- [x] Empty states; Hint listsAdd; fills in missing cities; iCloud sync (SwiftData + CloudKit, unchanged)
- [x] Opens on Home from Spin → Eat in → Edit

## Groups (GroupHomeView, CreateGroupView, GroupLobbyView, Shared/GroupUI, Shared/UI/GroupComponents)
_Now: dark Start card on Group home; `WinnerCard` becomes the dark "Meet in" hero (countdown, avatars, "1 of 4 here") while a meet time is ahead; Directions is the one primary with Call/Website as icons. Everything else in the lobby is unchanged in behavior._
- [x] Group home: Start a group plan, Got a code? Join, Recent (live title/status, remove), name prompt, setup notice, empty state
- [x] "New in" card → group tour pages
- [x] Create: Vote, Spin our picks, Surprise us, I'll pick; name; places picker; Surprise wheel (area, filters, shuffle, remove); group filters; voting closes; date & time; I'll pick note, RSVPs, reply-by; Send the plan share sheet
- [x] Lobby: header (title, meet time, filters line, join code, avatars, count line, invite share), invite card, expected count, group filters card
- [x] Voting: live tally, your vote / change it, ruled-out reasons, vote countdown, notices, tie note, Add a place (picks), spin progress "3 of 4 picks in", owner tools (nudge, remove), lock in / spin with warnings
- [x] Spin reveal for everyone watching
- [x] Decided: winner card, Directions / Call / Website, meet time slots + custom, plan time / change place, RSVP settings and panel, note for the group, Add to Calendar, leave-by card (reminder with traffic, exact-location option), On my way, vote breakdown, share as image, Send everyone the plan
- [x] Menu: End group for everyone / Leave group, Reopen voting
- [x] Opens from links, codes, notifications (`pendingGroupSessionID`); push alerts permission ask

## Getting there
_Now: `OnMyWayCard` has a row and progress bar per person (times only), "I'm on my way" + "Late +10" side by side (hold Late for +15/+30/I'll text you), then I'm here / Running late / Stop sharing. It sits right under the plan hero. Live Activity untouched._
- [x] Leave-by reminder notification + its action (GroupPlanActionRunner)
- [x] Live Activity countdown and its buttons (unchanged)
- [x] On my way: I'm on my way (live ETA), Running late (+10/+15/+30, I'll text you), I'm here, Stop sharing, "You're here. Enjoy!", Everyone's here, footnote "never where you are"
- [x] Friends' times feed the Lock Screen countdown

## Trips
- [x] Trips UI was removed before 1.0 (data model kept only for store migration). Other cities are covered by the area menu and Choose on map. Nothing to carry over.

## Settings (SettingsView, AcknowledgementsView)
_Now: large title, compact sections, readable tint. All rows unchanged._
- [x] Your name; search radius, No fast food, No coffee & sweets, diet; Full-screen spin; Lock Screen countdown starts / remove; Appearance; Ask "How was it?"; alerts status + turn on / open Settings; Share anonymous usage counts; Clear spin history (confirm); Take the tour; Show tips again; Version, Restaurant data, Credits, Privacy Policy, footer

## Onboarding (OnboardingView, TourMockups)
_Now: bigger titles, sleek primary button, tour's Spin art shows the new screen._
- [x] 7 pages: welcome, spin, lists, group ways, group join, plans, permissions; Skip; page dots with labels; location + notification permission asks; group-only tour from "New in"

## iMessage app (MessagesExtension)
_Now: same plan hero, icon actions, On the way rows and sleek buttons as the app._
- [x] Start a new plan / New vote (modes, places, filters, voting closes, web link toggle), vote view, add a place, plan controls (times), decided section with On my way, invite, end/leave, try again

## Widgets and system
_Now: Tonight's pick says "THE WHEEL PICKED" with bigger type and an initial tile; Spin again, Control Center control, Live Activity, Siri unchanged._
- [x] Tonight's pick widget with Spin again (SpinAgainIntent), Control Center Spin control, Lock Screen Live Activity (stays as is)
- [x] Shortcuts/Siri: Pick dinner, Spin, Open Spin
- [x] Usage stats calls unchanged
- [x] VoiceOver labels, Dynamic Type, dark mode, Reduce Motion throughout
