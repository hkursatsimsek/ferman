# FERMAN — Mimari

Bu doküman FERMAN'ın modül yapısını, veri akışını ve katman sorumluluklarını tanımlar.
- Kararların gerekçeleri: [`DECISIONS.md`](DECISIONS.md) (`D#`).
- Adım adım yol haritası ve simülasyon semantiği: [`FERMAN-PLAN.md`](FERMAN-PLAN.md).
- Her oturumda geçerli kurallar: [`../CLAUDE.md`](../CLAUDE.md).

---

## 1. Genel desen

**Fonksiyonel çekirdek, emir kipli kabuk, tek yönlü veri akışı.**

- **Saf çekirdek:** Oyunun anlamı `BattleConfig → BattleResult` saf fonksiyonudur.
  - Yan etkisi yoktur, saate ve rastgeleliğe bağlı değildir.
  - Linux'ta test edilir ve CI'da doğrulanır.
- **Emir kipli kabuk:** Çevresindeki her şey veri hazırlar ya da sonucu gösterir. Bu kabuk UI, render, kalıcılık, Game Center, CloudKit, LLM ve reklamdan oluşur.
- **Simüle-sonra-oynat:** Simülasyon savaş başlamadan sonuna kadar koşar. Render yalnızca olay akışını oynatır. Yeniden başlatma, hız kontrolü, geri sarma, klip üretimi ve arena doğrulaması bu sayede ek maliyetsizdir.

```
                   ┌──────────────── App (SwiftUI + SpriteKit) ────────────────┐
 levels.json ──►   │ Campaign ─► ArmySetup ─► RuleEditor ─► BattleConfig        │
 units.json        │                                           │                │
 (FermanContent)   │                              BattleRunner (@concurrent)    │
                   │                                           ▼                │
 EnemyAI ─────────►│                  FermanCore.BattleSimulator.run(config)    │
 (FermanAI)        │                                           ▼                │
 RuleCompiler ────►│                                     BattleResult           │
                   │                                           ▼                │
                   │               FermanReplay.ReplayTimeline / DebriefAnalyzer│
                   │                   ▼                           ▼            │
                   │      BattleScene (SpriteKit) + HUD      DebriefView        │
                   │                                               ▼            │
                   │                              ProgressStore (SwiftData)     │
                   └────────────────────────────────────────────────────────────┘
```

---

## 2. Modüller ve bağımlılık kuralları

| Modül | Konum | Bağımlılık | Linux | Sorumluluk |
|---|---|---|---|---|
| `FermanCore` | `Packages/FermanCore` | yalnızca Foundation | ✅ | Sabit nokta matematik, RNG, model, kurallar, simülasyon, olaylar, checksum |
| `FermanContent` | `Packages/FermanContent` | FermanCore | ✅ | JSON kaynaklar, `ContentCatalog`, `ContentValidator`, zorluk tabloları |
| `FermanReplay` | `Packages/FermanReplay` | FermanCore | ✅ | `ReplayTimeline`, `ReplayFrame`, `DebriefAnalyzer` |
| `FermanAI` | `Packages/FermanAI` | FermanCore, FermanContent | ❌ | `RuleCompiler<Input>`, Manual/Template/FoundationModels derleyicileri, `EnemyAI/` (GameplayKit) |
| `fermansim` | `Tools/fermansim` | FermanCore, FermanContent | ✅ | `run` · `verify` · `batch` · `bench` · `validate-content` · `gen-tables` |
| Uygulama | `App/Ferman.xcodeproj` (F1.1, D3) | tüm paketler | — | Features, Rendering, Services, DesignSystem |

**Kurallar**
1. **Bağımlılık yönü:** Oklar yalnızca aşağı, `FermanCore`'a doğru gider. `FermanCore` hiçbir iç modülü bilmez.
2. **İzinli framework'ler:**

   | Modül | İzinli |
   |---|---|
   | FermanCore, FermanContent, FermanReplay | Yalnızca Foundation |
   | FermanAI | Foundation; ayrıca FoundationModels ve GameplayKit (yalnızca belirlenmiş dosya ve klasörlerde, madde 4) |
   | Uygulama | Apple framework'leri |

