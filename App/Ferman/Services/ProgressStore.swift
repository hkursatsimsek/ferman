import FermanCore
import Foundation
import SwiftData

/// Schema v1 (D14). Models are nested inside the versioned schema, as Apple's own migration
/// samples do, so a later `FermanSchemaV2` can define its own `LevelProgress` without colliding —
/// `MigrationStage.custom` closures need both versions addressable at once.
///
/// CloudKit-compatible from the start even though sync itself doesn't land until F4.2: every
/// property below is either optional or has a default, nothing uses `@Attribute(.unique)`, and
/// there are no relationships between the three models.
enum FermanSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LevelProgress.self, SavedOrderSet.self, BattleRecord.self]
    }

    /// The best result reached on one level and the program that earned it, so a mirrored level
    /// (F3.7) can replay a win without re-deriving it.
    ///
    /// `levelID` mirrors `CampaignFront.id` for now — `FermanContent` has no level type of its own
    /// until F1.12 gives one a content-defined identifier; this field's type moves with it then.
    @Model
    final class LevelProgress {
        var levelID: Int = 0
        var bestOutcome: BattleOutcome?
        var attempts: Int = 0
        @Attribute(.codable) var winningArmy: [UnitPlacement]?
        @Attribute(.codable) var winningPrograms: [RuleProgram]?
        /// The enemy `TeamSetup` from the most recent attempt, win or lose — today's stand-in for
        /// the `EnemyArmyPlan` the strategist (F3.6) will eventually produce and store here instead.
        @Attribute(.codable) var lastEnemyPlan: TeamSetup?

        init(levelID: Int) {
            self.levelID = levelID
        }
    }

    /// A named, reusable composition + program set — the future Emir Kütüphanesi (F4.8). Persisted
    /// from F1.11 on even though no screen writes to it yet, the same order `FermanAI` (F1.6) landed
    /// before `RuleEditor` (F1.7) consumed it.
    @Model
    final class SavedOrderSet {
        var name: String = ""
        var tag: String?
        @Attribute(.codable) var army: [UnitPlacement] = []
        @Attribute(.codable) var programs: [RuleProgram] = []
        var usageCount: Int = 0
        var createdAt: Date = Date.distantPast

        init(name: String) {
            self.name = name
        }
    }

    /// One finished battle's config and outcome — enough to re-simulate and verify it (D14). Never
    /// the event stream or a replay; those are derived, not stored.
    @Model
    final class BattleRecord {
        var levelID: Int = 0
        @Attribute(.codable) var config: BattleConfig?
        var outcome: BattleOutcome?
        var checksum: UInt64 = 0
        var createdAt: Date = Date.distantPast

        init(levelID: Int) {
            self.levelID = levelID
        }
    }
}

/// Empty stages: v1 has no prior version to migrate from. Still declared as a real
/// `SchemaMigrationPlan` rather than a bare model list, per the skill's own guidance that a
/// migration schema is worth having even for the lightweight case.
enum FermanMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FermanSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// A `LevelProgress` reduced to a `Sendable` value. `ProgressStoring` never hands out `@Model`
/// reference types — those are tied to `ProgressStore`'s own `ModelContext` — so a caller can hold,
/// compare or pass one anywhere without touching SwiftData's actor rules.
struct LevelProgressSnapshot: Sendable, Hashable {
    let levelID: Int
    let bestOutcome: BattleOutcome?
    let attempts: Int
    let winningArmy: [UnitPlacement]?
    let winningPrograms: [RuleProgram]?
    let lastEnemyPlan: TeamSetup?
}

struct SavedOrderSetSnapshot: Sendable, Hashable, Identifiable {
    let id: PersistentIdentifier
    let name: String
    let tag: String?
    let army: [UnitPlacement]
    let programs: [RuleProgram]
    let usageCount: Int
    let createdAt: Date
}

struct BattleRecordSnapshot: Sendable, Hashable, Identifiable {
    let id: PersistentIdentifier
    let levelID: Int
    let config: BattleConfig
    let outcome: BattleOutcome
    let checksum: UInt64
    let createdAt: Date
}

/// What a feature model needs from persisted progress (D12's dependency-injection seam — see
/// `RuleEditorModel`'s `progress: any ProgressStoring`). `ProgressStore` is the only conformer that
/// touches SwiftData; a fake conformance for previews or tests only needs to return snapshots.
@MainActor
protocol ProgressStoring: AnyObject {
    func progress(forLevel levelID: Int) -> LevelProgressSnapshot?
    @discardableResult
    func recordBattle(levelID: Int, config: BattleConfig, result: BattleResult) throws -> LevelProgressSnapshot
    func battleRecords(forLevel levelID: Int) -> [BattleRecordSnapshot]

    func savedOrderSets() -> [SavedOrderSetSnapshot]
    @discardableResult
    func saveOrderSet(name: String, tag: String?, army: [UnitPlacement], programs: [RuleProgram]) throws
        -> SavedOrderSetSnapshot
    func markOrderSetUsed(_ id: PersistentIdentifier) throws
    func deleteOrderSet(_ id: PersistentIdentifier) throws
}

