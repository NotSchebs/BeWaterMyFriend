import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Export a backup file and import it again (new phone, reinstall).
struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        Section {
            Button {
                do {
                    exportDocument = BackupDocument(data: try Backup.encode(Backup.make(context: context)))
                    showExporter = true
                } catch {
                    message = "Couldn't create the backup: \(error.localizedDescription)"
                }
            } label: {
                Label("Export backup", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("Import backup", systemImage: "square.and.arrow.down")
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Your drinks live only on this phone. Export a backup (e.g. to Files or iCloud Drive) to move to a new phone or restore after reinstalling. Importing adds what's missing and never deletes anything.")
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: Backup.fileName()) { result in
            if case .success = result { message = "Backup saved." }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let file = try Backup.decode(Data(contentsOf: url))
                let r = try Backup.restore(file, into: context)
                message = "Imported \(Format.count(r.addedDrinks, "drink", "drinks")) and \(Format.count(r.addedPresets, "preset", "presets"))"
                    + (r.skippedDrinks > 0 ? " (\(r.skippedDrinks) already here)." : ".")
            } catch {
                message = "That file isn't a BeWaterMyFriend backup."
            }
        }
    }
}

/// `nonisolated`: SwiftUI reads and writes documents on a background thread.
/// As main-actor code (the app's default) that could stop the app, like the
/// colour crash on 29 Oct. It only holds `Data`, so it's safe anywhere.
nonisolated struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if DEBUG
/// Test mode (only in builds from Xcode): jump through belts, Dan ranks and
/// prestige without real goal days, then restore the real progress.
struct DojoTestSection: View {
    @AppStorage(SettingsKey.dojoBestGoalDays) private var bestGoalDays = 0
    @AppStorage(SettingsKey.dojoBelt) private var awardedBelt = 0
    @AppStorage(SettingsKey.prestigeLevel) private var prestigeLevel = 0
    @AppStorage(SettingsKey.prestigeBaseGoalDays) private var prestigeBase = 0
    @AppStorage("debugSnapshot") private var snapshot = ""

    var body: some View {
        Section {
            LabeledContent("Goal days counted", value: "\(bestGoalDays - prestigeBase)")
            Button("+1 goal day") { change { bestGoalDays += 1 } }
            Button("+10 goal days") { change { bestGoalDays += 10 } }
            Button("Jump to black belt (100)") { change { bestGoalDays = prestigeBase + 100 } }
            Button("Jump to 10th Dan (1,000)") { change { bestGoalDays = prestigeBase + 1000 } }
            if !snapshot.isEmpty {
                Button("Restore my real progress", role: .destructive) { restore() }
            }
        } header: {
            Text("Dojo test mode")
        } footer: {
            Text("Only in test builds from Xcode, never in a release. Your real progress is saved before the first change and can be restored.")
        }
    }

    private func change(_ action: () -> Void) {
        if snapshot.isEmpty {
            snapshot = [bestGoalDays, awardedBelt, prestigeLevel, prestigeBase].map(String.init).joined(separator: ",")
        }
        action()
    }

    private func restore() {
        let values = snapshot.split(separator: ",").compactMap { Int($0) }
        guard values.count == 4 else { return }
        bestGoalDays = values[0]
        awardedBelt = values[1]
        prestigeLevel = values[2]
        prestigeBase = values[3]
        snapshot = ""
    }
}
#endif