3. **Paketlerdeki tipler:** Dışa açık tipler `Sendable` değer tipleridir. Paketler varsayılan olarak nonisolated çalışır.
4. **Framework yeri:**
   - `import FoundationModels` yalnızca `FermanAI/Sources/FermanAI/FoundationModelsCompiler.swift` ve onun test dosyasında bulunur.
   - `import GameplayKit` yalnızca `FermanAI/Sources/FermanAI/EnemyAI/` klasöründe bulunur (D6).
5. **Üçüncü parti:** Faz 5'e kadar yok. Faz 5'te yalnızca Google Mobile Ads eklenir: `App/Ferman/Services/Monetization/AdMobProvider.swift` dosyasında, protokol arkasında.

### Paket ayarları (tüm paketler)
- `swift-tools-version` 6.2+ (Xcode 27 toolchain: Swift 6.4); platformlar `.iOS("27.0")`, `.macOS("27.0")`.
- Swift 6 dil modu; `ExistentialAny` upcoming feature.
- Uyarılar hata olarak ele alınır.
- `FermanCore`'da ek olarak `strictMemorySafety()` açıktır. Sıcak döngülerde `Unsafe*Pointer` yerine `Span`/`MutableSpan`/`InlineArray` kullanılır.

---

## 3. FermanCore

```
Sources/FermanCore/
├── Determinism/   DeterministicRNG · Fixed (+ FixedSquared) · FixedVector2 · FixedAngle · FixedMath (+ FixedMathTables, üretilmiş) · FNV1a64
├── Model/         UnitTypeID · UnitID · Team · Terrain · UnitType · Ability · UnitPlacement · TeamSetup
│                  BattleMap · UnitState · BattleState · SimulationTuning · BattleObjective · ConstraintCard
├── Rules/         Condition · ConditionKind · Action · ActionKind · Rule · RuleProgram
│                  RuleConstraints · RuleValidator · RuleEvaluator
├── Simulation/    BattleConfig · SimulationOptions · BattleSimulator · SpatialGrid · FlowField
│                  Steering · Combat · Morale · Abilities · Outcome
└── Output/        BattleEvent · BattleResult · RuleFireCounts · BattleOutcome · EndReason
```

