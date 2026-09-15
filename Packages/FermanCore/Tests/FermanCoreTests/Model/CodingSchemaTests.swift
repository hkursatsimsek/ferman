import Foundation
import Testing

@testable import FermanCore

/// Pins the JSON shape of every encoded type. Saved battles, golden files, arena records and duel data all depend on
/// it, so a failure here means a format change that needs a version bump, not a test update.
@Suite("Coding schema")
struct CodingSchemaTests {
    static let conditions: [(Condition, String)] = [
        (.enemyWithin(cells: 3), #"{"cells":3,"kind":"enemyWithin"}"#),
        (.healthBelow(percent: 35), #"{"kind":"healthBelow","percent":35}"#),
        (.allyCountBelow(count: 2), #"{"count":2,"kind":"allyCountBelow"}"#),
        (.isFlanked, #"{"kind":"isFlanked"}"#),
        (.targetInRange("suvari"), #"{"kind":"targetInRange","unitType":"suvari"}"#),
        (.timeAfter(seconds: 20), #"{"kind":"timeAfter","seconds":20}"#),
        (.nearestEnemyType("okcu"), #"{"kind":"nearestEnemyType","unitType":"okcu"}"#),
        (.moraleBelow(percent: 40), #"{"kind":"moraleBelow","percent":40}"#),
        (.terrainIs(.forest), #"{"kind":"terrainIs","terrain":"forest"}"#),
        (.commanderDead, #"{"kind":"commanderDead"}"#),
        (.enemyDensityAbove(count: 4), #"{"count":4,"kind":"enemyDensityAbove"}"#),
        (.always, #"{"kind":"always"}"#),
    ]

    static let actions: [(Action, String)] = [
        (.advance, #"{"kind":"advance"}"#),
        (.retreat, #"{"kind":"retreat"}"#),
        (.hold, #"{"kind":"hold"}"#),
        (.focusFire("okcu"), #"{"kind":"focusFire","unitType":"okcu"}"#),
        (.focusFire(nil), #"{"kind":"focusFire"}"#),
        (.flankLeft, #"{"kind":"flankLeft"}"#),
        (.flankRight, #"{"kind":"flankRight"}"#),
        (.regroup, #"{"kind":"regroup"}"#),
        (.useAbility, #"{"kind":"useAbility"}"#),
        (.takeCover, #"{"kind":"takeCover"}"#),
        (.guardCommander, #"{"kind":"guardCommander"}"#),
        (.scatter, #"{"kind":"scatter"}"#),
    ]

    static let events: [(BattleEvent, String)] = [
        (
            BattleEvent(tick: 0, kind: .spawn(UnitID(rawValue: 1), "okcu", .player, FixedVector2(x: .half, y: 2))),
            #"{"kind":"spawn","position":{"x":32768,"y":131072},"team":"player","tick":0,"unit":1,"unitType":"okcu"}"#
        ),
        (
            BattleEvent(tick: 3, kind: .move(UnitID(rawValue: 1), FixedVector2(x: 1, y: -1))),
            #"{"kind":"move","position":{"x":65536,"y":-65536},"tick":3,"unit":1}"#
        ),
        (
            BattleEvent(tick: 6, kind: .ruleActivated(UnitID(rawValue: 2), ruleIndex: 1)),
            #"{"kind":"ruleActivated","ruleIndex":1,"tick":6,"unit":2}"#
        ),
        (
            BattleEvent(tick: 40, kind: .attack(UnitID(rawValue: 2), target: UnitID(rawValue: 9), damage: 7)),
            #"{"damage":7,"kind":"attack","target":9,"tick":40,"unit":2}"#
        ),
        (
            BattleEvent(tick: 41, kind: .abilityUsed(UnitID(rawValue: 3), .volley)),
            #"{"ability":"volley","kind":"abilityUsed","tick":41,"unit":3}"#
        ),
        (BattleEvent(tick: 50, kind: .death(UnitID(rawValue: 9))), #"{"kind":"death","tick":50,"unit":9}"#),
        (
            BattleEvent(tick: 51, kind: .moraleBroken(UnitID(rawValue: 4))),
            #"{"kind":"moraleBroken","tick":51,"unit":4}"#
        ),
        (
            BattleEvent(tick: 141, kind: .moraleRecovered(UnitID(rawValue: 4))),
            #"{"kind":"moraleRecovered","tick":141,"unit":4}"#
        ),
        (
            BattleEvent(tick: 1_800, kind: .battleEnded(.draw, .timeLimit)),
            #"{"kind":"battleEnded","outcome":"draw","reason":"timeLimit","tick":1800}"#
        ),
    ]

    @Test(arguments: conditions)
    func conditionEncoding(condition: Condition, json: String) throws {
        #expect(try JSON.encode(condition) == json)
        #expect(try JSON.decode(Condition.self, from: json) == condition)
    }

    @Test func conditionSamplesCoverEveryKind() {
        #expect(Set(Self.conditions.map(\.0.kind)) == Set(ConditionKind.allCases))
        #expect(ConditionKind.allCases.count == 12)
    }

    @Test(arguments: actions)
    func actionEncoding(action: Action, json: String) throws {
        #expect(try JSON.encode(action) == json)
        #expect(try JSON.decode(Action.self, from: json) == action)
    }

    @Test func actionSamplesCoverEveryKind() {
        #expect(Set(Self.actions.map(\.0.kind)) == Set(ActionKind.allCases))
        #expect(ActionKind.allCases.count == 11)
    }

    @Test(arguments: events)
    func eventEncoding(event: BattleEvent, json: String) throws {
        #expect(try JSON.encode(event) == json)
        #expect(try JSON.decode(BattleEvent.self, from: json) == event)
    }

    @Test func scalarTypesEncodeAsBareValues() throws {
        #expect(try JSON.encode([UnitTypeID("okcu")]) == #"["okcu"]"#)
        #expect(try JSON.encode([UnitID(rawValue: 7)]) == "[7]")
        #expect(try JSON.encode([Team.player]) == #"["player"]"#)
        #expect(try JSON.encode([Terrain.hill]) == #"["hill"]"#)
        #expect(try JSON.encode([Ability.shieldWall]) == #"["shieldWall"]"#)
        #expect(try JSON.encode([BattleObjective.holdLine]) == #"["holdLine"]"#)
        #expect(try JSON.encode([BattleOutcome.playerWin]) == #"["playerWin"]"#)
        #expect(try JSON.encode([EndReason.rout]) == #"["rout"]"#)
    }

    @Test(arguments: [
        #"{"kind":"charge"}"#,
        #"{"kind":"enemyWithin"}"#,
        #"{"kind":"terrainIs","terrain":"lava"}"#,
        #"{"cells":3}"#,
    ])
    func malformedConditionsFailToDecode(json: String) {
        #expect(throws: DecodingError.self) {
            try JSON.decode(Condition.self, from: json)
        }
    }

    @Test(arguments: [
        #"{"kind":"attack","tick":1,"unit":2}"#,
        #"{"kind":"teleport","tick":1,"unit":2}"#,
        #"{"kind":"death","unit":2}"#,
    ])
    func malformedEventsFailToDecode(json: String) {
        #expect(throws: DecodingError.self) {
            try JSON.decode(BattleEvent.self, from: json)
        }
    }

    @Test func tuningFieldNamesArePinned() throws {
        let expected =
            #"{"allyDeathMoralePenalty":10,"allyDeathMoraleRadiusCells":3,"checksumIntervalTicks":30,"#
            + #""commanderDeathMoralePenalty":25,"counterDamagePercent":150,"coverRangedDamageReductionPercent":30,"#
            + #""coverSearchRadiusCells":5,"decisionIntervalTicks":6,"flankOffsetCells":4,"flankedMemoryTicks":30,"#
            + #""flankedMoralePenalty":5,"flowFieldIntervalTicks":15,"focusFireExtraRangeCells":2,"#
            + #""guardCommanderDistanceCells":2,"minimumCommitTicks":15,"moraleBreakPercent":20,"#
            + #""moraleBrokenTicks":90,"moraleRecoveredPercent":35,"moraleRecoveryEnemyFreeRadiusCells":4,"#
            + #""moraleRecoveryPerSecond":1,"moveSampleIntervalTicks":3,"proximityRadiusCells":3,"#
            + #""regroupRadiusCells":6,"spatialBucketCells":2,"#
            + #""terrainMovementCost":{"forest":30,"hill":20,"open":10,"rubble":20}}"#
        #expect(try JSON.encode(SimulationTuning.standard) == expected)
    }

    @Test func handwrittenConfigDecodes() throws {
        let json = #"""
            {
              "simulationVersion": 1,
              "seed": 18446744073709551615,
              "maxTicks": 900,
              "objective": "holdLine",
              "map": {
                "terrain": ["..F", ".WH"],
                "zones":   ["P.E", "P.."]
              },
              "unitCatalog": [
                { "id": "okcu", "cost": 30, "maxHP": 70, "speedMilliCellsPerSecond": 1000, "rangeMilliCells": 6000,
                  "damage": 10, "attackIntervalTicks": 36, "armor": 0, "moraleMax": 90,
                  "counters": ["mizrakci"], "ability": "volley" }
              ],
              "tuning": {
                "flowFieldIntervalTicks": 15, "terrainMovementCost": { "open": 10, "forest": 30, "hill": 20, "rubble": 20 },
                "decisionIntervalTicks": 6, "minimumCommitTicks": 15, "proximityRadiusCells": 3, "flankedMemoryTicks": 30,
                "counterDamagePercent": 150, "coverRangedDamageReductionPercent": 30, "focusFireExtraRangeCells": 2,
                "flankOffsetCells": 4, "regroupRadiusCells": 6, "coverSearchRadiusCells": 5,
                "guardCommanderDistanceCells": 2, "allyDeathMoraleRadiusCells": 3, "allyDeathMoralePenalty": 10,
                "commanderDeathMoralePenalty": 25, "flankedMoralePenalty": 5, "moraleRecoveryPerSecond": 1,
                "moraleRecoveryEnemyFreeRadiusCells": 4, "moraleBreakPercent": 20, "moraleBrokenTicks": 90,
                "moraleRecoveredPercent": 35, "moveSampleIntervalTicks": 3, "checksumIntervalTicks": 30,
                "spatialBucketCells": 2
              },
              "player": {
                "placements": [{ "type": "okcu", "cell": 0, "isCommander": true }],
                "programs": [{
                  "unitType": "okcu",
                  "rules": [
                    { "condition": { "kind": "enemyWithin", "cells": 4 }, "action": { "kind": "retreat" } },
                    { "condition": { "kind": "always" }, "action": { "kind": "focusFire" } }
                  ]
                }]
              },
              "enemy": {
                "placements": [{ "type": "okcu", "cell": 2, "isCommander": false }],
                "programs": [{ "unitType": "okcu", "rules": [{ "condition": { "kind": "always" }, "action": { "kind": "advance" } }] }]
              },
              "constraints": { "maxRules": 3, "availableConditions": ["enemyWithin", "always"], "availableActions": ["retreat", "advance", "focusFire"] }
            }
            """#
        let config = try JSON.decode(BattleConfig.self, from: json)

        #expect(config.seed == .max)
        #expect(config.maxTicks == 900)
        #expect(config.objective == .holdLine)
        #expect(config.tuning == .standard)
        #expect(config.map.width == 3 && config.map.height == 2)
        #expect(config.map.terrain == [.open, .open, .forest, .open, .water, .hill])
        #expect(config.map.playerZone == [0, 3] && config.map.enemyZone == [2])
        #expect(config.player.placements == [UnitPlacement(type: "okcu", cell: 0, isCommander: true)])
        #expect(
            config.player.program(for: "okcu")?.rules == [
                Rule(condition: .enemyWithin(cells: 4), action: .retreat),
                Rule(condition: .always, action: .focusFire(nil)),
            ]
        )
        #expect(config.constraints.availableConditions == [.enemyWithin, .always])
        #expect(try JSON.roundTrip(config) == config)
    }

    @Test func fixtureConfigRoundTrips() throws {
        let config = try Fixtures.config(seed: 0x8000_0000_0000_0001)
        #expect(try JSON.roundTrip(config) == config)
    }

    @Test func resultRoundTrips() throws {
        let result = BattleResult(
            outcome: .enemyWin,
            endReason: .rout,
            tickCount: 912,
            events: Self.events.map(\.0),
            ruleFireCounts: [
                RuleFireCounts(team: .player, unitType: "okcu", counts: [3, 0]),
                RuleFireCounts(team: .enemy, unitType: "suvari", counts: [1, 5]),
            ],
            survivorsPlayer: 0,
            survivorsEnemy: 4,
            checksum: .max
        )
        #expect(try JSON.roundTrip(result) == result)
    }
}
