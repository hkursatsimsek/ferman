import FermanCore

/// One fragment of a typed order, read once for an action and once for a condition. Every word a
/// match uses is consumed, so "komutanı koru" can't also count as `commanderDead` and the number
/// a condition takes can't be taken twice.
struct TemplateFragment {
    private let tokens: [TemplateToken]
    private var consumed: [Bool]

    init(_ tokens: [TemplateToken]) {
        self.tokens = tokens
        consumed = Array(repeating: false, count: tokens.count)
    }

    // MARK: Action

    /// Actions are read first: their words are more distinctive than a condition's, and a
    /// conditional verb form ("ilerlerse", "çekilince") is a condition, never an action.
    ///
    /// Throws when a second action is left over: "ilk 10 saniye bekle sonra ilerle" is two orders
    /// in one breath, and guessing how they split would yield a wrong order that still looks valid.
    mutating func takeAction() throws(RuleCompileError) -> Action? {
        guard let action = takeFirstAction() else {
            return nil
        }
        // "use your special ability": two words for the same action are one action, not two.
        let sameAction = phrases(for: action.kind)
        while let range = firstMatch(of: sameAction, rejectingConditionalForms: true) {
            consume(range)
        }
        if takeFirstAction() != nil {
            throw .multipleActions
        }
        return action
    }

    private func phrases(for kind: ActionKind) -> [TemplatePhrase] {
        TemplateLexicon.actions.first { $0.0 == kind }?.1 ?? []
    }

    private mutating func takeFirstAction() -> Action? {
        for (kind, phrases) in TemplateLexicon.actions {
            guard let range = firstMatch(of: phrases, rejectingConditionalForms: true) else {
                continue
            }
            consume(range)
            switch kind {
            case .focusFire:
                return .focusFire(takeFocusTarget(around: range))
            case .advance where matches(TemplateLexicon.attack, in: range):
                return takeFocusTarget(around: range, allowingWeakest: false).map(Action.focusFire) ?? .advance
            default:
                return Self.action(for: kind)
            }
        }
        return nil
    }

    private func matches(_ phrases: [TemplatePhrase], in range: Range<Int>) -> Bool {
        range.count == 1
            && phrases.contains {
                $0.words.count == 1
                    && $0.words[0].matches(tokens[range.lowerBound].word, rejectingConditionalForms: true)
            }
    }

    private static func action(for kind: ActionKind) -> Action {
        switch kind {
        case .advance: .advance
        case .retreat: .retreat
        case .hold: .hold
        case .focusFire: .focusFire(nil)
        case .flankLeft: .flankLeft
        case .flankRight: .flankRight
        case .regroup: .regroup
        case .useAbility: .useAbility
        case .takeCover: .takeCover
        case .guardCommander: .guardCommander
        case .scatter: .scatter
        }
    }

    /// Turkish puts the target right before the verb in the dative ("okçulara yüklen"); English
    /// puts it a few words after ("focus fire on the archers"). Anything else — including the
    /// unit a condition is about ("en yakın düşman okçuysa yüklen") — leaves the target open.
    private mutating func takeFocusTarget(around range: Range<Int>, allowingWeakest: Bool = true) -> UnitTypeID? {
        let before = range.lowerBound - 1
        if before >= 0, !consumed[before], let unit = TemplateLexicon.unit(in: tokens[before].word),
            TemplateLexicon.dativeEndings.contains(unit.ending)
        {
            consumed[before] = true
            return unit.unitType
        }
        for index in range.upperBound..<min(range.upperBound + 4, tokens.count) where !consumed[index] {
            if let unit = TemplateLexicon.unit(in: tokens[index].word) {
                consumed[index] = true
                return unit.unitType
            }
        }
        if allowingWeakest {
            _ = take(TemplateLexicon.weakest)
        }
        return nil
    }

    // MARK: Condition

    /// The first condition the remaining words describe, most specific first. Throws when the
    /// words clearly name a condition but leave out its number or unit type, or ask for a
    /// comparison the game doesn't have.
    mutating func takeCondition() throws(RuleCompileError) -> Condition? {
        if contains(TemplateLexicon.commander), contains(TemplateLexicon.commanderLost) {
            _ = take(TemplateLexicon.commander)
            _ = take(TemplateLexicon.commanderLost)
            return .commanderDead
        }
        if take(TemplateLexicon.otherwise) {
            return .always
        }
        if take(TemplateLexicon.flanked) {
            return .isFlanked
        }
        if let terrain = takeTerrain() {
            return .terrainIs(terrain)
        }
        if take(TemplateLexicon.seconds) {
            return .timeAfter(seconds: try requireNumber(for: .timeAfter))
        }
        if take(TemplateLexicon.minutes) {
            return .timeAfter(seconds: try requireNumber(for: .timeAfter) * 60)
        }
        if take(TemplateLexicon.health) {
            return .healthBelow(percent: try requireNumberBelow(for: .healthBelow))
        }
        if take(TemplateLexicon.morale) {
            return .moraleBelow(percent: try requireNumberBelow(for: .moraleBelow))
        }
        if take(TemplateLexicon.range) {
            guard let unitType = takeUnit() else {
                throw .missingConditionParameter(.targetInRange)
            }
            return .targetInRange(unitType)
        }
        if let range = firstMatch(of: TemplateLexicon.nearest), let unitType = takeUnit() {
            consume(range)
            return .nearestEnemyType(unitType)
        }
        if take(TemplateLexicon.ally) {
            return .allyCountBelow(count: try requireNumberBelow(for: .allyCountBelow))
        }
        if contains(TemplateLexicon.enemy), take(TemplateLexicon.more) {
            _ = take(TemplateLexicon.enemy)
            return .enemyDensityAbove(count: try requireNumber(for: .enemyDensityAbove))
        }
        return try takeEnemyWithin()
    }

