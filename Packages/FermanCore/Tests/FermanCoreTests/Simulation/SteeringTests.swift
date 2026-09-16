import Testing

@testable import FermanCore

@Suite("Steering")
struct SteeringTests {
    private static func openMap() throws -> BattleMap {
        try BattleMap(terrainRows: ["....."], zoneRows: ["P...E"])
    }

    // MARK: - Intent and terrain speed

    @Test func aPureSeekMovesTheExactComputedDistanceOnOpenTerrain() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2), y: .half), velocity: .zero)
        let inputs = SteeringInputs(intent: .seek(FixedVector2(x: .one, y: .zero)), neighbors: [], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: .standard)

        let expectedSpeed = Fixed(numerator: 1_000, denominator: 1_000) * Fixed(numerator: 10, denominator: 10)
        let expectedDisplacement = expectedSpeed / BattleConfig.ticksPerSecond
        #expect(result.position == FixedVector2(x: previous.position.x + expectedDisplacement, y: previous.position.y))
        #expect(result.velocity == FixedVector2(x: expectedDisplacement * BattleConfig.ticksPerSecond, y: .zero))
    }

    @Test func fleeMovesOppositeTheGivenHeading() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2), y: .half), velocity: .zero)
        let inputs = SteeringInputs(intent: .flee(FixedVector2(x: .one, y: .zero)), neighbors: [], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: .standard)

        #expect(result.position.x < previous.position.x)
        #expect(result.position.y == previous.position.y)
    }

    @Test func holdWithNoOtherForceDoesNotMove() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2), y: .half), velocity: .zero)
        let inputs = SteeringInputs(intent: .hold, neighbors: [], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: .standard)

        #expect(result.position == previous.position)
        #expect(result.velocity == .zero)
    }

    @Test func forestSlowsAUnitInProportionToItsMovementCost() throws {
        let openMap = try Self.openMap()
        let forestMap = try BattleMap(terrainRows: ["F...."], zoneRows: ["P...E"])
        let previous = UnitKinematics(position: FixedVector2(x: .half, y: .half), velocity: .zero)
        let inputs = SteeringInputs(intent: .seek(FixedVector2(x: .one, y: .zero)), neighbors: [], flowDirection: .zero)

        let onOpen = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: openMap, tuning: .standard)
        let onForest = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: forestMap, tuning: .standard)

        let expectedForestSpeed =
            Fixed(numerator: 1_000, denominator: 1_000) * Fixed(numerator: 10, denominator: 30)
        let expectedForestDisplacement = expectedForestSpeed / BattleConfig.ticksPerSecond
        #expect(onForest.position.x == previous.position.x + expectedForestDisplacement)
        #expect(onForest.position.x < onOpen.position.x)
    }

    // MARK: - Separation, alignment, cohesion, flow (each isolated by zeroing the other weights)

    @Test func separationPushesAwayFromACrowdingNeighbor() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2) + .half, y: .half), velocity: .zero)
        let crowdingNeighbor = SteeringNeighbor(
            position: FixedVector2(x: previous.position.x + .half, y: .half), velocity: .zero)
        var tuning = SimulationTuning.standard
        tuning.steeringIntentWeightPercent = 0
        tuning.steeringAlignmentWeightPercent = 0
        tuning.steeringCohesionWeightPercent = 0
        tuning.steeringFlowWeightPercent = 0
        let inputs = SteeringInputs(intent: .hold, neighbors: [crowdingNeighbor], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: tuning)

        #expect(result.position.x < previous.position.x)
        #expect(result.position.y == previous.position.y)
    }

    @Test func aDistantNeighborDoesNotContributeSeparation() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2), y: .half), velocity: .zero)
        let farNeighbor = SteeringNeighbor(position: FixedVector2(x: Fixed(4), y: .half), velocity: .zero)
        var tuning = SimulationTuning.standard
        tuning.steeringIntentWeightPercent = 0
        tuning.steeringAlignmentWeightPercent = 0
        tuning.steeringCohesionWeightPercent = 0
        tuning.steeringFlowWeightPercent = 0
        let inputs = SteeringInputs(intent: .hold, neighbors: [farNeighbor], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: tuning)

        #expect(result.position == previous.position)
    }

    @Test func alignmentTurnsTowardTheNeighborsAverageHeading() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2), y: .half), velocity: .zero)
        let neighbor = SteeringNeighbor(position: previous.position, velocity: FixedVector2(x: .zero, y: .one))
        var tuning = SimulationTuning.standard
        tuning.steeringIntentWeightPercent = 0
        tuning.steeringSeparationWeightPercent = 0
        tuning.steeringCohesionWeightPercent = 0
        tuning.steeringFlowWeightPercent = 0
        let inputs = SteeringInputs(intent: .hold, neighbors: [neighbor], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: tuning)

        #expect(result.position.x == previous.position.x)
        #expect(result.position.y > previous.position.y)
    }

    @Test func cohesionPullsTowardTheNeighborCentroid() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2), y: .half), velocity: .zero)
        let neighbor = SteeringNeighbor(position: FixedVector2(x: Fixed(2), y: .half + .one), velocity: .zero)
        var tuning = SimulationTuning.standard
        tuning.steeringIntentWeightPercent = 0
        tuning.steeringSeparationWeightPercent = 0
        tuning.steeringAlignmentWeightPercent = 0
        tuning.steeringFlowWeightPercent = 0
        let inputs = SteeringInputs(intent: .hold, neighbors: [neighbor], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: tuning)

        #expect(result.position.x == previous.position.x)
        #expect(result.position.y > previous.position.y)
    }

    @Test func flowFollowingMovesAlongTheFieldDirection() throws {
        let map = try Self.openMap()
        let previous = UnitKinematics(position: FixedVector2(x: Fixed(2), y: .half), velocity: .zero)
        var tuning = SimulationTuning.standard
        tuning.steeringIntentWeightPercent = 0
        tuning.steeringSeparationWeightPercent = 0
        tuning.steeringAlignmentWeightPercent = 0
        tuning.steeringCohesionWeightPercent = 0
        let inputs = SteeringInputs(intent: .hold, neighbors: [], flowDirection: FixedVector2(x: -.one, y: .zero))

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 1_000, inputs: inputs, map: map, tuning: tuning)

        #expect(result.position.x < previous.position.x)
        #expect(result.position.y == previous.position.y)
    }

    // MARK: - Collision (F0.8 acceptance: no unit ever ends up in water)

    @Test func aBlockedMoveLeavesTheUnitInPlace() throws {
        let map = try BattleMap(terrainRows: ["..", ".."], zoneRows: ["P.", ".E"])
        // The unit sits in the map's far corner; a southeast seek has nowhere to go on either axis.
        let previous = UnitKinematics(
            position: FixedVector2(
                x: Fixed(numerator: 199, denominator: 100), y: Fixed(numerator: 199, denominator: 100)),
            velocity: .zero)
        let inputs = SteeringInputs(
            intent: .seek(FixedVector2(x: .one, y: .one)), neighbors: [], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 8_000, inputs: inputs, map: map, tuning: .standard)

        #expect(result.position == previous.position)
        #expect(result.velocity == .zero)
    }

    @Test func aDiagonalMoveBlockedOnOneAxisSlidesAlongTheOther() throws {
        let map = try BattleMap(terrainRows: ["...", ".W.", "..."], zoneRows: ["P..", "...", "..E"])
        // Starting just west of the water cell, a northeast seek can't cross into water on the x-axis but can
        // still slide north on the y-axis.
        let previous = UnitKinematics(
            position: FixedVector2(x: Fixed(numerator: 99, denominator: 100), y: Fixed(1) + .half), velocity: .zero)
        let inputs = SteeringInputs(
            intent: .seek(FixedVector2(x: .one, y: -.one)), neighbors: [], flowDirection: .zero)

        let result = Steering.step(
            previous: previous, speedMilliCellsPerSecond: 2_000, inputs: inputs, map: map, tuning: .standard)

        #expect(result.position.x == previous.position.x)
        #expect(result.position.y < previous.position.y)
        let cell = map.cellIndex(column: result.position.x.roundedDown(), row: result.position.y.roundedDown())
        #expect(cell != nil)
    }

    @Test func noUnitEverEndsOnWaterOrOffTheMap() throws {
        let map = try BattleMap(
            terrainRows: ["W.W.W", ".W.W.", "W.W.W", ".W.W.", "W.W.W"],
            zoneRows: [".P...", ".....", ".....", ".....", "...E."]
        )
        let passableCells = map.terrain.indices.filter { map.terrain[$0].isPassable }
        var generator = DeterministicRNG(seed: 909)

        for _ in 0..<300 {
            let startCell = passableCells[generator.int(in: 0...(passableCells.count - 1))]
            let jitter = FixedVector2(
                x: Fixed(numerator: generator.int(in: -40...40), denominator: 100),
                y: Fixed(numerator: generator.int(in: -40...40), denominator: 100)
            )
            let previous = UnitKinematics(position: map.center(ofCell: startCell) + jitter, velocity: .zero)
            let intent = SteeringIntent.seek(
                FixedVector2(x: Fixed(generator.int(in: -3...3)), y: Fixed(generator.int(in: -3...3))))
            let inputs = SteeringInputs(intent: intent, neighbors: [], flowDirection: .zero)

            let result = Steering.step(
                previous: previous, speedMilliCellsPerSecond: generator.int(in: 200...3_000), inputs: inputs,
                map: map, tuning: .standard)

            let cell = map.cellIndex(column: result.position.x.roundedDown(), row: result.position.y.roundedDown())
            #expect(cell != nil, "unit left the map at \(result.position)")
            if let cell {
                #expect(map.terrain[cell].isPassable, "unit ended on \(map.terrain[cell]) at \(result.position)")
            }
        }
    }

    // MARK: - Order independence (D10, F0.8 acceptance)

    @Test func resultsDoNotDependOnProcessingOrder() throws {
        let dimension = 10
        let terrainRows = Array(repeating: String(repeating: ".", count: dimension), count: dimension)
        var zoneRows = Array(repeating: String(repeating: ".", count: dimension), count: dimension)
        zoneRows[0] = "P" + String(repeating: ".", count: dimension - 2) + "E"
        let map = try BattleMap(terrainRows: terrainRows, zoneRows: zoneRows)

        var generator = DeterministicRNG(seed: 55)
        let unitCount = 24
        let previousStates = (0..<unitCount).map { _ in
            UnitKinematics(
                position: FixedVector2(
                    x: Fixed(generator.int(in: 0...(dimension - 1))) + generator.fixedUnit(),
                    y: Fixed(generator.int(in: 0...(dimension - 1))) + generator.fixedUnit()
                ),
                velocity: FixedVector2(x: Fixed(generator.int(in: -1...1)), y: Fixed(generator.int(in: -1...1)))
            )
        }
        let inputsList = (0..<unitCount).map { index -> SteeringInputs in
            let neighbors = (0..<unitCount)
                .filter { $0 != index }
                .map { SteeringNeighbor(position: previousStates[$0].position, velocity: previousStates[$0].velocity) }
            let intent = FixedVector2(x: Fixed(generator.int(in: -1...1)), y: Fixed(generator.int(in: -1...1)))
            return SteeringInputs(intent: .seek(intent), neighbors: neighbors, flowDirection: .zero)
        }

        func run(order: [Int]) -> [UnitKinematics] {
            var results: [(index: Int, kinematics: UnitKinematics)] = []
            for index in order {
                let kinematics = Steering.step(
                    previous: previousStates[index], speedMilliCellsPerSecond: 1_000, inputs: inputsList[index],
                    map: map, tuning: .standard)
                results.append((index, kinematics))
            }
            return results.sorted { $0.index < $1.index }.map(\.kinematics)
        }

        let forward = run(order: Array(0..<unitCount))
        let reversed = run(order: Array((0..<unitCount).reversed()))
        let interleaved = run(
            order: stride(from: 0, to: unitCount, by: 2).map { $0 } + stride(from: 1, to: unitCount, by: 2).map { $0 })

        #expect(reversed == forward)
        #expect(interleaved == forward)
    }
}