- **Giriş noktası:** `BattleSimulator.run(_ config: BattleConfig, options: SimulationOptions = .init()) -> BattleResult`.
- **Tick hattı:** Sabit 30 Hz, faz sırası ve kesin anlamları [`FERMAN-PLAN.md` §5](FERMAN-PLAN.md#5-simülasyon-semantiği).
- **Durum yerleşimi:** Birim durumları `UnitID` sırasında bitişik dizilerde tutulur. Steering için iki tampon vardır (önceki ve yeni, D10). Tüm tamponlar koşum başında bir kez ayrılır; tick döngüsünde tahsis yapılmaz.
- **Mekânsal sorgular:** `SpatialGrid` her tick yeniden kurulur. Komşu aramaları O(n²) değildir.
- **Batch hızı:** `recordEvents: false` ile olay kaydı kapanır; checksum yine hesaplanır.
- **Sürümleme:** `BattleConfig.simulationVersion`, simülasyon mantığı değişince artar. Altın dosyalar, arena kayıtları ve düello `matchData`'sı bu değeri taşır.
- **Birlik varsayımı:** Tüm çekirdek tipleri `Codable`, `Sendable` ve `Hashable`'dır (uygun olanlar). Codable şeması testle sabitlenir.

---

## 4. FermanContent

- **Kaynaklar:** `Resources/units.json`, `Resources/levels.json`, `Resources/maps/*.json`, `Resources/enemy-tactics.json`. Sayılar yalnızca tamsayıdır, haritalar ASCII satırlarıdır (D19).
- **`ContentCatalog`:** Kaynakları `Bundle.module` (ya da `fermansim validate-content --path` ile bir klasör) üzerinden yükler, doğrular ve `throws(ContentError)` ile hata verir.
  - Harita yapısı `BattleMap` başlatıcısında, birim sınırları ve katalog kuralları `UnitType.validateCatalog`'da (`FermanCore`) denetlenir; böylece indirilen arena config'leri içerik paketi olmadan da doğrulanır.
  - Seviyeler eklendiğinde (F1.12) çapraz referans denetimleri (seviye → harita/birim, referans çözüm) buraya eklenir.
- **`LevelDefinition`:** Harita, düşman ordusu ya da taktik referansı, bütçeler, `RuleConstraints`, kısıt kartları, hedef, seed ve referans çözüm programı.
- **`DifficultyTable`:** R(n), U(n), C(n), B(n), Bp(n) ve H(n) değerlerinin tamsayı tablosu. `pow` ile üretimi `fermansim` alt komutu yapar; runtime yalnızca tabloyu okur.
- **`contentVersion`:** İçerik değişince artar; arena kayıtları bunu da taşır.

---

## 5. FermanReplay

- **`ReplayTimeline`**
  - `BattleResult.events`'i tick'e göre indeksler.
  - Olayları katlayarak (fold) 30 tick'te bir keyframe üretir.
  - `frame(at tick: Double) -> ReplayFrame` konumları iki örnek arasında interpole eder.
  - Seek işlemi en yakın keyframe'den ileri katlamadır. Doğruluk testi: seek sonucu, baştan katlamayla aynı olmalı.
- **`ReplayFrame`:** Birim başına konum, yön, hp oranı, moral durumu, aktif kural indeksi ve o anki kıvılcım olayları. Yalnızca çizim için gerekenleri taşır.
  - *Faz 1'deki gerçek durum:* `frame(at: Int32)` tamsayı tick'te çalışır; yön ve hp oranı taşınmaz, interpolasyon uygulamadadır. Faz 1.5 (G2) `frame(at:)`'in yalnızca anahtar kare aralığındaki olayları katlamasını sağlar.
- **`UnitTrack`** (Faz 1.5, G7 — D27): Birim başına tick sıralı olay indeksi — saldırılar (saldıran/hedef/hasar), ölüm tick'i, moral pencereleri, yetenek pencereleri, birikimli hp. İkili aramayla sorgulanır; çizim tarafı pozları (`FigurePose`) bundan replay zamanının saf fonksiyonu olarak türetir.
- **`DebriefAnalyzer`:** `BattleResult` + `BattleConfig` alır, öncelik sırasına dizilmiş `[DebriefInsight]` döndürür.
  - Tip bazında ölüm kümeleri: "Okçularının %70'i 12. saniyede aynı anda öldü."
  - Hiç çalışmayan kurallar ve baskın kural: "Okçular hep birinci emri uyguladı."
  - Eşzamanlı aktivasyon: "Hepsi aynı anda geri çekildi."
  - Hat bütünlüğü: "Hat 60 saniye boyunca hiç kırılmadı."
  - Kilit an (klip penceresi): 5 sn içinde en yoğun ölüm ve tetiklenme.
- **Metinleştirme:** Insight'lar yalnızca veri taşır. Cümleler uygulamadaki String Catalog ve `OrderPhraseFormatter` ile kurulur.

---

## 6. FermanAI

```
Sources/FermanAI/
├── RuleCompiler.swift              protocol RuleCompiler<Input>, CompileContext, RuleCompileError
├── RuleDraft.swift                 seçici durumu (koşul türü, parametre, eylem türü, parametre)
├── ManualCompiler.swift            RuleDraft → [Rule]
├── TemplateCompiler.swift          String → [Rule] (TR/EN anahtar kelime, ek normalizasyonu)
├── FoundationModelsCompiler.swift  String → [Rule] (tek FoundationModels dosyası)
├── CompilerChain.swift             FM → zaman aşımı/uygunsuzluk → Template
└── EnemyAI/                        GameplayKit yalnızca burada (D6)
    ├── EnemyTacticTree.swift       GKDecisionTree → EnemyTactic
    ├── EnemyStrategist.swift       GKMonteCarloStrategist → EnemyArmyPlan
    └── PlayerProfile.swift         Sendable girdi: son kazanan ordular/programlar
```

### Derleyici hattı (D17, D18)
```
metin ──► CompilerChain
            ├─ FoundationModelsCompiler
            │    availability + supportsLocale? ──hayır──► TemplateCompiler
            │    tokenCount(for:) < min(800, contextSize)?
            │    yeni LanguageModelSession(instructions: locale cümlesi + görev)
            │    DynamicGenerationSchema (yalnızca açık koşul/eylem)
            │    respond(…, options: .init(sampling: .greedy))  ── 2 sn yarışı ──► zaman aşımı ► Template
            └─► [Rule] ──► RuleValidator ──► UI'da pusula olarak gösterilir ──► oyuncu onaylar/düzeltir
```

### GameplayKit izolasyonu (D6, D13)
- Dışa açık API şu biçimdedir: `@concurrent func makeArmyPlan(_ request: StrategistRequest) async -> EnemyArmyPlan`. Her iki tip de `Sendable` struct'tır.
- `GKGameModel`, `GKGameModelPlayer` ve `GKGameModelUpdate` sınıfları `internal`'dır ve fonksiyonun yerel kapsamında oluşturulup yok edilir. Sınır dışına referans çıkmaz.
- Rollout değerlendirmesi `BattleSimulator.run(_:options: .init(recordEvents: false))` ile yapılır.
- Rastgelelik tohumlu `GKMersenneTwisterRandomSource` ile sağlanır; süre ve rollout bütçesi vardır.
- Çıktı `BattleConfig.enemy` alanına yazılır ve denemeyle birlikte saklanır.

---

## 7. Uygulama katmanı

```
App/Ferman/
├── FermanApp.swift              App, ModelContainer, AppDependencies, Transaction.updates dinleyicisi
├── AppRouter.swift              @Observable, [Route] yığını + sheet durumu
├── Features/
│   ├── Home/        HomeView · HomeModel
│   ├── Campaign/    CampaignView · CampaignModel · LevelSheet
│   ├── ArmySetup/   ArmySetupView · ArmySetupModel
│   ├── RuleEditor/  RuleEditorView · RuleEditorModel · RulePickerSheet · OrderPhraseFormatter
│   ├── Battle/      BattleView · BattleModel · BattleHUD
│   ├── Debrief/     DebriefView · DebriefModel
│   ├── Arena/       ArenaView · ArenaModel · DuelView · DuelModel
│   ├── Library/     LibraryView · LibraryModel
│   └── Settings/    SettingsView · SettingsModel
├── Rendering/       BattleScene · UnitNode · ReplayClock · ClipRenderer · BoardProjection (D26) · TerrainBaker · FigurePose (D27)
├── Services/
│   ├── BattleRunner.swift        @concurrent simülasyon koşucusu
│   ├── ProgressStore.swift       SwiftData (VersionedSchema, MigrationPlan)
│   ├── GameCenterService.swift
│   ├── ArenaService.swift        CloudKit public DB + önbellek + doğrulama
│   ├── DuelService.swift         GKTurnBasedMatch
│   ├── SpeechInputService.swift  SpeechAnalyzer
│   ├── AudioService.swift        SFX, AVAudioSession.ambient
│   └── Monetization/             EntitlementStore · RewardedAdProvider · NoopAdProvider · AdMobProvider (Faz 5)
├── DesignSystem/    Tokens (Color/Font/Spacing/Radius/Shadow) · Components · Shaders (.metal) · UnitArt (D24)
└── Resources/       Assets.xcassets · Localizable.xcstrings · Fonts/ · PrivacyInfo.xcprivacy · Sounds/
```

### Feature deseni (D12)
```swift
@Observable
final class RuleEditorModel {                 // app target varsayılan olarak MainActor
    private(set) var stacks: [UnitTypeID: [EditableRule]]
    private(set) var remainingBudget: Int
    var selectedUnitType: UnitTypeID

    private let compiler: any RuleCompiler<RuleDraft>
    private let progress: any ProgressStoring

    init(level: LevelDefinition, army: ArmyDraft, compiler: any RuleCompiler<RuleDraft>, progress: any ProgressStoring) { … }

    func move(_ difference: ReorderDifference<EditableRule.ID, ReorderableSingleCollectionIdentifier>) { … }
    func add(_ draft: RuleDraft) async { … }
}

struct RuleEditorView: View {
    @State var model: RuleEditorModel
    var body: some View { … }                 // yalnızca model state'ini çizer ve niyet metotlarını çağırır
}
```
- **Dependency injection:**
  - `AppDependencies` protokol tipli servisleri toplar ve `@Entry var dependencies` ile environment'a konur.
  - Modeller oluşturulurken bağımlılıkları init ile alır; view environment'tan okuyup modele verir.
  - Önizlemeler `PreviewModifier` ile sahte bağımlılık kullanır.
- **Navigasyon:**
  - `NavigationStack(path: $router.path)` + `navigationDestination(for: Route.self)`.
  - Savaş akışı `Campaign → ArmySetup → RuleEditor → Battle → Debrief` şeklindedir. "Emirleri Düzelt" RuleEditor'a aynı orduyla döner.
- **Hata gösterimi:** Typed hatalar kullanıcı metnine çevrilir ve `alert(error:actions:)` (iOS 27) ile gösterilir. Metinler yasak kelime içermez.
- **Concurrency (D13):** Model metotları MainActor'dadır. Simülasyon `BattleRunner.run(_:)` (`@concurrent`) ile koşar. Uzun işler görev iptalini (`Task.isCancelled`) dikkate alır.

---

## 8. Render hattı

- **`ReplayClock`** (`@Observable`): `tick: Double`, `speed ∈ {1, 2, 4}`, `isPaused`.
  - SpriteKit'in `update(_:)` zamanıyla ilerler.
  - Yeniden başlatma yalnızca `tick = 0` yapar, simülasyon tekrar koşmaz (< 100 ms).
- **`BattleScene: SKScene`**
  - Her karede `timeline.frame(at: clock.tick)` okur ve UnitID ile eşlenmiş node havuzunu günceller.
  - Kare başına tahsis yoktur; node'lar spawn'da oluşturulur. Ölen figür devrilir ve `fallen` pozuyla masada kalır (D27).
  - Kum masası ışığı `SKShader` (radyal düşüş); ızgara ve arazi `TerrainBaker`'ın harita başına bir kez pişirdiği texture'dır (SwiftUI Ordu Kurulumu da aynı görüntüyü kullanır).
  - Masa dikey çizilir, oyuncu altta (D26). Sim koordinatı ↔ görünüm noktası dönüşümü yalnızca `BoardProjection`'dadır.
  - Figürler `SKSpriteNode`, dokular tek atlastan (`UnitArt`, D24/D25). Pozlar `FigurePose` ile replay zamanından hesaplanır; durum tutan `SKAction` ve tohumsuz rastgelelik kullanılmaz, böylece seek, hız ve `ClipRenderer` aynı kareyi üretir (D27).
  - Kıvılcım: `ruleActivated` sonrasında figürün üstünde çakan bir sprite ve emir numarasını gösteren küçük bir mühür — yalnızca oyuncu birimleri için (D27). `SKEmitterNode` kullanılmaz: tohumsuz parçacıklar seek ve klipte aynı kareyi üretmez; kıvılcım da diğer her şey gibi zamanın saf fonksiyonudur (`FigureMotion`). Vuruş parlaması kâğıt rengidir, kıvılcım rengi değil.
  - Oklar: okçu saldırıları replay geleceği bildiği için uçuş süresi kadar önce fırlatılır ve `attack` tick'inde iner (`FigureMotion.arrows(atTick:)`, 64'lük havuz).
  - Dokunma: hit-test ile birim bulunur, `BattleModel`'e bildirilir, SwiftUI etiketi gösterilir ("şu an uyguluyor").