/// SwiftData-backed `ProgressStoring` (D14). `inMemory` exists so tests and previews never touch
/// disk — the F1.11 "bitti tanımı" is exactly that in-memory container coverage.
@MainActor
final class ProgressStore: ProgressStoring {
    let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(
            for: FermanSchemaV1.LevelProgress.self, FermanSchemaV1.SavedOrderSet.self,
            FermanSchemaV1.BattleRecord.self,
            migrationPlan: FermanMigrationPlan.self, configurations: configuration)
        context = ModelContext(container)
    }

    // MARK: - Level progress

    func progress(forLevel levelID: Int) -> LevelProgressSnapshot? {
        levelProgress(levelID).map(Self.snapshot)
    }

    /// Every attempt counts and refreshes `lastEnemyPlan`; `bestOutcome` only ever improves
    /// (§rank), and the winning army/programs are overwritten on each new win so they always
    /// reflect the player's current best approach rather than their first one.
    @discardableResult
    func recordBattle(levelID: Int, config: BattleConfig, result: BattleResult) throws -> LevelProgressSnapshot {
        let progress =
            levelProgress(levelID)
            ?? {
                let created = FermanSchemaV1.LevelProgress(levelID: levelID)
                context.insert(created)
                return created
            }()

        progress.attempts += 1
        progress.lastEnemyPlan = config.enemy
        if Self.rank(result.outcome) > Self.rank(progress.bestOutcome) {
            progress.bestOutcome = result.outcome
        }
        if result.outcome == .playerWin {
            progress.winningArmy = config.player.placements
            progress.winningPrograms = config.player.programs
        }

        let record = FermanSchemaV1.BattleRecord(levelID: levelID)
        record.config = config
        record.outcome = result.outcome
        record.checksum = result.checksum
        record.createdAt = Date()
        context.insert(record)

        try context.save()
        return Self.snapshot(progress)
    }

    func battleRecords(forLevel levelID: Int) -> [BattleRecordSnapshot] {
        let descriptor = FetchDescriptor<FermanSchemaV1.BattleRecord>(
            predicate: #Predicate { $0.levelID == levelID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(Self.snapshot)
    }

    // MARK: - Saved order sets

    func savedOrderSets() -> [SavedOrderSetSnapshot] {
        let descriptor = FetchDescriptor<FermanSchemaV1.SavedOrderSet>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map(Self.snapshot)
    }

    @discardableResult
    func saveOrderSet(name: String, tag: String?, army: [UnitPlacement], programs: [RuleProgram]) throws
        -> SavedOrderSetSnapshot
    {
        let set = FermanSchemaV1.SavedOrderSet(name: name)
        set.tag = tag
        set.army = army
        set.programs = programs
        set.createdAt = Date()
        context.insert(set)
        try context.save()
        return Self.snapshot(set)
    }

    func markOrderSetUsed(_ id: PersistentIdentifier) throws {
        guard let set = savedOrderSet(id) else { return }
        set.usageCount += 1
        try context.save()
    }

    func deleteOrderSet(_ id: PersistentIdentifier) throws {
        guard let set = savedOrderSet(id) else { return }
        context.delete(set)
        try context.save()
    }

    // MARK: - Lookups

    private func levelProgress(_ levelID: Int) -> FermanSchemaV1.LevelProgress? {
        var descriptor = FetchDescriptor<FermanSchemaV1.LevelProgress>(
            predicate: #Predicate { $0.levelID == levelID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// A predicate on `persistentModelID` rather than `model(for:)` or `registeredModel(for:)`: the
    /// former can hand back a not-yet-fetched fault for an id it doesn't recognize instead of `nil`,
    /// and the latter only finds models the context already has materialized — both wrong for "does
    /// this id still exist" after the snapshot that produced it has gone out of scope.
    private func savedOrderSet(_ id: PersistentIdentifier) -> FermanSchemaV1.SavedOrderSet? {
        var descriptor = FetchDescriptor<FermanSchemaV1.SavedOrderSet>(
            predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func rank(_ outcome: BattleOutcome?) -> Int {
        switch outcome {
        case nil: -1
        case .enemyWin: 0
        case .draw: 1
        case .playerWin: 2
        }
    }

    private static func snapshot(_ model: FermanSchemaV1.LevelProgress) -> LevelProgressSnapshot {
        LevelProgressSnapshot(
            levelID: model.levelID, bestOutcome: model.bestOutcome, attempts: model.attempts,
            winningArmy: model.winningArmy, winningPrograms: model.winningPrograms,
            lastEnemyPlan: model.lastEnemyPlan)
    }

    private static func snapshot(_ model: FermanSchemaV1.SavedOrderSet) -> SavedOrderSetSnapshot {
        SavedOrderSetSnapshot(
            id: model.persistentModelID, name: model.name, tag: model.tag, army: model.army,
            programs: model.programs, usageCount: model.usageCount, createdAt: model.createdAt)
    }

    /// `nil` for a record that was inserted but never reached `config`/`outcome` — can't happen
    /// through `recordBattle`, but a snapshot type shouldn't assert on data it didn't itself write.
    private static func snapshot(_ model: FermanSchemaV1.BattleRecord) -> BattleRecordSnapshot? {
        guard let config = model.config, let outcome = model.outcome else { return nil }
        return BattleRecordSnapshot(
            id: model.persistentModelID, levelID: model.levelID, config: config, outcome: outcome,
            checksum: model.checksum, createdAt: model.createdAt)
    }
}
