import SwiftData
import SwiftUI
import VisionKit

/// Scan a barcode (or type it), look it up, then review the drink before saving.
/// Products the user saved before are found offline and win over online data.
struct ScanView: View {
    /// Called with the pre-filled draft to open the editor for review.
    var onResult: (DrinkDraft) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var typedCode = ""
    @State private var found = false
    @AppStorage(SettingsKey.companionEnabled) private var companionEnabled = SettingsDefault.companionEnabled
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0
    @State private var state: LookupState = .idle
    @FocusState private var fieldFocused: Bool

    private enum LookupState: Equatable {
        case idle
        case looking(String)
        case failed(String)
    }

    private var cameraAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Group {
                    if cameraAvailable {
                        BarcodeScanner { code in lookUp(code) }
                            .clipShape(.rect(cornerRadius: 20))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20).stroke(Dojo.ink.opacity(0.3), lineWidth: 1)
                            }
                    } else {
                        ContentUnavailableView(
                            "Camera scanning not available",
                            systemImage: "barcode.viewfinder",
                            description: Text("This device can't scan barcodes with the camera. Type the number under the barcode instead.")
                        )
                    }
                }
                .frame(maxHeight: 340)

                HStack {
                    TextField("Barcode number", text: $typedCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                    Button("Look up") { lookUp(typedCode) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!OpenFoodFacts.isValidBarcode(typedCode) || isLooking)
                }

                if companionEnabled {
                    ScanCompanion(phase: companionPhase, belt: Belt.belt(forGoalDays: max(bestGoalDays - prestigeBase, 0)))
                        .frame(height: 70)
                }

                switch state {
                case .idle:
                    VStack(spacing: 8) {
                        Label("Needs an internet connection (Wi-Fi or mobile data)", systemImage: "wifi")
                            .font(.footnote.weight(.semibold))
                        Text("Point the camera at a drink's barcode. Product data comes from Open Food Facts. Drinks you saved before also work offline.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                case .looking(let code):
                    ProgressView("Looking up \(code)…")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding()
            .background(Dojo.paper)
            .navigationTitle("Scan a drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isLooking: Bool {
        if case .looking = state { return true }
        return false
    }

    private func lookUp(_ code: String) {
        guard !isLooking else { return }
        guard OpenFoodFacts.isValidBarcode(code) else {
            state = .failed(ProductLookup.LookupError.invalidBarcode.localizedDescription)
            return
        }
        fieldFocused = false

        // A product the user saved before: use it, no internet needed.
        let barcode: String? = code
        if let saved = try? context.fetch(FetchDescriptor<DrinkPreset>(predicate: #Predicate { $0.barcode == barcode })).first {
            finish(DrinkDraft(scannedPreset: saved))
            return
        }

        state = .looking(code)
        Task {
            do {
                if let product = try await ProductLookup.fetch(barcode: code) {
                    finish(DrinkDraft(scanned: product))
                } else {
                    finish(DrinkDraft(unknownBarcode: code))
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private var companionPhase: ScanCompanion.Phase {
        if found { return .found }
        switch state {
        case .idle, .looking: return .searching
        case .failed: return .confused
        }
    }

    private func finish(_ draft: DrinkDraft) {
        // A short thumbs-up before the review opens.
        found = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(companionEnabled ? 500 : 0))
            finishNow(draft)
        }
    }

    private func finishNow(_ draft: DrinkDraft) {
        state = .idle
        dismiss()
        onResult(draft)
    }
}

/// The ninja drop on the scan screen: looks around while searching, gives a
/// thumbs-up when found, shrugs when nothing was found or there's no internet.
struct ScanCompanion: View {
    enum Phase { case searching, found, confused }
    var phase: Phase
    var belt: Belt
    @State private var look = false

    var body: some View {
        HStack(spacing: 14) {
            NinjaDrop(progress: phase == .found ? 1 : 0.4, belt: belt, mood: .calm)
                .frame(width: 44, height: 58)
                .rotationEffect(.degrees(phase == .searching ? (look ? 10 : -10) : (phase == .confused ? -12 : 0)), anchor: .bottom)
                .animation(phase == .searching ? .easeInOut(duration: 1.2).repeatForever() : .spring, value: look)
                .animation(.spring, value: phase)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: symbol)
                        .font(.title3.bold())
                        .foregroundStyle(color)
                        .offset(x: 18, y: -6)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.trailing, 18)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { look = true }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch phase {
        case .searching: "magnifyingglass"
        case .found: "hand.thumbsup.fill"
        case .confused: "questionmark"
        }
    }

    private var color: Color {
        switch phase {
        case .searching: Dojo.ink
        case .found: .green
        case .confused: .orange
        }
    }

    private var text: String {
        switch phase {
        case .searching: "Looking for a barcode…"
        case .found: "Found it!"
        case .confused: "Hmm, I couldn't find that one."
        }
    }
}

/// VisionKit's live barcode scanner.
/// https://developer.apple.com/documentation/visionkit/datascannerviewcontroller
struct BarcodeScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        private var lastCode: String?

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, code != lastCode {
                    lastCode = code
                    onScan(code)
                }
            }
        }
    }
}
