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
- Quick log: max 12 (`QuickLogRules`), presets have `inQuickLog`; new drinks ask before becoming a preset (scans are always remembered for their barcode). Drinks can only be logged up to 2 logical days back (`LogTimeLimit`). Backups: `Backup` (JSON, additive import, progress only goes up). Dojo test mode is `#if DEBUG` only.
- Companion: wording lives in `CompanionLines` (a few variants each, picked by a stable `seed` so text never flickers; variant 0 is what tests check). Drops outside Today are static (`animated: false`) except the day replay, which only animates while it plays. Repeating animations start one run loop after appearing (starting during a sheet's layout made the drop jump).
- Anything tappable over a `List` (toasts etc.) must live inside the list (e.g. a section footer): overlays and safe-area insets let taps fall through to rows.
- Performance: never summarize the whole history on a hot path. Old goal days/streaks live in `DojoArchive` (stored, advanced once a day); Today/Stats/AddDrink/Health/Reminders fetch only recent or candidate drinks. `BenchmarkTests` (BWMF_BENCHMARK=1) measures 10 years of data.
- New SwiftData properties must be optional (or have a default) so existing databases on test phones migrate.
- With Swift 6 + MainActor default isolation, custom `Shape`s and pure value types need `nonisolated`; so does any closure that SwiftUI/UIKit may call off the main thread (e.g. `UIColor { traits in … }` in `Color(light:dark:)`: as main-actor code it crashed the app during animations, 29 Oct).
- Nutrients are stored **per 100 ml**; totals are always computed from the current volume. They are saved as encoded `Data` (see `NutrientStorage`) because SwiftData crashes when reloading a struct whose fields are all nil.
- Days with no entries are "no data", never zero. Day boundaries go through `Calendar` (DST-safe), never `+ 86400`.
- Build/test from the CLI: `xcodebuild -scheme BeWaterMyFriend -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`
