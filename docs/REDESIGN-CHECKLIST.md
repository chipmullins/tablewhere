# Sleek redesign: functionality checklist (1.2.0)

Written from the code at `pre-redesign` (`30771c9`, 1.1.1 build 45) before any
UI changed. Every item is something a person can see, tap, or get today. Each
one is ticked only after it was carried into the new layout on the `redesign`
branch, with where it lives now. Nothing ships unticked.

Revert: build from the `pre-redesign` branch, or see "How to revert" in the
README's redesign note.

## App shell (RootTabView)
- [ ] Four tabs: Discover, Spin, Lists, Group (now the floating pill bar; VoiceOver labels on icon-only tabs, selected trait on the active one)
- [ ] Reopens on the last tab used (`lastTab`)
- [ ] Undo toast above the tab bar; hidden when switching tabs
- [ ] Dynamic Type capped at accessibility2
- [ ] Deep links: `https://<webHost>/v/<id>` (Universal Link), `forkroad://place?d=`, `forkroad://spin?go=1`, `forkroad://spin|discover|lists|group/<id>`
- [ ] `DeepLink` notification hand-off (notifications, Live Activity, widget)
- [ ] On foreground: usage stats active device, leave-by refresh, "How was it?" follow-up
- [ ] "How was it?" sheet: Loved it / It was fine / Never again / We didn't go; swipe away counts as skipped
- [ ] Shared caches for widget, Siri, iMessage refresh when lists change

## Spin (SpinView, PickedWheel)
- [ ] Eat out / Eat in switch
- [ ] Sources: Nearby, Custom, Favorites, To try
- [ ] Nearby filters sheet: location (search), Use my location, Choose on map, radius, cuisines (up to 4), diet, No fast food / No coffee & sweets
- [ ] Favorites / To try: area menu (CityMenu) and No fast food chip
- [ ] Custom wheel editor: add places, type your own, remove, clear, max 20, needs 2 to spin
- [ ] Eat in: empty state "Add a meal", meal count, Add, Edit (opens Lists → Home)
- [ ] Late-night note
- [ ] Pool rules: skips blacklist (place + category), favors places not spun lately (last week), radius only for Nearby, coffee filter off for saved lists, "Not tonight" places sit out 6 h, Leave out of spins honored
- [ ] Spin button (disabled under the minimum), footnote ("N places · favors ones you haven't spun lately", left-out count, area)
- [ ] Full-screen reveal (sparkles, names flying) when "Full-screen spin" is on; quick reel when off; Reduce Motion fade
- [ ] Landing haptic, burst, VoiceOver announcement "Your pick: …"
- [ ] Records spin history and usage stats (spins, eatInSpins)
- [ ] Pending spin from other tabs, widget, Siri, Control Center (`pendingSpin`), waits for search results
- [ ] Reel resets when source, area, location, radius, or wheel changes
- [ ] Empty reel messages (location off, no location, offline, loading, none in range, empty lists)
- [ ] Hints: spinFirst, myWheel, eatIn
- [ ] Result: "Picked from N places"
- [ ] Result actions: Call (disabled without phone), Go / directions + visit follow-up, Favorite, Try, Blacklist (with Undo; also off a Custom wheel)
- [ ] Result: See details (zoom transition on iOS 18), Share your pick (share card)
- [ ] Result: "Not tonight · spin again" (Undo; last-one message)
- [ ] Result: Spin again (without skipping)
- [ ] Typed wheel picks show "From your wheel" with no actions
- [ ] Eat in result: "Tonight you're making", note, Open the recipe, "Missing something? Not tonight · spin again", swipe left, VoiceOver action

## Discover (DiscoverView, NearbyMap, RestaurantSearch, LocationPickerView)
- [ ] Location: change (LocationPickerView: search cities, recent, remove recent), Use my location
- [ ] Settings button
- [ ] Search by name or craving (2+ characters), clear search, results open details
- [ ] Where-to-look card when there's no location (Use my location / Pick a city / Open Settings when denied)
- [ ] Map of results with radius circle; full-screen map: tap a place (card with Details + Directions), tap elsewhere to search there, Search this area, My location, Done
- [ ] Radius slider 0.5–10 mi with presets
- [ ] Cuisine chips (multi, up to 4, "Mixing …" line), diet chips, Filters chip (No fast food, No coffee & sweets)
- [ ] Label memory (search remembers what a place is called)
- [ ] "Spin for it" banner with the filter summary
- [ ] Nearby list (nearest first, Show more · N left), loading skeleton, pull to refresh
- [ ] States: location off, can't reach Apple Maps (Try again), empty with "Search N mi instead" / "Clear filters"
- [ ] Hint: discoverMap
- [ ] Widget pick opens its details (`pendingPlace`)

