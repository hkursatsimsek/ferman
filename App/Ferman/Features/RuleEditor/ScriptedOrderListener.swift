import Foundation

/// A stand-in microphone for UI tests and screenshots (`-uiTestSpokenOrder "<text>"`): it "hears" the
/// given text a word at a time. The real `SpeechOrderListener` needs a device — Apple's own live-audio
/// sample doesn't run in the Simulator.
nonisolated struct ScriptedOrderListener: OrderListening {
    let text: String

    func availability() async -> ListeningAvailability { .ready }

    func installAssets(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }

    func startListening() async throws -> any SpokenOrder {
        await ScriptedSpeech(words: text.split(separator: " ").map(String.init))
    }
}

private actor ScriptedSpeech: SpokenOrder {
    nonisolated let transcripts: AsyncThrowingStream<String, any Error>
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation
    private let words: [String]
    private var speaking: Task<Void, Never>?

    init(words: [String]) async {
        (transcripts, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        self.words = words
        speaking = Task { await self.speak() }
    }

    func finish() async {
        speaking?.cancel()
        continuation.yield(words.joined(separator: " "))
        continuation.finish()
    }

    private func speak() async {
        for count in 1...max(words.count, 1) {
            guard !Task.isCancelled else { return }
            continuation.yield(words.prefix(count).joined(separator: " "))
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
