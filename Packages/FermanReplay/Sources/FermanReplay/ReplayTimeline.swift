import FermanCore

/// Turns a `BattleResult`'s flat event stream into random-access frames (D11).
///
/// Built once per result. A keyframe is kept every `keyframeInterval` ticks so
/// `frame(at:)` never folds more than one interval's worth of events, but the
/// answer is defined as "fold every event from tick 0" — a small
/// `keyframeInterval` only changes speed, never the result.
public struct ReplayTimeline: Sendable {
    public let result: BattleResult
    public let keyframeInterval: Int32

    private let keyframes: [ReplayFrame]
    private let unitIndex: UnitIndex

    public init(result: BattleResult, keyframeInterval: Int32 = 30) {
        precondition(keyframeInterval > 0, "keyframeInterval must be positive")
        self.result = result
        self.keyframeInterval = keyframeInterval
        self.unitIndex = UnitIndex(events: result.events)
        self.keyframes = Self.buildKeyframes(events: result.events, interval: keyframeInterval)
    }

    /// The state of the battlefield at `tick`, clamped to `[0, result.tickCount]`.
    public func frame(at tick: Int32) -> ReplayFrame {
        let tick = tick.clamped(to: 0...Int32(result.tickCount))
        let keyframeIndex = min(Int(tick / keyframeInterval), keyframes.count - 1)
        let keyframe = keyframes[keyframeIndex]

        var frame = keyframe
        for event in result.events where event.tick > keyframe.tick && event.tick <= tick {
            frame = frame.applying(event)
        }
        return frame.withTick(tick)
    }

    /// How many times each order had fired by `tick`, in the same shape as `result.ruleFireCounts`.
    public func fireCounts(upTo tick: Int32) -> [RuleFireCounts] {
        var counts: [ProgramKey: [Int]] = [:]
        for entry in result.ruleFireCounts {
            counts[ProgramKey(team: entry.team, unitType: entry.unitType)] = Array(
                repeating: 0, count: entry.counts.count)
        }

        for event in result.events where event.tick <= tick {
            guard case .ruleActivated(let unit, let ruleIndex) = event.kind,
                let team = unitIndex.team(of: unit),
                let unitType = unitIndex.unitType(of: unit)
            else { continue }
            let key = ProgramKey(team: team, unitType: unitType)
            guard var programCounts = counts[key], ruleIndex < programCounts.count else { continue }
            programCounts[ruleIndex] += 1
            counts[key] = programCounts
        }

        return result.ruleFireCounts.compactMap { entry in
            guard let programCounts = counts[ProgramKey(team: entry.team, unitType: entry.unitType)] else {
                return nil
            }
            return RuleFireCounts(team: entry.team, unitType: entry.unitType, counts: programCounts)
        }
    }

    private static func buildKeyframes(events: [BattleEvent], interval: Int32) -> [ReplayFrame] {
        guard let lastTick = events.last?.tick else {
            return [.empty]
        }

        var keyframes: [ReplayFrame] = []
        var frame = ReplayFrame.empty
        var eventIndex = events.startIndex
        var keyframeTick: Int32 = 0

        while keyframeTick <= lastTick {
            while eventIndex < events.endIndex, events[eventIndex].tick <= keyframeTick {
                frame = frame.applying(events[eventIndex])
                eventIndex += 1
            }
            keyframes.append(frame.withTick(keyframeTick))
            keyframeTick += interval
        }
        return keyframes
    }
}

extension Int32 {
    fileprivate func clamped(to range: ClosedRange<Int32>) -> Int32 {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