## Place detail (PlaceDetailView)
- [ ] Look Around (or map) hero; no-address state for your own places
- [ ] Name, category, distance, "added by you"
- [ ] Call, Go (Apple/Google per PlaceLinks), Favorite, Try, Blacklist (just this place / all of the category) or Edit for your own places
- [ ] Leave out of spins toggle, Your note
- [ ] View menu & hours (in-app Safari), address (selectable)
- [ ] Share (added in 1.2: was only on the Spin result)

## Lists (ListsView, AddToListSheet, CustomPlaceForm, RecipeForm, CityMenu)
- [ ] Favorites, To try, Home, Blacklist with counts
- [ ] Add a place (search or your own: CustomPlaceForm with area, list, type, Leave out of spins, delete)
- [ ] Area menu, metro grouping on All areas, "Show all areas"
- [ ] Spin these (per list and area)
- [ ] Swipe actions (move to Favorites/To try, leave out of spins, remove) with haptics; left-out and recipe-link badges
- [ ] Home meals: add, edit, delete, recipe link, Spin what to make
- [ ] Blacklist: places and categories, remove
- [ ] Empty states; Hint listsAdd; fills in missing cities; iCloud sync (SwiftData + CloudKit, unchanged)
- [ ] Opens on Home from Spin → Eat in → Edit

## Groups (GroupHomeView, CreateGroupView, GroupLobbyView, Shared/GroupUI, Shared/UI/GroupComponents)
- [ ] Group home: Start a group plan, Got a code? Join, Recent (live title/status, remove), name prompt, setup notice, empty state
- [ ] "New in" card → group tour pages
- [ ] Create: Vote, Spin our picks, Surprise us, I'll pick; name; places picker; Surprise wheel (area, filters, shuffle, remove); group filters; voting closes; date & time; I'll pick note, RSVPs, reply-by; Send the plan share sheet
- [ ] Lobby: header (title, meet time, filters line, join code, avatars, count line, invite share), invite card, expected count, group filters card
- [ ] Voting: live tally, your vote / change it, ruled-out reasons, vote countdown, notices, tie note, Add a place (picks), spin progress "3 of 4 picks in", owner tools (nudge, remove), lock in / spin with warnings
- [ ] Spin reveal for everyone watching
- [ ] Decided: winner card, Directions / Call / Website, meet time slots + custom, plan time / change place, RSVP settings and panel, note for the group, Add to Calendar, leave-by card (reminder with traffic, exact-location option), On my way, vote breakdown, share as image, Send everyone the plan
- [ ] Menu: End group for everyone / Leave group, Reopen voting
- [ ] Opens from links, codes, notifications (`pendingGroupSessionID`); push alerts permission ask

## Getting there
- [ ] Leave-by reminder notification + its action (GroupPlanActionRunner)
- [ ] Live Activity countdown and its buttons (unchanged)
- [ ] On my way: I'm on my way (live ETA), Running late (+10/+15/+30, I'll text you), I'm here, Stop sharing, "You're here. Enjoy!", Everyone's here, footnote "never where you are"
- [ ] Friends' times feed the Lock Screen countdown

## Trips
- [ ] Trips UI was removed before 1.0 (data model kept only for store migration). Other cities are covered by the area menu and Choose on map. Nothing to carry over.

## Settings (SettingsView, AcknowledgementsView)
- [ ] Your name; search radius, No fast food, No coffee & sweets, diet; Full-screen spin; Lock Screen countdown starts / remove; Appearance; Ask "How was it?"; alerts status + turn on / open Settings; Share anonymous usage counts; Clear spin history (confirm); Take the tour; Show tips again; Version, Restaurant data, Credits, Privacy Policy, footer

## Onboarding (OnboardingView, TourMockups)
- [ ] 7 pages: welcome, spin, lists, group ways, group join, plans, permissions; Skip; page dots with labels; location + notification permission asks; group-only tour from "New in"

## iMessage app (MessagesExtension)
- [ ] Start a new plan / New vote (modes, places, filters, voting closes, web link toggle), vote view, add a place, plan controls (times), decided section with On my way, invite, end/leave, try again

## Widgets and system
- [ ] Tonight's pick widget with Spin again (SpinAgainIntent), Control Center Spin control, Lock Screen Live Activity (stays as is)
- [ ] Shortcuts/Siri: Pick dinner, Spin, Open Spin
- [ ] Usage stats calls unchanged
- [ ] VoiceOver labels, Dynamic Type, dark mode, Reduce Motion throughout
