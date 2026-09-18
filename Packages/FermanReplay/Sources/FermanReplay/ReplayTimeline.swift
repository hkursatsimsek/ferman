import FermanCore

/// Turns a `BattleResult`'s flat event stream into random-access frames (D11).
///
/// Built once per result. A keyframe is kept every `keyframeInterval` ticks so
/// `frame(at:)` never folds more than one interval's worth of events, but the
/// answer is defined as "fold every event from tick 0" — a small
/// `keyframeInterval` only changes speed, never the result.
///
/// Requires `result.events` sorted by tick ascending — always true of a real
/// `BattleSimulator` run, which appends to the stream one tick at a time.
public struct ReplayTimeline: Sendable {
    public let result: BattleResult
    public let keyframeInterval: Int32

    private let keyframes: [ReplayFrame]
    /// For each keyframe, the index of the first event after it — where `frame(at:)` starts folding.
    private let keyframeEventStarts: [Int]
    /// Every `ruleActivated` event resolved to its program, in tick order, so `fireCounts(upTo:)`
    /// binary-searches its cut-off instead of scanning the whole stream.
    private let ruleActivations: [RuleActivation]
    private let unitIndex: UnitIndex

    private struct RuleActivation {
        let tick: Int32
        let key: ProgramKey
        let ruleIndex: Int
    }

    public init(result: BattleResult, keyframeInterval: Int32 = 30) {
        precondition(keyframeInterval > 0, "keyframeInterval must be positive")
        self.result = result
        self.keyframeInterval = keyframeInterval
        let unitIndex = UnitIndex(events: result.events)
        self.unitIndex = unitIndex
        (self.keyframes, self.keyframeEventStarts) = Self.buildKeyframes(
            events: result.events, interval: keyframeInterval)
        self.ruleActivations = result.events.compactMap { event in
            guard case .ruleActivated(let unit, let ruleIndex) = event.kind,
                let team = unitIndex.team(of: unit),
                let unitType = unitIndex.unitType(of: unit)
            else { return nil }
            return RuleActivation(
                tick: event.tick, key: ProgramKey(team: team, unitType: unitType), ruleIndex: ruleIndex)
        }
    }

    /// The state of the battlefield at `tick`, clamped to `[0, result.tickCount]`.
    public func frame(at tick: Int32) -> ReplayFrame {
        let tick = tick.clamped(to: 0...Int32(result.tickCount))
        var frame = keyframes[keyframeIndex(for: tick)]
        for eventIndex in foldedEventRange(forFrameAt: tick) {
            frame = frame.applying(result.events[eventIndex])
        }
        return frame.withTick(tick)
    }

    /// The events `frame(at:)` folds on top of its keyframe: those after the keyframe, up to `tick`.
    /// Never more than one keyframe interval's worth — the renderer calls `frame(at:)` twice a frame.
    func foldedEventRange(forFrameAt tick: Int32) -> Range<Int> {
        let tick = tick.clamped(to: 0...Int32(result.tickCount))
        let start = keyframeEventStarts[keyframeIndex(for: tick)]
        var end = start
        while end < result.events.endIndex, result.events[end].tick <= tick {
            end += 1
        }
        return start..<end
    }

    private func keyframeIndex(for tick: Int32) -> Int {
        min(Int(tick / keyframeInterval), keyframes.count - 1)
    }

    /// How many times each order had fired by `tick`, in the same shape as `result.ruleFireCounts`.
    public func fireCounts(upTo tick: Int32) -> [RuleFireCounts] {
        var counts: [ProgramKey: [Int]] = [:]
        for entry in result.ruleFireCounts {
            counts[ProgramKey(team: entry.team, unitType: entry.unitType)] = Array(
                repeating: 0, count: entry.counts.count)
        }

        for activation in ruleActivations[..<activationCount(upTo: tick)] {
            guard var programCounts = counts[activation.key], activation.ruleIndex < programCounts.count else {
                continue
            }
            programCounts[activation.ruleIndex] += 1
            counts[activation.key] = programCounts
        }

        return result.ruleFireCounts.compactMap { entry in
            guard let programCounts = counts[ProgramKey(team: entry.team, unitType: entry.unitType)] else {
                return nil
            }
            return RuleFireCounts(team: entry.team, unitType: entry.unitType, counts: programCounts)
        }
    }

    /// Activations with `tick <= tick`: the first index whose tick is past it (binary search).
    private func activationCount(upTo tick: Int32) -> Int {
        var low = 0
        var high = ruleActivations.count
        while low < high {
            let middle = (low + high) / 2
            if ruleActivations[middle].tick <= tick {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private static func buildKeyframes(events: [BattleEvent], interval: Int32) -> ([ReplayFrame], [Int]) {
        guard let lastTick = events.last?.tick else {
            return ([.empty], [events.startIndex])
        }

        var keyframes: [ReplayFrame] = []
        var eventStarts: [Int] = []
        var frame = ReplayFrame.empty
        var eventIndex = events.startIndex
        var keyframeTick: Int32 = 0

        while keyframeTick <= lastTick {
            while eventIndex < events.endIndex, events[eventIndex].tick <= keyframeTick {
                frame = frame.applying(events[eventIndex])
                eventIndex += 1
            }
            keyframes.append(frame.withTick(keyframeTick))
            eventStarts.append(eventIndex)
            // `interval` may be `.max` (tests fold from the start with a single keyframe).
            let (next, overflow) = keyframeTick.addingReportingOverflow(interval)
            if overflow { break }
            keyframeTick = next
        }
        return (keyframes, eventStarts)
    }
}

extension Int32 {
    fileprivate func clamped(to range: ClosedRange<Int32>) -> Int32 {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
