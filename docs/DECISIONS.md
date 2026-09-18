# FERMAN — Karar Kaydı (ADR)

Bu dosya projedeki mimari ve ürün kararlarının tek kaynağıdır. Her karar numaralıdır (`D#`). Diğer dokümanlar kararlara bu numarayla atıf yapar.

**Kurallar**
- Bir kararı değiştirmek için mevcut kaydı silme. Durumunu `Yerini aldı → D#` yap ve yeni bir kayıt ekle.
- "Kaynak" alanı kararı kimin verdiğini gösterir: **Kullanıcı** (ürün sahibi) ya da **Teknik** (mühendislik önerisi, ürün sahibi onayıyla).
- Kararla çelişen bir görev geldiğinde kodu yazma, önce sor.

**Durum anahtarı:** `Kabul` · `Önerildi` · `Yerini aldı`

---

## D1 — Minimum hedef iOS 27

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** İlk plan iOS 26+ diyordu, şablon Xcode projesi ise 27.0'a ayarlıydı. iOS 27, 14 Eylül 2026'da yayımlandı; lansman ~Şubat 2027.
- **Karar:** Deployment target iOS 27.0. Araç zinciri Xcode 27 ve Swift 6.4.
- **Sonuçlar:**
  - SwiftUI 27'nin `reorderContainer(for:isEnabled:move:)` ve `reorderable()` API'leri pusula yığınında doğrudan kullanılır.
  - SwiftData'da `@Attribute(.codable)` ve `ResultsObserver` kullanılabilir.
  - Foundation Models tarafında tek bir on-device model sürümü (iOS 27) hedeflenir, prompt'lar bir kez ayarlanır.
  - iOS 26 kullanıcıları hedef dışıdır.

## D2 — Simülasyonda sabit noktalı sayılar (Q16.16)

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** İlk sözleşme `Float` ve `SIMD2<Float>` kullanıyordu. IEEE754 temel aritmetik tek platformda deterministiktir. Farklı mimariler (arm64 iOS, x86_64 Linux CI) ve derleyici sürümleri arasında ise bit düzeyinde aynılık garanti değildir. Arena'da (D5) bir cihazın ürettiği sonucu başka cihaz doğrulayacak.
- **Karar:**
  - `FermanCore` içindeki tüm konum, hız ve oran hesapları `Fixed` (Int32, Q16.16) ve `FixedVector2` ile yapılır.
  - `FermanCore` içinde `Float`, `Double` ve `SIMD` yasaktır.
  - Trigonometri 4096 girişli tamsayı tablolardandır; tablolar `fermansim gen-tables` ile üretilip literal olarak commit edilir.
  - Karekök tamsayı `isqrt` ile alınır.
- **Sonuçlar:**
  - Altın dosyalar macOS arm64 ve Linux x86_64'te aynı checksum'ı üretmek zorundadır; CI bunu doğrular.
  - Çarpma ve bölmede Int64 ara değer kullanılır; yuvarlama ve taşma politikası `Fixed` içinde belgelenir ve test edilir.
  - Faz 0'a ~3–4 gün eklenir.
  - Render katmanı `Fixed` değerleri `CGFloat`/`Float`'a yalnızca çizim anında çevirir.

## D3 — Xcode projesi `App/Ferman.xcodeproj`

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** Kökte Xcode şablonu olarak `FERMAN.xcodeproj` oluşturulmuş: `SWIFT_VERSION = 5.0` ve SwiftData `Item` şablonu var. Plan `App/` altını öngörüyor.
- **Karar:** Faz 0 boyunca kök şablona dokunulmaz. F1.1'de kök şablon kaldırılır ve `App/Ferman.xcodeproj` oluşturulur. Bundle id `com.hksimsek.FERMAN` korunur.
- **Sonuçlar:** Faz 0 komutları yalnızca SPM paketlerini hedefler. CLAUDE.md'deki dizin ağacı `App/` yapısını gösterir.

