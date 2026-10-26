import SwiftUI

/// Answers shown in the FAQ (and reused elsewhere, e.g. the standard-drink info).
enum FAQ {
    static let standardDrink = "One standard drink is 10 g of pure alcohol (the WHO's measure). A 330 ml beer with 5 % is about 1.3, a 150 ml glass of wine with 12 % about 1.4, a 40 ml shot with 40 % about 1.3. Apple Health uses the same unit."

    static let items: [(question: String, answer: String)] = [
        ("How is my goal calculated?",
         "Manual: you set it. Suggested: your weight × 35 ml per kg, plus extra for today's workouts (1 l per hour by default) and for hot or cold days. Settings › Daily water goal shows the calculation; every number can be changed under \"Adjust the formula\". All values are estimates, not medical advice."),
        ("Why does a beer count less than water?",
         "Each drink counts with a percentage toward your water goal. Automatic: non-alcoholic drinks count fully, alcoholic drinks count their non-alcohol part (a 5 % beer counts 95 %). You can set your own percentage per drink or preset."),
        ("What does \"std. drinks\" mean?", standardDrink),
        ("How do belts work?",
         "Every day you reach your goal is a goal day. Belts go from white to black, then ten Dan ranks. Earned ranks are never lost. After the 10th Dan you can choose to start again with a prestige seal."),
        ("How far back can I log a drink?",
         "Today and the two days before. Older days can't be filled in, so goal days and belts stay fair."),
        ("What goes into the Quick log?",
         "Up to 12 drinks for one-tap logging. New drinks ask whether to add them. Settings › Presets lets you choose which ones show up; all others are still found with search when you tap +."),
        ("I tapped a drink by accident.",
         "Tap Undo in the message that appears, or swipe the drink left under \"Today's drinks\" to delete it. Apple Health is updated too."),
        ("What's written to Apple Health?",
         "Water (with each drink's percentage), caffeine, alcohol and known nutrients, after the delay you chose. Edits and deletes are updated in Health. The app only changes entries it wrote itself."),
        ("What if I get a new phone or delete the app?",
         "Your drinks are stored only on this phone. Use Settings › Backup to export a file (for example to Files or iCloud Drive) and import it on the new phone. Deleting the app deletes its data; entries already in Apple Health stay there."),
        ("Is my data shared?",
         "No account, no server. Data stays on your phone and, if you allow it, in Apple Health. Only a barcode (for scanning) and a location rounded to about 1 km (for the weather, if turned on) are sent to look things up."),
    ]
}

struct FAQView: View {
    var body: some View {
        List {
            ForEach(FAQ.items, id: \.question) { item in
                DisclosureGroup {
                    Text(item.answer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } label: {
                    Text(item.question)
                }
            }
        }
        .dojoBackground()
        .navigationTitle("FAQ")
    }
}
