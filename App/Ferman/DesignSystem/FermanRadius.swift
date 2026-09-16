import CoreGraphics

/// Corner radius follows material, not a single global value (design brief §3.4).
enum FermanRadius {
    /// Emir pusulası — paper, cut sharp.
    static let orderCard: CGFloat = 2
    /// Panel / sheet — metal housing.
    static let panel: CGFloat = 14
    /// Button.
    static let button: CGFloat = 8
    /// Kum masası — the table itself, no edge.
    static let sandTable: CGFloat = 0
}
