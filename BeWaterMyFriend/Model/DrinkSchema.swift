import SwiftData

// Version numbers for the database, so its structure can change safely later.
//
// Adding an optional field needs nothing here. A bigger change (renaming a field,
// changing a type, making one required) does:
// 1. Freeze the current structure: copy the models into `DrinkSchemaV1` as nested
//    types, because `models` below points at the live ones.
// 2. Add `DrinkSchemaV2`, list it in `schemas`, and add a stage that says how to
//    convert the old data.
// 3. Save a new sample database for `DatabaseUpgradeTests`.
//
// Apple documentation:
// https://developer.apple.com/documentation/swiftdata/versionedschema
// https://developer.apple.com/documentation/swiftdata/schemamigrationplan

/// The structure as of 31 Oct 2026: the same as before versions existed, so
/// existing databases simply open as Version 1. Nothing gets converted.
nonisolated enum DrinkSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [DrinkEntry.self, DrinkPreset.self] }
}

nonisolated enum DrinkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [DrinkSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum DrinkDatabase {
    /// `groupContainer: .none` is essential: with an App Group in the entitlements,
    /// SwiftData would otherwise silently open a new, empty database in the shared
    /// folder, and the user's drinks would look gone (found 31 Oct, before release).
    static let storeConfiguration = ModelConfiguration(groupContainer: .none)

    static func makeContainer(configuration: ModelConfiguration = storeConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: DrinkSchemaV1.self), migrationPlan: DrinkMigrationPlan.self,
                           configurations: configuration)
    }
}