- **SwiftUI köprüsü**
  - `SpriteView(scene:preferredFramesPerSecond: 60)`.
  - Üst bar ve sayaç şeridi SwiftUI katmanındadır. Sayaç şeridi `ReplayTimeline.fireCounts(upTo:)` değerini 10 Hz'de örnekler; SwiftUI her karede geçersiz kılınmaz.
- **Liquid Glass:** Yalnızca üst bar ve alt sheet'lerde `glassEffect` kullanılır. Kum masası üzerinde okunabilirlik doğrulanır.
- **Koreografi (brief §3.5):** Damgalama sekansı 60 ms aralıkla `sensoryFeedback` ile oynar; dokununca hızlanır. Reduce Motion açıkken anında kesilir.
- **Performans ölçümü:** `OSSignposter` aralıkları (`frame`, `timelineSample`) Instruments'ta izlenir. Hedef: 150 birimde 60 fps.
- **Klip (D15):** `ClipRenderer` aynı `BattleScene`'i `SKRenderer` ile offscreen çizer ve `AVAssetWriter` ile HEVC 1080×1920 video üretir.

---

## 9. Kalıcılık ve senkron (D14)

- **Şema v1** (`FermanSchemaV1: VersionedSchema`):

  | Model | Alanlar |
  |---|---|
  | `LevelProgress` | `levelID`, `bestOutcome`, `attempts`, `winningArmy` (.codable), `winningPrograms` (.codable), `lastEnemyPlan` (.codable) |
  | `SavedOrderSet` | `name`, `tag`, `army` (.codable), `programs` (.codable), `usageCount`, `createdAt` |
  | `BattleRecord` | `levelID`, `config` (.codable), `outcome`, `checksum`, `createdAt` |
  | `CachedDefenseSet` (Faz 4) | CloudKit kaydının yerel kopyası |
  | `PendingAttackReport` (Faz 4) | Gönderilmeyi bekleyen rapor |