## D4 — Kural hakkı R(n) tüm ordu için toplamdır

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** Tasarımda her birim sekmesinde "3 / 6 pusula" yazıyordu; bütçe kapsamı ve varsayılan kartın sayılıp sayılmadığı tutarsızdı.
- **Karar:**
  - R(n) bir seviyedeki tüm birim tiplerinin pusulaları arasında paylaşılır.
  - Varsayılan ("başka durumda" / `always`) pusula hak tüketmez, silinemez, taşınamaz ve her zaman yığının sonundadır.
  - Editördeki sayaç ordu genelindeki kullanımı gösterir.
- **Sonuçlar:**
  - `RuleConstraints.maxRules` ordu geneli bir değerdir.
  - `CompileContext.remainingRuleBudget` tüm programlardan hesaplanır.
  - Tasarımdaki "3 / 6" örneği "2 / 6" olarak düzeltilir.

## D5 — Arena ikili yapı: CloudKit hayalet arena + GKTurnBasedMatch Dost Düellosu + çevrimdışı önbellek

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** Plan Arena için `GKTurnBasedMatch` diyordu. Tasarımdaki Arena ise rastgele rakiplerin kayıtlı savunma setlerine saldırdığı bir "hayalet savunma" modeli: "11 / 14 saldırı püskürtüldü". Kullanıcı hem çevrimiçi hem çevrimdışı oynanabilirlik istedi.
- **Karar:**
  - **Hayalet Arena → CloudKit public database.**
    - `DefenseSet` ve `AttackReport` kayıtları tutulur.
    - Saldıran taraf savunma setini çekip kendi cihazında simüle eder.
    - Savunan taraf raporu yeniden simüle eder ve checksum'ı doğrular; eşleşmeyen rapor sayılmaz.
    - Sıralama Game Center liderlik tablosunda tutulur.
  - **Dost Düellosu → `GKTurnBasedMatch`.** Oyuncu belirli bir arkadaşa meydan okur. `matchData` (sürümlü JSON) ordu ve programları taşır; üç tur oynanır; iki taraf da checksum doğrular.
  - **Çevrimdışı:** İndirilen savunma setleri SwiftData'da önbelleklenir ve internetsiz oynanır. Sonuçlar `PendingAttackReport` kuyruğunda bekler, bağlantı gelince gönderilir.
- **Sonuçlar:**
  - Faz 4 süresi 3 haftadan 4 haftaya çıkar.
  - Kayıtlar `simulationVersion` ve `contentVersion` taşır; sürüm uyuşmazsa rapor doğrulanamaz ve ayrı işlenir.
  - Set adları kompozisyondan otomatik üretilir, serbest metin yoktur. Oyuncu adı olarak Game Center görünen adı kullanılır.
  - Game Center'da bölgesel kapsam olmadığı için tasarımdaki "Bölgende 47." metni değişir.

## D6 — Düşman YZ: GameplayKit ile oyun içinde seçim

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** Plan seviye 11–25 için `GKDecisionTree`, 26–40 için `GKMonteCarloStrategist` öngörüyordu. Bu, CLAUDE.md'deki "tek meşru GameplayKit kullanımı `GKMonteCarloStrategist`" kuralıyla çelişiyordu.
  - **Alternatif:** Düşman ordularını `fermansim` ile geliştirme sırasında üretip `levels.json`'a yazmak önerildi. Kullanıcı oyun içi GameplayKit yolunu seçti.
- **Karar:**
  - Seviye 1–10: elle yazılmış düşman kural setleri ve orduları.
  - Seviye 11–25: `EnemyTacticTree` (`GKDecisionTree`). Oyuncu profili özellikleri taktik arketipi seçer; çıktı Sendable `EnemyTactic`.
  - Seviye 26–40: `EnemyStrategist` (`GKMonteCarloStrategist`).
    - Kompozisyon ve konuşlanma, sıralı hamleli bir `GKGameModel` olarak modellenir.
    - Rollout değerlendirmesi `BattleSimulator.run(_:options:)` ile yapılır (`recordEvents: false`).
    - Rastgelelik kaynağı tohumlu `GKMersenneTwisterRandomSource`, süre bütçesi < 1,5 sn.
    - Çıktı Sendable `EnemyArmyPlan`.
  - GameplayKit import'u yalnızca `Packages/FermanAI/Sources/FermanAI/EnemyAI/` klasöründe bulunabilir.
  - `NSObject` tabanlı GameplayKit tipleri o klasörden dışarı çıkmaz. Dışa açık API yalnızca Sendable değer tipleri alır ve döndürür. `@unchecked Sendable` kullanılmaz.
  - Seçilen düşman ordusu denemeye (`BattleConfig`) yazılır; tekrar denemede aynı düşman gelir. Simülasyonun kendisi deterministik kalır.
  - `GKAgent`, `GKGridGraph`, `GKRuleSystem` ve GameplayKit rastgele kaynakları simülasyon içinde yasaktır.
