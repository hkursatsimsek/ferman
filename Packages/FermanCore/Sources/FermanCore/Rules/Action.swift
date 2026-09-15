/// What a unit does while an order applies (FERMAN-PLAN §5.4).
public enum Action: Sendable, Hashable {
    case advance
    case retreat
    case hold
    /// Targets the nearest enemy of the given type, or the weakest enemy nearby when no type is given.
    case focusFire(UnitTypeID?)
    case flankLeft
    case flankRight
    case regroup
    case useAbility
    case takeCover
    case guardCommander
    case scatter

    public var kind: ActionKind {
        switch self {
        case .advance: .advance
        case .retreat: .retreat
        case .hold: .hold
        case .focusFire: .focusFire
        case .flankLeft: .flankLeft
        case .flankRight: .flankRight
        case .regroup: .regroup
        case .useAbility: .useAbility
        case .takeCover: .takeCover
        case .guardCommander: .guardCommander
        case .scatter: .scatter
        }
    }
}

/// Payload-free mirror of `Action` for pickers, level locks and the language-model schema (D8).
public enum ActionKind: String, Sendable, Codable, CaseIterable {
    case advance
    case retreat
    case hold
    case focusFire
    case flankLeft
    case flankRight
    case regroup
    case useAbility
    case takeCover
    case guardCommander
    case scatter

    public var parameter: ActionParameter {
        switch self {
        case .focusFire: .optionalUnitType
        default: .none
        }
    }
}

public enum ActionParameter: Sendable, Hashable {
    case none
    case optionalUnitType
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case unitType
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ActionKind.self, forKey: .kind) {
        case .advance: self = .advance
        case .retreat: self = .retreat
        case .hold: self = .hold
        case .focusFire: self = .focusFire(try container.decodeIfPresent(UnitTypeID.self, forKey: .unitType))
        case .flankLeft: self = .flankLeft
        case .flankRight: self = .flankRight
        case .regroup: self = .regroup
        case .useAbility: self = .useAbility
        case .takeCover: self = .takeCover
        case .guardCommander: self = .guardCommander
        case .scatter: self = .scatter
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if case .focusFire(let unitType) = self {
            try container.encodeIfPresent(unitType, forKey: .unitType)
        }
    }
}
