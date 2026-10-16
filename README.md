# BeWaterMyFriend

A dojo-themed hydration tracker for iPhone, built with SwiftUI and SwiftData, with Apple Health integration.

Mini-Challenge *KI-gestütztes Programmieren (kip)*, HS26 — Sébastien André Bagdasarianz.

> All goals and values in this app are estimates, not medical advice.

## Scope

**MVP**
- Quick drink logging (presets, favourites, edit, delete)
- Manual daily water goal
- Customizable end of day
- Separate water, caffeine and alcohol totals
- History and monthly summary
- Optional ninja-drop companion (toggle; never dies by default)
- Unit tests for calculation and date logic

**Phase 2:** write water and caffeine to Apple Health, read workouts, transparent suggested goal.

**Stretch:** pace-based reminders, Open-Meteo weather input, barcode scanning, widget, companion streaks.

**Future:** Apple Watch app.

## Requirements

- Xcode 27, iOS 27 SDK
- Runs fully offline; no account or backend

## Development

Open `BeWaterMyFriend.xcodeproj` in Xcode and run on an iPhone simulator. Run tests with ⌘U.