- **Sonuçlar:**
  - 11–40 arasında düşman oyuncudan oyuncuya değişir. Liderlik tabloları seviye skoruna değil, kampanya ilerlemesi ve arena sonuçlarına dayanır.
  - `FermanAI` Linux'ta derlenmez; stratejist kalibrasyon testleri macOS'ta koşar.
  - Rakip modeli oyuncunun son kazanan ordu ve programlarıdır (`ProgressStore`); yeni oyuncular için referans profiller kullanılır.

## D7 — Kural sırası önceliktir; çekirdekte `priority` ve `UUID` yok

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** İlk sözleşmede `Rule.priority` (1–10) ile "öncelik sırasında dizi" ve "sürükle-sırala önceliği artırır" bir aradaydı. `Rule.id: UUID` çekirdekteki eşitlik ve Codable çıktısına karışıyordu.
- **Karar:**
  - `RuleProgram.rules` dizisinin sırası tek öncelik kaynağıdır; ilk eleman en yüksek önceliktir.
  - `Rule` yalnızca `condition` ve `action` taşır.
  - UI kimliği uygulama katmanındaki `EditableRule` (id + rule) sarmalayıcısındadır.
- **Sonuçlar:** VoiceOver sıra adını okur ("Birinci emir…"); "Öncelik dokuz" gibi bir ifade yoktur.

## D8 — İlişkili değerli `Condition` / `Action` enum'ları

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** `threshold: Int` + `conditionParameter: String?` geçersiz kombinasyonlara izin veriyordu, örneğin `isFlanked` + eşik 7.
- **Karar:**
  - `enum Condition { case enemyWithin(cells: Int), …, case nearestEnemyType(UnitTypeID), …, case always }` ve `enum Action { …, case focusFire(UnitTypeID?), … }`.
  - `ConditionKind` ve `ActionKind` (`CaseIterable`), UI seçicileri ile LLM şeması için ayna olarak kalır.
  - Parametre aralıkları `RuleValidator` içinde doğrulanır.
- **Sonuçlar:** Codable çıktısı ayrık birleşim (discriminated union) biçimindedir ve JSON şeması testle sabitlenir.

## D9 — Kural değerlendirme: 5 Hz kademeli, kenar tetiklemeli sayım, bağlılık histerezisi

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** "Tetiklenme" tanımsızdı. Her tick sayılsaydı `always` kuralı bir savaşta binlerce kez tetiklenir, hayatta kalma koşulları da titreşirdi.
- **Karar:**
  - Her birim, `unitID % 6 == tick % 6` olan tick'lerde kurallarını değerlendirir (30 Hz'de 5 Hz, yük dağıtılmış).
  - İlk eşleşen kural seçilir.
  - Seçili kural değiştiğinde `ruleActivated` olayı yayılır ve o kuralın sayacı 1 artar (kenar tetik).
  - Yeni seçilen kurala en az `tuning.minimumCommitTicks` (varsayılan 15) bağlı kalınır; bu süre yalnızca daha yüksek öncelikli bir kural eşleşirse kesilir.
  - Hiçbir kural eşleşmezse örtük davranış "ilerle ve dövüş"tür ve sayaca yazılmaz.
- **Sonuçlar:** Savaş sonrası "N kez" değerleri oyuncunun anlayacağı ölçektedir ve "hiç çalışmadı" uyarısı anlamlıdır.

