# CLAUDE.md

BeWaterMyFriend: SwiftUI + SwiftData hydration tracker for iPhone, later with HealthKit. This is a graded university project on AI-assisted programming, so how code gets written matters as much as the code.

## Ownership rules (from the exposé — follow these)

- **The developer writes the data model and calculation logic** (SwiftData models, daily totals, custom day boundary, goal calculation) themselves or with minimal help. For these, Claude explains, reviews, and writes *tests*, but does not write the implementation unless explicitly asked.
- Claude may write SwiftUI views and boilerplate more freely.
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
- Build/test from the CLI: `xcodebuild -scheme BeWaterMyFriend -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`
