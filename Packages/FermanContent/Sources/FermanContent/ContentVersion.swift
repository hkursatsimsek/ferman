/// Bumped whenever units, levels or maps change in a way that can alter a battle's outcome.
///
/// Arena records and duel match data carry it next to `simulationVersion`, so a report produced against different
/// content is recognised as unverifiable instead of being counted as a mismatch (D5).
public enum ContentVersion {
    public static let current = 1
}