- **CloudKit uyumu:** Tüm özellikler opsiyonel ya da varsayılan değerlidir; `@Attribute(.unique)` yoktur; ilişkiler opsiyoneldir.
- **Senkron:** `ModelConfiguration(cloudKitDatabase: .private(…))` ile açılır (F4.2).
- **`ProgressStore`:** `ProgressStoring` protokolünü uygular. Modeller liste değişikliklerini iOS 27 `ResultsObserver` ile izler.
- **Göç:** Şema değişikliği yeni `VersionedSchema` + `MigrationStage` gerektirir. Göç testleri in-memory container ile koşar.
- **Tarih alanları:** `Date` alanları yalnızca uygulama katmanındadır; çekirdeğe girmez.

---

## 10. Sosyal katman (D5)

### Game Center
- **`GameCenterService`:** `GKLocalPlayer.local.authenticateHandler` ve access point.
- **Liderlik tabloları:** kampanya ilerlemesi, arena savunma puanı, haftalık arena.
- **Etkileşim:** ~30 başarım; `GKGameActivity` ve Challenges, Xcode'daki GameKit configuration file ile tanımlanır.

### Hayalet Arena (CloudKit public DB)
```
Savunma yayınla:  SavedOrderSet ─► DefenseSet{playerRef, army, programs, simVersion, contentVersion, weekKey, rating}
Saldır:           query(rating bandı, weekKey) ─► CachedDefenseSet (SwiftData) ─► BattleConfig(seed yeni)
                  ─► BattleSimulator (saldıran cihaz) ─► AttackReport{defenseRef, attacker army/programs, seed,
                     outcome, checksum, simVersion} ─► çevrimdışıysa PendingAttackReport kuyruğu
Doğrula:          savunan cihaz raporları çeker ─► config'i yeniden kurar ─► BattleSimulator ─► checksum eşleşmesi
                  ─► eşleşen raporlar savunma siciline işlenir ─► Game Center skoru
```
- **Güvenlik rolleri:** Kayıtları yalnızca oluşturan yazabilir; herkes okuyabilir.
- **Sürüm uyuşmazlığı:** `simulationVersion` farklıysa rapor doğrulanamaz; sayılmaz ve "eski sürüm" olarak gösterilir.
- **Ağ izleme:** `NWPathMonitor` bağlantı gelince bekleyen raporları gönderir.

