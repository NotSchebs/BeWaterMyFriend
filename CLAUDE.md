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
- New SwiftData properties must be optional (or have a default) so existing databases on test phones migrate.
- With Swift 6 + MainActor default isolation, custom `Shape`s and pure value types need `nonisolated`.
- Nutrients are stored **per 100 ml**; totals are always computed from the current volume. They are saved as encoded `Data` (see `NutrientStorage`) because SwiftData crashes when reloading a struct whose fields are all nil.
- Days with no entries are "no data", never zero. Day boundaries go through `Calendar` (DST-safe), never `+ 86400`.
- Build/test from the CLI: `xcodebuild -scheme BeWaterMyFriend -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`