## D10 — Eşzamanlı çözüm: çift tamponlu steering, toplu hasar

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** Birimler sırayla güncellenirse sonuç birim sırasına bağlı olur ve küçük ID'li birim avantaj kazanır.
- **Karar:**
  - Steering önceki tick durumundan okur, yeni tampona yazar.
  - Savaş fazında bir tick'in tüm saldırıları toplanır ve birlikte uygulanır; ölümler fazın sonunda işlenir.
  - Eşitlik bozmada her yerde (mesafe, sonra UnitID) kuralı kullanılır.
- **Sonuçlar:** "Giriş sırası karıştırılınca checksum aynı" testi mümkün olur. Birim sayısı kadar ek bellek gerekir (önceden ayrılır).

## D11 — `FermanReplay` paketi

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** Replay'in seek ve interpolasyon mantığı ile savaş sonrası analiz saf mantıktır; SpriteKit'e gömülürse test edilemez.
- **Karar:** Yalnızca `FermanCore`'a bağımlı `FermanReplay` paketi eklenir:
  - `ReplayTimeline`: olay indeksleme, 30 tick'te bir keyframe, `frame(at:)`, `fireCounts(upTo:)`.
  - `DebriefAnalyzer`: ölüm kümeleri, hiç çalışmayan ve baskın kural, eşzamanlı aktivasyon, hat bütünlüğü → typed `DebriefInsight`.
- **Sonuçlar:** Linux CI'da test edilir. `BattleScene` yalnızca `ReplayFrame` çizer. Metinleştirme uygulamadaki String Catalog'dadır.

## D12 — Uygulama katmanı deseni

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Karar:**
  - Her Feature klasöründe `XView.swift` + `XModel.swift` bulunur.
  - Model `@Observable @MainActor final class` olur; görünüm mantığı ve niyet metotları modeldedir.
  - Bağımlılıklar init ile protokol tipinde verilir. Kök `AppDependencies` `@Entry` ile environment'a konur.
  - Navigasyon: `@Observable AppRouter` + `NavigationStack(path:)` + typed `Route` enum; sheet'ler router state'inden sürülür.
  - `ObservableObject`, Combine ve singleton servisler kullanılmaz.
- **Sonuçlar:** Modeller servis sahteleriyle Swift Testing'de birim test edilir. Önizlemeler `PreviewModifier` ile bağımlılık alır.

