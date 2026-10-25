# BeWaterMyFriend

A dojo-themed hydration tracker for iPhone with a ninja-drop companion, built with SwiftUI and SwiftData, with Apple Health integration and barcode scanning.

Mini-Challenge *KI-gestütztes Programmieren (kip)*, HS26 — Sébastien André Bagdasarianz.

> All goals and values in this app are estimates, not medical advice.

## Features

**Logging**
- One-tap presets with favourites; drinks can be added, edited and deleted
- 16 drink types with a free-text name, amount, time and optional alcohol %
- All nutrients that Apple Health supports (38), stored per 100 ml and scaled to the amount
- Powder drinks (electrolytes, protein): scoop size in grams plus the liquid it was mixed with
- Barcode scanning (camera, or type the number) with data from [Open Food Facts](https://world.openfoodfacts.org); every scan is reviewed before saving, and corrections are remembered for that barcode

**Goal and history**
- Daily goal, custom end of day (e.g. 3 am for late nights)
- Each drink counts toward the goal with a percentage: automatic (non-alcohol share, so a 5 % beer counts 95 %) or set by hand
- Separate totals for water, caffeine, alcohol (standard drinks) and nutrients
- History by day and month; days without entries count as "no data", not zero

**Ninja drop**
- Fills in the colours of the day's drinks (grouped by type, with a legend) and grows with progress
- Reacts to the last drink: jittery after caffeine, tipsy after alcohol (extra drunk after too much), flexing after protein, sparks after electrolytes
- Belts from white to black, then ten Dan ranks and an optional prestige; ranks are never lost
- The mask shows the current belt; can be turned off

**Apple Health**
- Writes water, caffeine, alcohol and known nutrients (40 types), immediately, after 1 hour, or at the end of the day
- Edits and deletes are updated in Health (every sample is tagged with its drink's sync ID)

**Reminders**
- At a random moment within each interval (default every hour, 9:00–18:00), optionally skipped when on track
- Long-press a reminder to log the last drink again, add a new one, or scan

**Other:** System, Light or Dark appearance.

## Privacy

No account and no backend. Data stays on the phone and, if allowed, in Apple Health. The only network request is the barcode lookup on Open Food Facts (only the barcode number is sent). The camera is used only while scanning.

## Project structure

| Folder | Contents |
|---|---|
| `BeWaterMyFriend/Model` | SwiftData models (`DrinkEntry`, `DrinkPreset`), nutrients, drink types |
| `BeWaterMyFriend/Logic` | Pure, tested logic: day boundary, totals, goal %, belts, moods, Health plan, Open Food Facts parsing, reminder planning |
| `BeWaterMyFriend/Health` | HealthKit sync (the only file using HealthKit) |
| `BeWaterMyFriend/Notifications` | Reminder scheduling and actions |
| `BeWaterMyFriend/Views` | SwiftUI screens and the companion |
| `BeWaterMyFriendTests` | XCTest unit tests (96), including daylight-saving days and real Open Food Facts responses |
| `Design` | App icon and icon concepts, with the scripts that generate them |

## Requirements

- Xcode 27, iOS 26 or newer
- A free Apple ID is enough to run it on your own iPhone (reinstall every 7 days)

## Development

Open `BeWaterMyFriend.xcodeproj` in Xcode and run on an iPhone or simulator. Run the tests with ⌘U, or:

```bash
xcodebuild -scheme BeWaterMyFriend -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Camera scanning, Health permissions and reminders work best on a real device.

## Credits

Product data from [Open Food Facts](https://world.openfoodfacts.org), available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).
