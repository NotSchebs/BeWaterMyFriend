# CLAUDE.md

BeWaterMyFriend: SwiftUI + SwiftData hydration tracker for iPhone, later with HealthKit. This is a graded university project on AI-assisted programming, so how code gets written matters as much as the code.

## Ownership rules (from the exposé — follow these)

- **The developer designs the data model and calculation logic** (fields, types, what's optional, how values are stored). Originally the developer also wrote the implementation; on 19 Oct the developer asked Claude to implement the MVP from that design. From now on, Claude may implement, but must explain non-obvious choices so the developer can explain every core file, and every core logic change needs tests.
- Claude may write SwiftUI views and boilerplate freely.
- Every HealthKit snippet must cite the Apple documentation it relies on, so it can be checked.
- Small steps, one feature at a time. After each step, suggest a one-line diary entry (what was done, the decision, and whether it worked).

## Design principles

- All goals and values are estimates, not medical advice. The goal is always user-editable; any automatic adjustment is transparent and overridable.
- Never claim a drink dehydrates you by a specific amount.
- Everything works offline. Optional inputs (weather, location, camera) are off by default and never required.
- The companion never dies or loses progress by default.

## Tech

- Swift, SwiftUI, SwiftData, HealthKit (Phase 2), XCTest
- Test-driven for daily/weekly/monthly totals, the day boundary and goal calculation. UI is checked manually.
- Layout: `Model/` (SwiftData models, `Nutrients`), `Logic/` (pure, tested: `DrinkMath`, `DayBoundary`, `Summaries`, `DojoProgress`, `HealthPlan`, `EntryActions`), `Health/` (the only file that imports HealthKit), `Views/`. Tests mirror `Logic/` and `Model/`.
- Health sync: each entry's samples carry its `healthSyncID` in metadata; edits delete and rewrite them, deletes go through `EntryActions.delete` so Health is cleaned up too. Writes respect the user's delay (`HealthWriteDelay`); every edit restarts it.
- Scanning: `Logic/OpenFoodFacts.swift` parses Open Food Facts (values in grams → app units; tested with saved real responses in `OFFFixtures`). Every scan goes through the review editor; a preset with the same barcode wins over online data. Camera via VisionKit only works on a real device.
- Powder drinks (`.electrolytes`, `.proteinShake`): `powderGrams` set → nutrients are per 100 g of powder, scaled via `entry.nutrientBase`; `volumeML` is the liquid. Always scale nutrients with `nutrientBase`, never `volumeML` directly.
- Ranks: `Belt` covers coloured belts and 10 Dan ranks; prestige (opt-in, confirmed) offsets rank goal days via `prestigeBaseGoalDays`. Companion colours and moods come from `CompanionLogic` (pure, tested).
- Health sync must take its `isSyncing` lock before the first `await` (a race here caused duplicate Health entries); `write` always deletes a drink's samples by sync ID before writing.
- Reminders: `ReminderPlanner` (pure, tested) picks one random time per interval; `ReminderScheduler` re-plans local notifications on app open and after every save (iOS can't wake the app at reminder time).
- Quick log order is `sortOrder` only, shared with the Settings list. Stars (`DrinkStars`, `starNumber`) are ★1–★3 for the widgets only and don't affect it; `isFavourite` is only read once to migrate old favourites. Long press opens the edit mode: the page scrolls the grid under the floating Done (in ContentView, so nothing shifts) and stops scrolling, so a drag moves tiles at once. During a drag nothing is saved and the layout is frozen: tiles only move by `.offset` (`draftOrder`), the order is saved once on release; saving on every swap stuttered on the iPhone. Measure slots outside the offset/rotation and not during a drag: measuring moving tiles made them shake (custom drag gesture: iOS drag and drop did not start inside a List row; tiles use tap + long-press gestures because a Button would also log on release).
- Never store measured layout (`onGeometryChange`) in state the same view reads: that loop ran the app at 100 % CPU in Quick log edit mode (31 Oct). Unknown scans: `DrinkDraft.needsType` blocks saving until a type is chosen; nothing defaults to water.
- Widgets (target `BeWaterMyFriendWidgetExtension`, folder `BeWaterMyFriendWidget/`): they never touch the database. The app writes a `WidgetSnapshot` to the App Group (`WidgetBridge.publish`, only if changed); a widget button leaves a note (`WidgetStore.addPending`) that the widget counts itself and the app turns into a real drink on opening (`drainPending`), keeping the tap's time. Shared source files are listed in the project's membership exception set. Widgets get no app accent colour, so use `Dojo.ink`. `Color.accentColor` stays blue there.
- Database versions: `Model/DrinkSchema.swift`. Optional new fields need no new version; renames, type changes or new required fields do (steps in that file). `DatabaseUpgradeTests` opens a sample database saved before versions existed; update the expected structure there when fields change.
- The database must stay at `DrinkDatabase.storeConfiguration` (`groupContainer: .none`): with an App Group, SwiftData's default silently opens a new, empty store in the group folder. Tested.
- iOS doesn't let a widget's intent open the app (`openAppWhenRun` fails in extensions), so "+" is a `Link`, on Small too (tested on iOS 27).
- Quick log: max 12 (`QuickLogRules`), presets have `inQuickLog`; new drinks ask before becoming a preset (scans are always remembered for their barcode). Drinks can only be logged up to 2 logical days back (`LogTimeLimit`). Backups: `Backup` (JSON, additive import, progress only goes up). Dojo test mode is `#if DEBUG` only.
- Companion: wording lives in `CompanionLines` (a few variants each, picked by a stable `seed` so text never flickers; variant 0 is what tests check). Drops outside Today are static (`animated: false`) except the day replay, which only animates while it plays. Repeating animations start one run loop after appearing (starting during a sheet's layout made the drop jump).
- Anything tappable over a `List` (toasts etc.) must live inside the list (e.g. a section footer): overlays and safe-area insets let taps fall through to rows.
- Performance: never summarize the whole history on a hot path. Old goal days/streaks live in `DojoArchive` (stored, advanced once a day); Today/Stats/AddDrink/Health/Reminders fetch only recent or candidate drinks. `BenchmarkTests` (BWMF_BENCHMARK=1) measures 10 years of data.
- New SwiftData properties must be optional (or have a default) so existing databases migrate automatically; anything else needs a new schema version.
- With Swift 6 + MainActor default isolation, custom `Shape`s and pure value types need `nonisolated`; so does any closure that SwiftUI/UIKit may call off the main thread (e.g. `UIColor { traits in … }` in `Color(light:dark:)`: as main-actor code it crashed the app during animations, 29 Oct; `FileDocument` types are read/written on a background thread too).
- Nutrients are stored **per 100 ml**; totals are always computed from the current volume. They are saved as encoded `Data` (see `NutrientStorage`) because SwiftData crashes when reloading a struct whose fields are all nil.
- Days with no entries are "no data", never zero. Day boundaries go through `Calendar` (DST-safe), never `+ 86400`.
- Smoke tests (UI): scheme `SmokeTests` (target `BeWaterMyFriendUITests`) taps through the app; run them on the iPhone too (it must be unlocked). They launch with `-UITestMode` (`AppEnvironment`, debug only): sample drinks in memory, separate wiped settings, no Health/weather/reminders, so a run never touches real data.
- Background work (Health sync, goal refresh, reminders) lives in `BackgroundJobs`; ContentView only triggers it. Stats drop decisions live in `Logic/StatsCompanion` (tested); views only draw.
- Large text: tile rows use `StatTileRow` (stacks at accessibility sizes); fixed-size things (ring text, calendar) cap `dynamicTypeSize`.
- Build/test from the CLI: `xcodebuild -scheme BeWaterMyFriend -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`