    /// Text that reads as a condition ("eğer…", "düşman görünce…") but matched none.
    var hasConditionalWord: Bool {
        tokens.indices.contains { !consumed[$0] && TemplateLexicon.isConditionalWord(tokens[$0].word) }
    }

    private mutating func takeEnemyWithin() throws(RuleCompileError) -> Condition? {
        let cells = firstMatch(of: TemplateLexicon.cells)
        let near = firstMatch(of: TemplateLexicon.near)
        let isFar = contains(TemplateLexicon.far)
        guard cells != nil || near != nil || (isFar && contains(TemplateLexicon.enemy)) else {
            return nil
        }
        // "düşman 3 kareden uzaksa": the game only knows "closer than".
        if isFar, near == nil {
            throw .unsupportedComparison(.enemyWithin)
        }
        cells.map { consume($0) }
        near.map { consume($0) }
        _ = take(TemplateLexicon.enemy)
        return .enemyWithin(cells: try requireNumber(for: .enemyWithin))
    }

    private mutating func takeTerrain() -> Terrain? {
        for (terrain, stems) in TemplateLexicon.turkishTerrain {
            for index in tokens.indices where !consumed[index] {
                let word = tokens[index].word
                for stem in stems where word.hasPrefix(stem) {
                    // "moloz arasındayken", "ormanın içindeyken": the locative sits on the next word.
                    if TemplateLexicon.genitiveEndings.contains(String(word.dropFirst(stem.count))),
                        index + 1 < tokens.count,
                        TemplateLexicon.terrainPostpositions.contains(where: { tokens[index + 1].word.hasPrefix($0) })
                    {
                        consumed[index] = true
                        consumed[index + 1] = true
                        return terrain
                    }
                    let ending = word.dropFirst(stem.count)
                    let isLocative =
                        TemplateLexicon.locativeEndings.contains { ending.hasPrefix($0) }
                        && !TemplateLexicon.ablativeEndings.contains { ending.hasPrefix($0) }
                    if isLocative {
                        consumed[index] = true
                        return terrain
                    }
                }
            }
        }
        for (terrain, phrases) in TemplateLexicon.englishTerrain {
            guard let range = firstMatch(of: phrases), followsPreposition(range.lowerBound) else {
                continue
            }
            consume(range)
            return terrain
        }
        return nil
    }

    private func followsPreposition(_ index: Int) -> Bool {
        var previous = index - 1
        if previous >= 0, TemplateLexicon.englishArticles.contains(tokens[previous].word) {
            previous -= 1
        }
        return previous >= 0 && TemplateLexicon.englishPrepositions.contains(tokens[previous].word)
    }

    private mutating func requireNumberBelow(for kind: ConditionKind) throws(RuleCompileError) -> Int {
        if contains(TemplateLexicon.more) {
            throw .unsupportedComparison(kind)
        }
        _ = take(TemplateLexicon.fewer)
        return try requireNumber(for: kind)
    }

    private mutating func requireNumber(for kind: ConditionKind) throws(RuleCompileError) -> Int {
        guard let number = takeNumber() else {
            throw .missingConditionParameter(kind)
        }
        return number
    }

    /// The number a condition is about: one next to a measure ("3 kare", "%40", "10 saniye")
    /// first, then any plain number, and "bir" — usually just "a", even right before a measure
    /// ("bir düşman") — only as a last resort.
    private mutating func takeNumber() -> Int? {
        let candidates = tokens.indices.filter { !consumed[$0] && tokens[$0].number != nil }
        let strong = candidates.filter { !tokens[$0].isWeakNumber }
        guard let chosen = strong.first(where: isAnchored) ?? strong.first ?? candidates.first else {
            return nil
        }
        consumed[chosen] = true
        return tokens[chosen].number
    }

    private func isAnchored(_ index: Int) -> Bool {
        let next = index + 1 < tokens.count ? tokens[index + 1].word : nil
        let previous = index > 0 ? tokens[index - 1].word : nil
        return next.map(TemplateLexicon.isMeasure) == true || previous.map(TemplateLexicon.isPercentMarker) == true
    }

    private mutating func takeUnit() -> UnitTypeID? {
        for index in tokens.indices where !consumed[index] {
            if let unit = TemplateLexicon.unit(in: tokens[index].word) {
                consumed[index] = true
                return unit.unitType
            }
        }
        return nil
    }

    // MARK: Matching

    private func firstMatch(of phrases: [TemplatePhrase], rejectingConditionalForms: Bool = false) -> Range<Int>? {
        for phrase in phrases {
            for start in tokens.indices where matches(phrase, at: start, rejectingConditionalForms) {
                return start..<(start + phrase.words.count)
            }
        }
        return nil
    }

    private func matches(_ phrase: TemplatePhrase, at start: Int, _ rejectingConditionalForms: Bool) -> Bool {
        guard start + phrase.words.count <= tokens.count else {
            return false
        }
        return phrase.words.indices.allSatisfy { offset in
            let index = start + offset
            return !consumed[index]
                && phrase.words[offset].matches(
                    tokens[index].word, rejectingConditionalForms: rejectingConditionalForms)
        }
    }

    private func contains(_ phrases: [TemplatePhrase]) -> Bool {
        firstMatch(of: phrases) != nil
    }

    private mutating func take(_ phrases: [TemplatePhrase]) -> Bool {
        guard let range = firstMatch(of: phrases) else {
            return false
        }
        consume(range)
        return true
    }

    private mutating func consume(_ range: Range<Int>) {
        for index in range {
            consumed[index] = true
        }
    }
}