## D13 — Concurrency modeli

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Karar:**
  - **App target:** Swift 6 dil modu, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
  - **Paketler:** varsayılan nonisolated; tüm model tipleri `Sendable` değer tipleridir.
  - **Ağır işler:** Simülasyon, stratejist ve LLM çağrıları `@concurrent` async fonksiyonlarla ana aktör dışında koşar.
  - **Paralellik sınırı:** Tek bir simülasyon koşumu her zaman tek iş parçacığıdır. Birbirinden bağımsız koşumlar (`fermansim batch`, stratejist rollout'ları) paralel çalışabilir.
  - **Yasak:** `@unchecked Sendable`, `nonisolated(unsafe)` ve `DispatchQueue` tabanlı yeni kod.
- **Sonuçlar:** GameplayKit gibi Sendable olmayan tipler tek bir fonksiyonun yerel kapsamında yaşar (D6).

## D14 — Kalıcılık: SwiftData + CloudKit private DB

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** Plan cihazlar arası senkron için `GKSavedGame` öngörüyordu. Bu API blob tabanlıdır ve çakışma çözümü elle yapılır.
- **Karar:**
  - SwiftData, v1'den itibaren `VersionedSchema` + `SchemaMigrationPlan` ile kurulur.
  - Programlar ve ordular `@Attribute(.codable)` ile saklanır.
  - Şema baştan CloudKit uyumludur: tüm özellikler opsiyonel ya da varsayılan değerli, `@Attribute(.unique)` yok.
  - Senkron CloudKit private DB üzerinden yapılır (F4.2).
  - Kayıtlı savaşlar yalnızca `BattleConfig` saklar; replay deterministik yeniden simülasyonla elde edilir.
- **Sonuçlar:** `GKSavedGame` kullanılmaz. Ayna seviyeleri (F3.7) için `LevelProgress` kazanan programı saklar.

## D15 — Klip üretimi offline render ile

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** Plan ReplayKit (`RPScreenRecorder`) öngörüyordu. Bu API ekranı cihaz en-boy oranında ve HUD ile kaydeder, kullanıcıdan izin ister, zamanlamayı da kullanıcıya bırakır.
- **Karar:** `ClipRenderer` şu hattı kullanır:
  - `SKRenderer`, `BattleScene`'i offscreen Metal texture'a çizer.
  - `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` HEVC 1080×1920, 30 fps, 20 sn üretir.
  - Paylaşım kartı `ImageRenderer` ile üretilip bindirilir.
  - 20 sn'lik pencereyi `DebriefAnalyzer`'ın "kilit an"ı belirler.
  - Paylaşım `ShareLink` + `Transferable` ile yapılır.
- **Sonuçlar:** ReplayKit kullanılmaz. Klip her zaman tam 9:16 ve HUD'suzdur. Hedef boyut < 8 MB.

## D16 — Ses girişi: SpeechAnalyzer

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Karar:** `SFSpeechRecognizer` yerine `SpeechAnalyzer` + `SpeechTranscriber` (on-device) kullanılır. Dil varlıkları `AssetInventory` ile indirilir. Desteklenen diller `tr_TR` ve `en_US`.
- **Sonuçlar:** Varlık indirildikten sonra çevrimdışı çalışır. Özellik kullanılamıyorsa mikrofon düğmesi gizlenir.

## D17 — Foundation Models kullanım deseni

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Karar:**
  - **Hazırlık:**
    - `SystemLanguageModel.default.availability` ve `supportsLocale()` önce kontrol edilir.
    - Her derlemede yeni `LanguageModelSession` açılır; geçmiş tutulmaz.
    - `Instructions` Apple'ın tam locale cümlesiyle başlar: "The person's locale is tr_TR.".
    - `GenerationOptions(sampling: .greedy)` kullanılır.
  - **Şema:**
    - `@Generable` ayna tipleri yalnızca `FoundationModelsCompiler.swift` içinde tanımlanır; çekirdek enum'ları FoundationModels'e bağlanmaz.
    - Seviyede kilitli koşul ve eylemler `DynamicGenerationSchema` ile şemadan çıkarılır.
  - **Sınırlar:**
    - `tokenCount(for:)` ile oturum başına < 800 token ve `contextSize` kontrolü yapılır.
    - Editör açılınca `prewarm()` çağrılır.
    - 2 sn zaman aşımında `TemplateCompiler`'a düşülür.
  - **Test:** Birim testlerde iOS 27 `LanguageModel` protokolüyle sahte model kullanılır. Doğruluk harness'ı gerçek modelle macOS/cihazda koşar.
- **Sonuçlar:** Model hiçbir zaman sonucu belirlemez. Üretilen her kural oyuncuya gösterilir ve onaylanır (CLAUDE.md kural 3).

## D18 — `RuleCompiler<Input>` protokolü ve ortak doğrulayıcı

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** `compile(_ text: String…)` imzası seçici tabanlı `ManualCompiler`'a uymuyordu.
- **Karar:**
  - `protocol RuleCompiler<Input>: Sendable { associatedtype Input: Sendable; func compile(_ input: Input, context: CompileContext) async throws(RuleCompileError) -> [Rule] }`.
  - `ManualCompiler.Input = RuleDraft`; `TemplateCompiler` ve `FoundationModelsCompiler` için `Input = String`.
  - Tüm çıktılar `FermanCore.RuleValidator`'dan geçer.
  - Metin zinciri `any RuleCompiler<String>` ile kurulur.
- **Sonuçlar:** Uygulamanın tamamı `ManualCompiler` ile oynanabilir. LLM bir kolaylıktır.

## D19 — İçerik biçimi: tamsayı birimler, ASCII haritalar, pişirilmiş zorluk tabloları

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Karar:**
  - JSON içerikte ondalık sayı yoktur; açık birimli tamsayılar kullanılır (`speedMilliCellsPerSecond`, `attackIntervalTicks`).
  - Haritalar okunur ve diff'lenir ASCII satırlarıdır: `.` açık, `F` orman, `H` tepe, `W` su, `R` moloz.
  - `DifficultyCurve` formülleri (`pow` içeren) yalnızca üretici araçta hesaplanır; runtime tamsayı tabloyu okur.
  - Birim görünen adları çekirdekte değil, String Catalog'da `unit.<id>` anahtarıyla tutulur.
- **Sonuçlar:** `ContentValidator` hatalı içeriği typed hata ile reddeder. Her seviye bir referans çözümle test edilir.

## D20 — Araç zinciri ve kalite kapıları

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Karar:**
  - **Test:** Birim testleri Swift Testing (`@Test`, `#expect`, `@Test(arguments:)`), UI testleri XCUITest + `performAccessibilityAudit()`. Snapshot testleri `ImageRenderer` tabanlı yardımcıyla yazılır; üçüncü parti kütüphane yok.
  - **Biçim:** Toolchain'deki `swift format` ve repo kökündeki `.swift-format`.
  - **Değişmez denetimleri:**
    - `InvariantTests`: FermanCore kaynaklarında yasak import, API ve `Float`/`Double` taraması.
    - `Scripts/check-invariants.sh`: FoundationModels ve GameplayKit import yerleri, boş `Package.resolved`, String Catalog'da yasak kelimeler.
  - **CI:**
    - GitHub Actions: Linux (Swift 6.4 imajı) ve macOS'ta paket testleri, kapsam eşiği, altın dosyalar, `fermansim verify`; gece denge koşumu.
    - Xcode Cloud: uygulama build/test ve TestFlight.
  - **Gözlem:** `Logger` (OSLog), `OSSignposter`, MetricKit. Üçüncü parti analitik yok.
- **Sonuçlar:** Faz 5'e kadar `Package.resolved` boş kalır.

## D21 — Yerelleştirme ve Türkçe dil bilgisi

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** Pusula metinleri sayıya ek alır ("3 kareden", "%35'in", "%40'ın", "5'ten"). Foundation'ın Automatic Grammar Agreement özelliği Türkçe'yi kapsamıyor.
- **Karar:**
  - Tüm kullanıcı metinleri String Catalog'dadır, kaynak dil `tr`.
  - `OrderPhraseFormatter` Türkçe ünlü ve ünsüz uyumuna göre sayı eklerini üretir; 0–100 ve yüzde değerleri tablo testiyle doğrulanır.
  - İngilizce çeviri lansman öncesi tamamlanır (F6.6).
- **Sonuçlar:** Kod içinde sabit kullanıcı metni yoktur. Yasak kelime testi katalog üzerinde koşar.

## D22 — v1 karanlık mod

- **Tarih:** 2026-09-15 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** Tasarımda açık mod yalnızca 3 ekran için çizilmiş; brief karanlık modu asıl kabul ediyor.
- **Karar:** Renk token'ları Asset Catalog'da Any/Dark çiftli tanımlanır. v1 `UIUserInterfaceStyle = Dark` ile yayımlanır. Açık modun açılıp açılmayacağına F6.7'de karar verilir.
- **Sonuçlar:** Açık mod ileride altyapı değişikliği gerektirmez; eksik ekran tasarımları tamamlanınca açılabilir.

## D23 — F0.12 CI doğrulaması proje bitimine ertelendi, Faz 1'e geçildi

- **Tarih:** 2026-09-16 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** `docs/FERMAN-PLAN.md` §6: "Fazın kabul kriterleri karşılanmadan sonraki faza geçilmez." F0.12'nin "CI yeşil" alt kriteri (`.github/workflows/core.yml`: Linux x86_64 + macOS, altın dosyaların iki platformda aynı checksum'ı üretmesi) karşılanmamıştı çünkü iş akışı kasıtlı olarak eklenmemişti. Faz 0'ın geri kalan tüm kabul kriterleri (determinizm, altın dosyalar, kapsam > %85, bağımlılık yok, F0.13 denge sorusu) yerelde karşılandı.
- **Karar:** `.github/workflows/core.yml` kurulumu ve CI'da doğrulama proje bitimine (Faz 7 lansman öncesi) ertelenir. Bu ertelemeyle birlikte Faz 1'e (F1.1) geçilir.
- **Sonuçlar:**
  - **Risk:** Determinizm sözleşmesi (CLAUDE.md kural 2) macOS arm64 = Linux x86_64 eşitliğini gerektirir; bu eşitlik CI olmadan doğrulanamaz, çünkü yerel geliştirme yalnızca macOS'tadır (bkz. `Scripts/check-invariants.sh` ve "Linux doğrulaması yerelde yapılmaz" notu). Bu pencerede Linux'a özgü bir determinizm kırılması sessizce birikebilir.
  - Telafi: `FermanCore`'a dokunan her değişiklikten sonra yerelde (macOS) `fermansim verify --runs 1000` çalıştırmaya devam edilir; bu CI'ın yerini tutmaz ama tek platformlu regresyonu yakalar.
  - `.github/workflows/core.yml` eklenip yeşil olduğunda F0.12 tam anlamıyla kapanır; bu karar F3.9'daki `balance-nightly.yml` iş akışını etkilemez, o da kendi adımına kadar ertelenmiş sayılır.

