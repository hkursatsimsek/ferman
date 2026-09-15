public enum Team: String, Sendable, Codable, CaseIterable {
    case player
    case enemy

    public var opponent: Team {
        switch self {
        case .player: .enemy
        case .enemy: .player
        }
    }
}