### Dost Düellosu (GKTurnBasedMatch)
- **Davet:** Game Center arkadaşı veya Mesajlar üzerinden.
- **`matchData`:** Sürümlü JSON; iki tarafın ordu ve programları, tur sonuçları, seed'ler ve checksum'lar.
- **Tur akışı:** Her turda sıradaki oyuncu kendi cihazında simüle eder; karşı taraf sıra kendisine geldiğinde doğrular.
- **Maç sonu:** 3 tur sonunda `participant.matchOutcome` ayarlanır.
- **Olaylar:** `GKLocalPlayerListener` üzerinden işlenir.

---

## 11. Monetizasyon izolasyonu (Faz 5)

- **`EntitlementStore`** (`@Observable`)
  - `Transaction.currentEntitlements` ile başlar, `Transaction.updates` dinleyicisi app açılışında başlatılır. Sunucu yoktur.
  - Mağaza görünümleri `SubscriptionStoreView` ve `ProductView`, token'larla stillenir.
- **Reklam sağlayıcıları**
  - Uygulama yalnızca `RewardedAdProvider` protokolünü görür. `NoopAdProvider` varsayılandır; `AdMobProvider` tek dosyadadır.
  - Rıza sırası: UMP → ATT.
- **Değişmez:** Satın alımlar kural bütçesini (R(n)) değiştiremez. `RuleConstraints` hesaplamasında hak durumu girdisi yoktur; bir test bunu doğrular.

---

## 12. Gözlem ve gizlilik