## D24 — Birimler: üstten görülen döküm minyatürler

- **Tarih:** 2026-09-18 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** Faz 1 sonunda savaşta her birim 10 pt'lik düz bir daireydi; dört birim tipi her ekranda (tepsi, ızgara, editör sekmeleri, savaş) birebir aynı görünüyordu. Tasarım teslimi de tipe özgü figür çizmemişti. Palet kum üstünde neredeyse eşit parlaklıkta: demir/kum 1,00:1, pirinç/aydınlık kum 1,06:1, pirinç/demir 1,42:1 (WCAG göreli parlaklık). Renk tek başına ne tipi ne takımı ayırabiliyor.
- **Karar:**
  - Kamera kum masasına tam yukarıdan bakar (brief §4.5 "üstten görünüm" korunur). Her birim, döküm altlık üstünde duran bir minyatürün üstten görünüşüdür.
  - Tip kimliği silüetle verilir, silahlar abartılır: mızrakçının mızrağı gövdenin 1,5–1,7 katı ileri uzanır; okçu önde yay kavisi + sırtta sadak; süvarinin at gövdesi yaya figürün ~1,8 katı; kalkanlı önünün ~%60'ını kaplayan kavisli kalkan.
  - Tek poz seti `zRotation` ile döndürülür (yön sürekli ve kesin görünür). Pozlar: `base`, `strike`, `brace`, `fallen` (+ süvari dörtnal karesi). Yürüme döngüsü yok.
  - Pirinç (oyuncu) ve demir (düşman) ayrı render edilmiş doku setleridir; çalışma zamanında renklendirme yok.
  - Takım renk dışı bir işaretle de kodlanır: oyuncu **yuvarlak**, düşman **sekizgen** altlık. Her figürde mürekkep rengi kontak gölgesi ve koyu kenar vardır.
