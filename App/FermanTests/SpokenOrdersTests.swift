import FermanAI
import FermanCore
import Testing

@testable import Ferman

/// F2.5: the microphone beside the write field. A scripted listener stands in for `SpeechAnalyzer` —
/// the real one only runs on a device (Apple's own live-audio sample doesn't run in the Simulator).
@MainActor
struct SpokenOrdersTests {
    private static func makeModel(
        listener: (any OrderListening)?,
        constraints: RuleConstraints = .unrestricted
    ) -> RuleEditorModel {
        RuleEditorModel(
            unitTypes: ["okcu"], catalog: Fixture.catalog, constraints: constraints, listener: listener)
    }

    /// Waits for the model to catch up with the listener's background stream.
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func withoutAListenerTheMicrophoneStaysHidden() async {
        let model = Self.makeModel(listener: nil)
        await model.checkListening()
        #expect(model.listening == .unavailable)
    }

    @Test(
        arguments: [
            (ListeningAvailability.ready, RuleEditorModel.ListeningState.idle),
            (.needsAssets, .needsAssets),
            (.unavailable, .unavailable),
        ])
    func availabilityDecidesTheMicrophone(answer: ListeningAvailability, expected: RuleEditorModel.ListeningState)
        async
    {
        let model = Self.makeModel(listener: ScriptedListener(availability: answer))
        await model.checkListening()
        #expect(model.listening == expected)
    }

    @Test func aFrontWithNoOrdersToWriteHasNoMicrophone() async {
        let model = Self.makeModel(
            listener: ScriptedListener(availability: .ready),
            constraints: RuleConstraints(maxRules: 0, availableConditions: [.always], availableActions: [.advance]))
        await model.checkListening()
        #expect(model.listening == .unavailable)
    }

    @Test func installingTheAssetsReadiesTheMicrophone() async {
        let listener = ScriptedListener(availability: .needsAssets)
        let model = Self.makeModel(listener: listener)
        await model.checkListening()

        await model.installSpeechAssets()

        #expect(model.listening == .idle)
        #expect(await listener.installs == 1)
    }

    @Test func aFailedDownloadOffersItAgain() async {
        let model = Self.makeModel(listener: ScriptedListener(availability: .needsAssets, installFails: true))
        await model.checkListening()

        await model.installSpeechAssets()

        #expect(model.listening == .needsAssets)
        #expect(model.listeningError == .assetsMissing)
    }

    @Test func theTranscriptRunsWhileSpeakingAndKeepsTheLastWords() async throws {
        let listener = ScriptedListener(
            availability: .ready, partials: ["düşman", "düşman 3 kareden yakınsa"],
            final: "düşman 3 kareden yakınsa geri çekil")
        let model = Self.makeModel(listener: listener)
        await model.checkListening()

        await model.startListening()
        try await Self.waitUntil { model.listening == .listening(transcript: "düşman 3 kareden yakınsa") }
        #expect(model.listening == .listening(transcript: "düşman 3 kareden yakınsa"))

        let spoken = await model.stopListening()
        #expect(spoken == "düşman 3 kareden yakınsa geri çekil")
        #expect(model.listening == .idle)
    }

    @Test func whatWasSaidBecomesSlipsLikeTypedText() async throws {
        let model = Self.makeModel(
            listener: ScriptedListener(availability: .ready, partials: [], final: "kuşatıldıysam dağıl"))
        await model.checkListening()

        await model.startListening()
        let spoken = await model.stopListening()
        await model.write(spoken)

        #expect(model.written?.slips.map(\.draft) == [RuleDraft(conditionKind: .isFlanked, actionKind: .scatter)])
        #expect(model.orders.isEmpty)
    }

    @Test func aRefusedMicrophoneSaysSoAndStaysReady() async {
        let model = Self.makeModel(listener: ScriptedListener(availability: .ready, startError: .microphoneDenied))
        await model.checkListening()

        await model.startListening()

        #expect(model.listeningError == .microphoneDenied)
        #expect(model.listening == .idle)
    }

    @Test func missingAssetsAtStartOfferTheDownload() async {
        let model = Self.makeModel(listener: ScriptedListener(availability: .ready, startError: .assetsMissing))
        await model.checkListening()

        await model.startListening()

        #expect(model.listening == .needsAssets)
    }

    @Test func noListeningWhileWrittenSlipsWait() async {
        let listener = ScriptedListener(availability: .ready)
        let model = Self.makeModel(listener: listener)
        await model.checkListening()
        await model.write("geri çekil")

        await model.startListening()

        #expect(model.listening == .idle)
        #expect(await listener.starts == 0)
    }
}

/// Answers availability as told and "hears" a fixed sequence of transcripts.
private actor ScriptedListener: OrderListening {
    private var answer: ListeningAvailability
    private let installFails: Bool
    private let startError: ListeningError?
    private let partials: [String]
    private let final: String
    private(set) var installs = 0
    private(set) var starts = 0

    init(
        availability: ListeningAvailability, installFails: Bool = false, startError: ListeningError? = nil,
        partials: [String] = [], final: String = ""
    ) {
        answer = availability
        self.installFails = installFails
        self.startError = startError
        self.partials = partials
        self.final = final
    }

    func availability() async -> ListeningAvailability { answer }

    func installAssets(progress: @escaping @Sendable (Double) -> Void) async throws {
        installs += 1
        progress(0.5)
        if installFails { throw ListeningError.assetsMissing }
        progress(1)
        answer = .ready
    }

    func startListening() async throws -> any SpokenOrder {
        if let startError { throw startError }
        starts += 1
        return ScriptedSpokenOrder(partials: partials, final: final)
    }
}

private actor ScriptedSpokenOrder: SpokenOrder {
    nonisolated let transcripts: AsyncThrowingStream<String, any Error>
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation
    private let final: String

    init(partials: [String], final: String) {
        (transcripts, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        self.final = final
        for partial in partials {
            continuation.yield(partial)
        }
    }

    func finish() async {
        continuation.yield(final)
        continuation.finish()
    }
}

private enum Fixture {
    static let catalog: [UnitType] = [
        UnitType(
            id: "okcu", cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000, damage: 10,
            attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [], ability: .volley)
    ]
}