- **Gözlem**
  - Loglama: `Logger(subsystem: "com.hksimsek.FERMAN", category: …)`. Kişisel veri loglanmaz.
  - Performans ve çökme tanılama: `OSSignposter` ve MetricKit (`MXMetricManager`).
- **Telemetri**
  - Beta dönemi: derleme düzeltmeleri cihazda tutulur, kullanıcı isterse paylaşım menüsüyle dışa aktarılır.
  - Tutma oranı ölçümü: App Store Connect App Analytics.
- **Gizlilik**
  - `PrivacyInfo.xcprivacy` required-reason API'lerini bildirir.
  - İzin metinleri: mikrofon ve konuşma (Faz 2), izleme (Faz 5, ATT).

---

## 13. Güncel API seçimleri (iOS 27 SDK)

| İhtiyaç | Seçilen API | Kullanılmayan |
|---|---|---|
| Durum yönetimi | `@Observable`, `@State` (Xcode 27 makro), `@Entry` | `ObservableObject`, Combine |
| Navigasyon | `NavigationStack(path:)`, typed `Route` | `NavigationView` |
| Pusula sıralama | `reorderContainer(for:isEnabled:move:)` + `reorderable()` | Elle yazılmış `DragGesture` |
| Ordu yerleştirme | `draggable` / `dropDestination` + `Transferable` | `onDrag`/`NSItemProvider` |
| Hata uyarıları | `alert(error:actions:)` | `alert(isPresented:)` + ayrı state |
| Materyal | `glassEffect`, `buttonStyle(.glass)` (ölçülü) | Özel blur |
| Haptik | `sensoryFeedback` | `UIFeedbackGenerator` |
| 2D render | SpriteKit (`SKScene`, `SpriteView`, `SKShader`, `SKRenderer`) | GameplayKit `GKAgent`/`GKGridGraph` |
| Veri | SwiftData (`VersionedSchema`, `@Attribute(.codable)`, `ResultsObserver`) + CloudKit | Core Data, `GKSavedGame` |
| LLM | Foundation Models (`LanguageModelSession`, `@Generable`, `DynamicGenerationSchema`, `tokenCount(for:)`, `LanguageModel` protokolü) | Uzak API |
| Konuşma | `SpeechAnalyzer` + `SpeechTranscriber` | `SFSpeechRecognizer` |
| Klip | `SKRenderer` + `AVAssetWriter`, `ShareLink` | ReplayKit |
| Sosyal | GameKit (`GKGameActivity`, `GKChallengeDefinition`, `GKTurnBasedMatch`), CloudKit public DB | Özel sunucu |
| Satın alma | StoreKit 2 (`Transaction`, `SubscriptionStoreView`) | StoreKit 1 |
| Test | Swift Testing, XCUITest `performAccessibilityAudit()` | XCTest birim testleri |
| Concurrency | `@concurrent`, default MainActor isolation, typed throws | `DispatchQueue`, `@unchecked Sendable` |
| Yerelleştirme | String Catalog (`.xcstrings`) | `.strings` |

Bir API'yi kullanmadan önce Apple dokümantasyonundaki güncel durumu (erişilebilirlik sürümü, deprecation) kontrol et.

---

## 14. Değişmezlerin otomatik denetimi

| Değişmez | Denetim | Nerede |
|---|---|---|
| FermanCore yalnızca Foundation; `Float`/`Double`/`SIMD` yok | `InvariantTests` kaynak taraması | `swift test` (Linux + macOS) |
| Yasak API'ler (`Date()`, `.random`, `UUID()`, `TaskGroup`, `sin`/`cos`/`atan2`…) | `InvariantTests` | `swift test` |
| Determinizm | `fermansim verify --runs 1000` + altın dosyalar (arm64 = x86_64) | CI |
| FoundationModels import yeri | `Scripts/check-invariants.sh` | CI |
| GameplayKit import yeri | `Scripts/check-invariants.sh` | CI |
| `Package.resolved` boş (Faz 5'e kadar) | `Scripts/check-invariants.sh` | CI |
| Kullanıcı metninde yasak kelime | `BannedWordsTests` (xcstrings) + betik | App testleri + CI |
| Her seviye çözülebilir | `LevelSolvabilityTests` | `swift test` |
| R(n) satılamaz | `EntitlementIndependenceTests` | App testleri |
| Kapsam > %85 (FermanCore) | `swift test --enable-code-coverage` + eşik betiği | CI |