- **Sonuçlar:** `UnitToken` ve `UnitNode` birim tipi ve poz alır; SwiftUI ve SpriteKit aynı görselleri kullanır (`UnitArt`). Brief §3.4 "birim jetonu tam yuvarlak" yalnızca oyuncu altlığı için geçerli kalır. Eğik "lamba görünümü" (profil figürler) bu kararın dışındadır, F4.7 ile düşünülür.

## D25 — Sanat üretimi: betikli Blender, çıktılar commit edilir

- **Tarih:** 2026-09-18 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** Projede sanatçı yok; hiçbir görsel varlık yoktu. Seçenekler: betikli Blender, sanatçıya model ısmarlamak, yalnızca kodla çizim, yapay zekâ ile görsel üretimi.
- **Karar:**
  - Figürler, arazi objeleri, ok/toz/mühür dokuları ve uygulama ikonu `Tools/figures/` altındaki bir Python betiğiyle Blender'da ilkel şekillerden modellenir ve başsız (`blender -b`) render edilir. İkili `.blend` dosyası repoda tutulmaz; model tamamen betiktedir. Blender sürümü betikte sabitlenir.
  - Çıktı PNG'leri `App/Ferman/Assets.xcassets` içine yazılır ve **commit edilir**; normal derleme Blender gerektirmez. Blender yalnızca geliştirme aracıdır, uygulamaya girmez (kural 6 korunur).
  - Blender gelmeden önce aynı dosya adlarıyla Core Graphics yer tutucular kullanılır; Blender çıktısı bunların üstüne yazılır, kod değişmez.
  - Yalnızca özgün ya da CC0 varlık kullanılır. CC-BY/CC-BY-SA (App Store DRM çelişkisi) ve GPL sanat kullanılmaz. **Yapay zekâ ile üretilmiş sanat gönderilmez** (telif koruması yok, mevcut stillere kayma riski, varyantlar arası tutarsızlık); yalnızca özel ruh hali panolarında kabul edilebilir.
