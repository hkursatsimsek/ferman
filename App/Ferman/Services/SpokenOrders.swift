import AVFoundation
import OSLog
import Speech

/// Whether a spoken order can be taken right now (F2.5, D16, D31).
nonisolated enum ListeningAvailability: Equatable, Sendable {
    /// No on-device transcriber for this device or language: the microphone button stays hidden (D16).
    case unavailable
    /// The language's speech assets aren't on the device yet — one download, then it works offline.
    case needsAssets
    case ready
}

nonisolated enum ListeningError: Error, Equatable, Sendable {
    case microphoneDenied
    case noMicrophone
    case assetsMissing
    case failed
}

/// The microphone side of writing an order. What it hears goes into the same field a typed order does,
/// and from there through the same compilers and the same sealing (CLAUDE.md rule 3).
nonisolated protocol OrderListening: Sendable {
    func availability() async -> ListeningAvailability
    /// Downloads and keeps the language's speech assets; `progress` reports 0…1 along the way.
    func installAssets(progress: @escaping @Sendable (Double) -> Void) async throws
    /// Opens the microphone. Throws before anything is heard when permission, a microphone or the
    /// assets are missing.
    func startListening() async throws -> any SpokenOrder
}

/// One spoken order in progress.
nonisolated protocol SpokenOrder: Sendable {
    /// The running transcript, each element the whole text so far. Ends after `finish()`, with the final text last.
    var transcripts: AsyncThrowingStream<String, any Error> { get }
    /// Closes the microphone; the last words still come through `transcripts`.
    func finish() async
}

/// Spoken orders through `SpeechAnalyzer` + `DictationTranscriber`, on device. D16 named
/// `SpeechTranscriber`, but it has no Turkish model (macOS 27: 45 locales, no `tr_TR`) while
/// `DictationTranscriber` does (D31). Audio comes from iOS 27's `CaptureInputSequenceProvider`, which
/// converts it for the transcriber without an audio-engine tap.
nonisolated struct SpeechOrderListener: OrderListening {
    /// Words the transcriber should expect (`AnalysisContext.contextualStrings`): units and orders.
    static let vocabulary = [
        "okçu", "okçular", "mızrakçı", "mızrakçılar", "süvari", "süvariler", "kalkanlı", "kalkanlılar", "kare",
        "geri çekil", "ilerle", "yerinde kal", "yüklen", "soldan kuşat", "sağdan kuşat", "toplan", "dağıl",
        "siper al", "komutanı koru", "mızrak duvarı", "kalkan duvarı", "yaylım", "hücum", "başka durumda",
    ]

    func availability() async -> ListeningAvailability {
        guard let locale = await Self.locale() else { return .unavailable }
        switch await AssetInventory.status(forModules: [Self.transcriber(locale)]) {
        case .installed: return .ready
        case .supported, .downloading: return .needsAssets
        case .unsupported: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func installAssets(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let locale = await Self.locale() else { throw ListeningError.assetsMissing }
        try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [Self.transcriber(locale)]) {
            let watcher = Task {
                while !Task.isCancelled {
                    progress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { watcher.cancel() }
            try await request.downloadAndInstall()
        }
        progress(1)
    }

    func startListening() async throws -> any SpokenOrder {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw ListeningError.microphoneDenied }
        guard let locale = await Self.locale() else { throw ListeningError.assetsMissing }
        let transcriber = Self.transcriber(locale)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw ListeningError.assetsMissing
        }
        return try await DictationSession(transcriber: transcriber)
    }

    /// The player's language if the transcriber has it, else the game's own (Turkish), else English.
    static func locale() async -> Locale? {
        for candidate in [Locale.current, Locale(identifier: "tr_TR"), Locale(identifier: "en_US")] {
            if let locale = await DictationTranscriber.supportedLocale(equivalentTo: candidate) {
                return locale
            }
        }
        return nil
    }

    /// A short phrase, punctuated (commas split orders for `TemplateCompiler`), corrected as it goes.
    static func transcriber(_ locale: Locale) -> DictationTranscriber {
        DictationTranscriber(
            locale: locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
            reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
    }
}

/// One microphone session. Everything that isn't `Sendable` — the capture session, its provider — lives
/// inside this actor and never leaves it.
private actor DictationSession: SpokenOrder {
    nonisolated private static let logger = Logger(subsystem: "com.hksimsek.FERMAN", category: "SpokenOrders")

    nonisolated let transcripts: AsyncThrowingStream<String, any Error>
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation
    private let provider: CaptureInputSequenceProvider
    private let analyzer: SpeechAnalyzer
    private var analysis: Task<Void, Never>?
    private var reading: Task<Void, Never>?

    init(transcriber: DictationTranscriber) async throws {
        guard let device = AVCaptureDevice.default(.microphone, for: .audio, position: .unspecified) else {
            throw ListeningError.noMicrophone
        }
        provider = try await CaptureInputSequenceProvider.providerWithSession(from: device, compatibleWith: [transcriber])
        analyzer = SpeechAnalyzer(modules: [transcriber])
        (transcripts, continuation) = AsyncThrowingStream.makeStream(of: String.self)

        let context = AnalysisContext()
        context.contextualStrings[.general] = SpeechOrderListener.vocabulary
        try await analyzer.setContext(context)
        provider.captureSession.startRunning()
        reading = Task { await self.read(transcriber) }
        analysis = Task { await self.analyze() }
    }

    func finish() async {
        analysis?.cancel()
        await analysis?.value
        await reading?.value
    }

    /// Progressive results replace the stretch of audio they cover (Apple's live-audio sample).
    private func read(_ transcriber: DictationTranscriber) async {
        var transcript = AttributedString()
        do {
            for try await result in transcriber.results {
                if let range = transcript.rangeOfAudioTimeRangeAttributes(intersecting: result.range) {
                    transcript.replaceSubrange(range, with: result.text)
                } else {
                    transcript.append(result.text)
                }
                continuation.yield(String(transcript.characters))
            }
            continuation.finish()
        } catch {
            Self.logger.error("Transcription failed: \(error, privacy: .public)")
            continuation.finish(throwing: ListeningError.failed)
        }
    }

    /// Runs until `finish()` cancels it; then the last words are finalized and the results end.
    private func analyze() async {
        do {
            let lastTime = try await analyzer.analyzeSequence(provider.analyzerInputs)
            try await withTaskCancellationShield {
                if let lastTime {
                    try await analyzer.finalizeAndFinish(through: lastTime)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            }
        } catch {
            Self.logger.error("Speech analysis failed: \(error, privacy: .public)")
            await analyzer.cancelAndFinishNow()
        }
        provider.captureSession.stopRunning()
        // The capture session switched the app to a recording category; the game's own sounds mix
        // with other audio again (`AudioService`).
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            Self.logger.error("Could not restore the ambient audio session: \(error, privacy: .public)")
        }
    }
}