- **Sonuçlar:** Yeni poz ya da birim eklemek betiği yeniden çalıştırmaktır. Görsel kaynak ve lisans kaydı `docs/design/ART-DIRECTION.md`'dedir. Modeller ileride USD ile RealityKit'e taşınabilir.

## D26 — Dikey masa: harita ekranda 90° döndürülür

- **Tarih:** 2026-09-18 · **Durum:** Kabul · **Kaynak:** Kullanıcı
- **Bağlam:** Haritalar 24×14 (oyuncu solda, düşman sağda). Dikey telefonda `.aspectFit` ile masa 393×229 pt'lik bir şeride iniyor, hücre ≈ 16 pt, birim ≈ 10 pt ≈ 31 px. Ayrıca Ordu Kurulumu ASCII 0. satırı üstte, `BattleScene` altta çiziyordu; yerleşim savaşta dikey aynalanıyordu.
- **Karar:** Masa ekranda 90° döndürülerek çizilir: oyuncu bölgesi altta, düşman üstte. Simülasyon, harita dosyaları, seviyeler ve altın dosyalar değişmez; dönüşüm yalnızca çizimdedir. Sim koordinatı ile görünüm noktası arasındaki **tek** dönüşüm noktası `App/Ferman/Rendering/BoardProjection.swift`'tir; SpriteKit (y yukarı) ve SwiftUI (y aşağı) ikisi de onu kullanır.
- **Sonuçlar:** Hücre ~23–28 pt'ye çıkar (figürler ~2,3× büyür). Brief §4.3 "sol üçte bir" → "alt bölge". 9:16 klip (D15) dikey masaya doğal olarak oturur.

## D27 — Replay canlandırması replay zamanının saf fonksiyonudur

- **Tarih:** 2026-09-18 · **Durum:** Kabul · **Kaynak:** Teknik
- **Bağlam:** Görsel geçişte savaş canlandırılıyor (zıplama, hamle, ok, devrilme, moral çöküşü, yetenek pozları). Replay ileri/geri sarılabiliyor, 1×/2×/4× oynuyor ve `ClipRenderer` (D15) aynı sahneyi `SKRenderer` ile offscreen çiziyor. Durum tutan `SKAction`'lar ve tohumsuz parçacık rastgeleliği bunlarla tutarsız sonuç verir.
- **Karar:**
  - Her figürün pozu (konum, yön, zıplama, poz karesi, parlama) `pose(unit, t)` biçiminde replay zamanının saf fonksiyonudur. Birim başına olay indeksi `FermanReplay`'de (`UnitTrack`, Linux'ta testli) tutulur; çizim tarafı yalnızca okur.
  - Ölen figür devrilir ve masada `fallen` pozuyla kalır (ARCHITECTURE §8'deki "ölümde gizlenir" yerine).
  - Vuruş parlaması kâğıt rengine (`#D6D0C2`) gider; **kıvılcım rengi yalnızca kural tetiklenmesindedir** (brief §3.2) ve yalnızca oyuncu birimlerinde çakar.
  - Okçu okları, replay geleceği bildiği için uçuş süresi kadar önceden fırlatılır ve `attack` tick'inde iner.
  - `spearWall`/`shieldWall`/`charge` etkinleşmesi `FermanCore`'da mevcut `.abilityUsed` olayıyla yalnızca `recordEvents` açıkken yayımlanır. Durum ve RNG değişmez, checksum değişmez, `simulationVersion` artmaz.
- **Sonuçlar:** Geri sarma, hız ve klip birebir aynı kareyi üretir. Titreme gibi "rastgele" görünen hareketler birim kimliği + tick hash'inden türetilir.
