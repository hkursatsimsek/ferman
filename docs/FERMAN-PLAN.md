# FERMAN — Geliştirme Planı (v2)

**Hedef:** iOS 27+, Swift 6.4 (Swift 6 dil modu), strict concurrency `complete`, Xcode 27
**Süre:** ~24,5 hafta (tam zamanlı tek geliştirici)
**Bu dosya:** Claude Code'un fazları sırayla yürütmesi için yazıldı. Her adımın ölçülebilir bir "bitti tanımı" vardır.

**İlgili dokümanlar**
- Kararlar ve gerekçeleri: [`DECISIONS.md`](DECISIONS.md) — metinde `D#` olarak anılır.
- Modüller, veri akışı, katmanlar: [`ARCHITECTURE.md`](ARCHITECTURE.md).
- Her oturumda geçerli kurallar: [`../CLAUDE.md`](../CLAUDE.md).

**v2'de değişenler (2026-09-16)**
- Hedef iOS 27 (D1), simülasyonda sabit noktalı sayılar (D2), Xcode projesi `App/` altında (D3).
- Tip sözleşmesi Codable ve determinizm açısından düzeltildi (§4). Kural sırası önceliktir (D7), koşul/eylem ilişkili değerli enum'lardır (D8).
- Simülasyonun kesin anlamı yazıldı (§5): tick hattı, koşullar, eylemler, moral, bitiş.
- Yol haritası ölçülebilir adımlara bölündü (§6: F0.1 … F7).
- Eklenenler: CI ve değişmez denetimleri, yerelleştirme ve Türkçe ek uyumu, erişilebilirlik temeli, öğretici seviyeler, replay/analiz paketi (D11), ikili arena (D5), tasarım açıkları (§10).

---

## 0. Ürün özeti (bağlam)

Oyuncu savaşta hiçbir birime dokunmaz. Savaştan önce birimlerinin davranış kurallarını yazar (doğal dille veya seçicilerle), sonra tamamen deterministik bir simülasyon çalışır. Savaş sonrası, her kuralın kaç kez tetiklendiği gösterilir — öğrenme buradan gelir.

---

## 1. GameplayKit'in yeri

Erken tasarım notlarında savaş simülasyonunun `GKRuleSystem`, `GKAgent2D` ve `GKGridGraph` üzerine kurulması öneriliyordu. **Bu karar geri alındı.**

| Sorun | Sonuç |
|---|---|
| `GKAgent`'ın yönlendirme matematiği kapalı kutu | Determinizm garanti edilemez |
| `GKGridGraph` A* uygulaması kapalı kutu | Aynı girdi için aynı yolun garantisi yok |
| GameplayKit `NSObject` mirası taşır | Swift 6 strict concurrency ile `@unchecked Sendable` sarmalayıcı gerekir |
| GameplayKit Foundation dışı bir bağımlılık | Simülasyon çekirdeği Linux/CI üzerinde headless koşamaz |
| Kural değerlendirme zaten basit | Sıralı koşul listesi. `GKRuleSystem`'in bulanık mantığı gereksiz |

**Kural (D6):**

```
FermanCore     →  saf Swift. Yalnızca Foundation. GameplayKit, SpriteKit, UIKit YOK.
FermanAI       →  GameplayKit YALNIZCA Sources/FermanAI/EnemyAI/ klasöründe (savaş öncesi düşman seçimi)
App            →  SwiftUI + SpriteKit
```

- **Seviye 11–25:** `EnemyTacticTree` (`GKDecisionTree`) oyuncu profiline göre düşman taktik arketipini seçer.
- **Seviye 26–40:** `EnemyStrategist` (`GKMonteCarloStrategist`) düşman kompozisyonunu ve konuşlanmasını arar; rollout'lar `BattleSimulator` ile değerlendirilir.
- Her ikisi de simülasyonun **dışındadır**. Çıktıları Sendable değer tipleridir ve `BattleConfig`'e yazılır; tekrar denemede aynı düşman gelir.
- Yol bulma, sürü davranışı ve kural değerlendirme elle yazılır: deterministik, CI'da test edilebilir, batch'te binlerce kez hızlı koşar.

---

## 2. Proje yapısı

SPM'de "workspace kökü Package.swift" kavramı yoktur. Her modül ayrı bir yerel pakettir; uygulama bunlara yerel paket referansıyla bağlanır.

```
FERMAN/
├── CLAUDE.md                          # her oturumda okunan kurallar
├── .swift-format                      # biçim kuralları (toolchain'deki swift format)
├── .github/workflows/                 # core.yml (F0.12), balance-nightly.yml (F3.9)
├── Scripts/
│   └── check-invariants.sh            # import yerleri, Package.resolved, yasak kelimeler
├── docs/
│   ├── FERMAN-PLAN.md                 # bu dosya
│   ├── ARCHITECTURE.md
│   ├── DECISIONS.md
│   ├── FERMAN-Design-Brief.md
│   └── design/                        # Claude Design teslimi
│
├── Packages/
│   ├── FermanCore/                    # saf Swift — simülasyon çekirdeği (Linux ✅)
│   │   ├── Sources/FermanCore/
│   │   │   ├── Determinism/           # DeterministicRNG · Fixed · FixedVector2 · FixedMath · FixedMathTables · FNV1a
│   │   │   ├── Model/                 # UnitType · BattleMap · Terrain · UnitPlacement · TeamSetup · UnitState · BattleState · SimulationTuning
│   │   │   ├── Rules/                 # Condition · Action · Rule · RuleProgram · RuleConstraints · RuleValidator · RuleEvaluator
│   │   │   ├── Simulation/            # BattleConfig · SimulationOptions · BattleSimulator · SpatialGrid · FlowField · Steering · Combat · Morale · Abilities
│   │   │   └── Output/                # BattleEvent · BattleResult · RuleFireCounts · BattleOutcome · EndReason
│   │   └── Tests/FermanCoreTests/
│   │       └── Resources/Golden/      # 5 altın savaş (config + beklenen checksum)
│   │
│   ├── FermanContent/                 # JSON içerik + yükleyici + doğrulayıcı (Linux ✅)
│   │   └── Sources/FermanContent/Resources/
│   │       ├── units.json
│   │       ├── levels.json
│   │       ├── enemy-tactics.json
│   │       └── maps/
│   │
│   ├── FermanReplay/                  # ReplayTimeline + DebriefAnalyzer (Linux ✅, D11)
│   │
│   └── FermanAI/                      # derleyiciler + düşman YZ (yalnızca Apple platformları)
│       └── Sources/FermanAI/
│           ├── RuleCompiler.swift
│           ├── RuleDraft.swift
│           ├── ManualCompiler.swift
│           ├── TemplateCompiler.swift
│           ├── FoundationModelsCompiler.swift   # tek FoundationModels dosyası
│           ├── CompilerChain.swift
│           └── EnemyAI/                          # GameplayKit yalnızca burada
│
├── Tools/
│   └── fermansim/                     # CLI: run · verify · batch · bench · validate-content · gen-tables
│
├── Balance/                           # denge matrisleri ve raporları
│
└── App/                               # F1.1'de oluşturulur (D3). O zamana kadar kökteki şablona dokunulmaz.
    ├── Ferman.xcodeproj
    └── Ferman/
        ├── FermanApp.swift
        ├── AppRouter.swift
        ├── Features/                  # Home · Campaign · ArmySetup · RuleEditor · Battle · Debrief · Arena · Library · Settings
        ├── Rendering/                 # BattleScene · UnitNode · ReplayClock · ClipRenderer
        ├── Services/                  # BattleRunner · ProgressStore · GameCenter · Arena · Duel · SpeechInput · Audio · Monetization
        ├── DesignSystem/              # token'lar, bileşenler, shader'lar
        └── Resources/                 # Assets.xcassets · Localizable.xcstrings · Fonts · PrivacyInfo.xcprivacy
```

Ayrıntılı katman sorumlulukları: [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## 3. Temel mimari kararlar

### 3.1 Simüle-sonra-oynat (sim-then-render)

Simülasyon savaş başlamadan **tamamına kadar** koşar ve bir olay akışı üretir. SpriteKit bu akışı oynatır.

```
BattleConfig → BattleSimulator.run() → BattleResult (birkaç ms)
                                            ↓
                          FermanReplay.ReplayTimeline → BattleScene (SpriteKit)
```

Kazanımlar:
- Anında yeniden başlatma (yeniden simüle etmeye gerek yok).
- Hız kontrolü (1×/2×/4×), seek ve geri sarma bedava.
- Render katmanı oyun mantığını hiç bilmez.
- Aynı simülatör denge testi için batch koşar; arena sonuçları yeniden simülasyonla doğrulanır (D5).

Bu mimari zorunludur. Simülasyonu render döngüsüne bağlama.

### 3.2 Determinizm sözleşmesi (D2)

Aynı `BattleConfig` + aynı seed = bit düzeyinde aynı `BattleResult`. Her zaman, her platformda (macOS arm64 = Linux x86_64).

**FermanCore içinde yasak:**

| Yasak | Yerine |
|---|---|
| `Float`, `Double`, `CGFloat`, `SIMD*` | `Fixed` (Q16.16, Int32) ve `FixedVector2` |
| `Date()`, `DispatchTime`, herhangi bir saat | Yalnızca `tick` sayacı |
| `Int.random`, `arc4random`, `SystemRandomNumberGenerator` | `DeterministicRNG` (xoshiro256**) |
| `hashValue`, `Hasher` ile mantık | Açık sıralama anahtarları (hash tohumu süreç başına rastgeledir) |
| `Dictionary` / `Set` üzerinde sıraya duyarlı iterasyon | Sıralı `Array` veya `.sorted()` |
| `sin`, `cos`, `atan2`, `sqrt`, `pow` | `FixedMath` tabloları ve tamsayı `isqrt` |
| `UUID()` çalışma zamanında | Deterministik ID sayacı |
| `TaskGroup`, `async let`, paralel `for` simülasyon içinde | Tek iş parçacığı |
| `@unchecked Sendable`, `nonisolated(unsafe)` | Değer tipleri |

Koşum düzeyinde paralellik serbesttir: birbirinden bağımsız simülasyonlar (`fermansim batch --jobs`, stratejist rollout'ları) aynı anda koşabilir (D13). Tek bir koşum her zaman tek iş parçacığıdır.

Bu yasaklar `InvariantTests` ve `Scripts/check-invariants.sh` ile otomatik denetlenir (§7).

### 3.3 LLM disiplini

```
╔════════════════════════════════════════════════════════╗
║  Dil modeli ASLA oyun sonucunu belirlemez.             ║
║                                                        ║
║  Yapabileceği tek şey: metni [Rule] dizisine çevirmek. ║
║  Ürettiği her kural RuleValidator'dan geçer, oyuncuya  ║
║  gösterilir; oyuncu onaylamadan savaş başlamaz.        ║
╚════════════════════════════════════════════════════════╝
```

`RuleCompiler<Input>` bir protokoldür (D18). Uygulamanın tamamı `ManualCompiler` (seçici tabanlı, `Input = RuleDraft`) ile oynanabilir olmalıdır. `TemplateCompiler` ve `FoundationModelsCompiler` metin girdisi alır; LLM katmanı bir kolaylıktır, bağımlılık değil. Foundation Models kullanım deseni: D17.

### 3.4 Karar özeti

| Konu | Karar |
|---|---|
| Platform | iOS 27+ (D1) |
| Sayılar | Q16.16 sabit nokta (D2) |
| Kural önceliği | Dizi sırası (D7); ordu geneli bütçe R(n) (D4) |
| Kural değerlendirme | 5 Hz kademeli, kenar tetik sayım, bağlılık histerezisi (D9) |
| Eşzamanlılık | Çift tampon steering, toplu hasar (D10) |
| Replay ve analiz | `FermanReplay` paketi (D11) |
| Uygulama deseni | `XView` + `@Observable XModel`, router, DI (D12); concurrency (D13) |
| Kalıcılık | SwiftData + CloudKit private (D14) |
| Arena | CloudKit hayalet arena + GKTurnBasedMatch düello + çevrimdışı önbellek (D5) |
| Klip | `SKRenderer` + `AVAssetWriter` (D15) |
| Ses girişi | `SpeechAnalyzer` (D16) |
| İçerik | Tamsayı birimler, ASCII haritalar (D19) |
| Araçlar | Swift Testing, `swift format`, GitHub Actions + Xcode Cloud (D20) |
| Dil | String Catalog, Türkçe ek uyumu (D21); v1 karanlık mod (D22) |

---

## 4. Temel tipler (sözleşme)

Bu imzalar bağlayıcıdır ve F0.4'te yazılır; Faz 1'e geçmeden dondurulur. Değişiklik `simulationVersion` artışı ve DECISIONS kaydı gerektirir.

Tüm tipler `Sendable` değer tipleridir; uygun olanlar `Codable` ve `Hashable`'dır. Codable şeması testle sabitlenir.

```swift
// ───────────── Determinism ─────────────

public struct DeterministicRNG: Sendable, Codable, Hashable {
    public init(seed: UInt64)                                   // SplitMix64 ile 4 kelimelik durum
    public mutating func next() -> UInt64                       // xoshiro256**
    public mutating func int(in range: ClosedRange<Int>) -> Int // Lemire, sapmasız
    public mutating func fixedUnit() -> Fixed                   // [0, 1)
}

public struct Fixed: Sendable, Codable, Hashable, Comparable, AdditiveArithmetic {
    public var raw: Int32                                       // Q16.16
    // * ve / Int64 ara değerle; yuvarlama sıfırdan uzağa en yakın (işarete simetrik).
    // Taşma trap eder; girdi aralıklarını doğrulayıcılar sınırlar.
}

public struct FixedVector2: Sendable, Codable, Hashable { public var x: Fixed; public var y: Fixed }

public enum FixedMath {
    public static func sin(_ angle: FixedAngle) -> Fixed        // 4096 girişli tablo
    public static func cos(_ angle: FixedAngle) -> Fixed
    public static func atan2(y: Fixed, x: Fixed) -> FixedAngle  // oktant + tablo
    public static func isqrt(_ value: UInt64) -> UInt64
}

// ───────────── Model ─────────────

public struct UnitTypeID: RawRepresentable, Hashable, Comparable, Codable, Sendable { public let rawValue: String }  // JSON: "okcu"; sıralama UTF-8 bayt
public struct UnitID: RawRepresentable, Hashable, Comparable, Codable, Sendable { public let rawValue: UInt32 }  // yerleşim sırası
public enum Team: String, Codable, Sendable { case player, enemy }                   // JSON'da okunur ad; bellekte yine 1 bayt
public enum Terrain: String, Codable, Sendable { case open, forest, hill, water, rubble }  // ASCII: . F H W R

public struct UnitType: Codable, Sendable, Hashable {
    public let id: UnitTypeID                // görünen ad yok → App String Catalog "unit.<id>" (D19)
    public let cost: Int
    public let maxHP: Int
    public let speedMilliCellsPerSecond: Int
    public let rangeMilliCells: Int
    public let damage: Int
    public let attackIntervalTicks: Int
    public let armor: Int
    public let moraleMax: Int
    public let counters: [UnitTypeID]        // %150 hasar verdiği tipler
    public let ability: Ability
}

public struct BattleMap: Codable, Sendable, Hashable {  // var olan her harita yapısal olarak geçerlidir (throws(BattleMapError))
    public let width: Int, height: Int       // en fazla 128 × 128
    public let terrain: [Terrain]            // satır öncelikli, width × height
    public let playerZone: [Int]             // yerleştirilebilir hücre indeksleri, kesin artan
    public let enemyZone: [Int]
    // JSON: { "terrain": ["..FF", "..HH"], "zones": ["P..E", "P..E"] }  — P oyuncu, E düşman, . yok
}

public struct UnitPlacement: Codable, Sendable, Hashable {
    public let type: UnitTypeID
    public let cell: Int
    public let isCommander: Bool             // takım başına en fazla bir
}

public struct TeamSetup: Codable, Sendable, Hashable {
    public let placements: [UnitPlacement]
    public let programs: [RuleProgram]       // unitType'a göre sıralı
}

// ───────────── Rules ─────────────

public enum Condition: Codable, Sendable, Hashable {
    case enemyWithin(cells: Int)             // 1–10
    case healthBelow(percent: Int)           // 10–90
    case allyCountBelow(count: Int)          // 1–10
    case isFlanked
    case targetInRange(UnitTypeID)
    case timeAfter(seconds: Int)             // 1–60
    case nearestEnemyType(UnitTypeID)
    case moraleBelow(percent: Int)           // 10–90
    case terrainIs(Terrain)
    case commanderDead
    case enemyDensityAbove(count: Int)       // 2–8
    case always                              // varsayılan pusula
}

public enum Action: Codable, Sendable, Hashable {
    case advance, retreat, hold
    case focusFire(UnitTypeID?)
    case flankLeft, flankRight, regroup, useAbility, takeCover, guardCommander, scatter
}

public enum ConditionKind: String, CaseIterable, Codable, Sendable { …; var parameter: ConditionParameter }  // UI/LLM aynası; aralıklar §5.3
public enum ActionKind: String, CaseIterable, Codable, Sendable { …; var parameter: ActionParameter }
// Condition/Action JSON'u ayrık birleşimdir: {"kind": "enemyWithin", "cells": 3}, {"kind": "focusFire", "unitType": "okcu"}

public struct Rule: Codable, Sendable, Hashable {       // id yok; UI kimliği App'teki EditableRule'da (D7)
    public var condition: Condition
    public var action: Action
}

public struct RuleProgram: Codable, Sendable, Hashable {
    public let unitType: UnitTypeID
    public var rules: [Rule]                 // sıra = öncelik; son kural her zaman .always
}

public struct RuleConstraints: Codable, Sendable, Hashable {
    public let maxRules: Int                 // ordu geneli, varsayılan pusula sayılmaz (D4)
    public let availableConditions: [ConditionKind]
    public let availableActions: [ActionKind]
}

public enum RuleValidator {
    public static func validate(_ programs: [RuleProgram], constraints: RuleConstraints,
                                catalog: [UnitType]) throws(RuleValidationError)
}

// ───────────── Simulation ─────────────

public struct BattleConfig: Codable, Sendable, Hashable {
    public let simulationVersion: Int
    public let map: BattleMap
    public let unitCatalog: [UnitType]       // id'ye göre sıralı
    public let tuning: SimulationTuning
    public let player: TeamSetup
    public let enemy: TeamSetup
    public let objective: BattleObjective    // eliminate | holdLine
    public let constraints: RuleConstraints
    public let seed: UInt64
    public let maxTicks: Int                 // varsayılan 1800 = 60 sn @ 30 Hz
}

public struct SimulationOptions: Sendable { public var recordEvents: Bool = true }

public struct BattleEvent: Codable, Sendable, Hashable {
    public let tick: Int32
    public let kind: Kind
    public enum Kind: Codable, Sendable, Hashable {
        case spawn(UnitID, UnitTypeID, Team, FixedVector2)
        case move(UnitID, FixedVector2)
        case ruleActivated(UnitID, ruleIndex: Int)
        case attack(UnitID, target: UnitID, damage: Int)
        case abilityUsed(UnitID, Ability)
        case death(UnitID)
        case moraleBroken(UnitID)
        case moraleRecovered(UnitID)
        case battleEnded(BattleOutcome, EndReason)
    }
}

public enum BattleOutcome: String, Codable, Sendable { case playerWin, enemyWin, draw }
public enum EndReason: String, Codable, Sendable { case elimination, rout, timeLimit }

public struct RuleFireCounts: Codable, Sendable, Hashable {
    public let team: Team
    public let unitType: UnitTypeID
    public let counts: [Int]                 // pusula indeksine göre
}

public struct BattleResult: Codable, Sendable, Hashable {
    public let outcome: BattleOutcome
    public let endReason: EndReason
    public let tickCount: Int
    public let events: [BattleEvent]         // recordEvents: false ise boş
    public let ruleFireCounts: [RuleFireCounts]
    public let survivorsPlayer: Int
    public let survivorsEnemy: Int
    public let checksum: UInt64
}

public enum BattleSimulator {
    public static func run(_ config: BattleConfig, options: SimulationOptions = .init()) -> BattleResult
}

// ───────────── AI (FermanAI) ─────────────

public protocol RuleCompiler<Input>: Sendable {
    associatedtype Input: Sendable
    func compile(_ input: Input, context: CompileContext) async throws(RuleCompileError) -> [Rule]
}

public struct CompileContext: Sendable {
    public let unitType: UnitTypeID
    public let constraints: RuleConstraints
    public let availableUnitTypes: [UnitTypeID]
    public let remainingRuleBudget: Int      // tüm programlardan hesaplanır (D4)
}
```

---

## 5. Simülasyon semantiği

Bu bölüm simülasyonun kesin anlamıdır. Kod bununla çelişirse ya kod düzeltilir ya da bu bölüm, `simulationVersion` artışı ve gerekçeyle güncellenir.

### 5.1 Uzay ve zaman

- **Tick:** Sabit 30 Hz. `maxTicks` varsayılanı 1800 (60 sn); seviye değiştirebilir.
- **Koordinatlar:** Hücre biriminde `FixedVector2`. Hücre `(cx, cy)`'nin merkezi `(cx + ½, cy + ½)`. Hücre indeksi `cy × width + cx`.
- **Hız:** `speedMilliCellsPerSecond` tick başına `Fixed` hıza bir kez çevrilir.
- **Mesafe:** Karşılaştırmalar kare mesafe ile yapılır (karekök yok). Uzunluk gerektiğinde `isqrt`.
- **Eşitlik bozma:** Her yerde önce mesafe, sonra `UnitID` (D10).
- **Sabitler:** Aşağıdaki tüm sayılar `SimulationTuning` içindedir; config'e dahildir ve F0.13 dengesiyle ayarlanır.

### 5.2 Tick hattı

Her tick şu fazlardan sırayla geçer:

1. **Flow field** (15 tick'te bir): Takım başına çok kaynaklı Dijkstra; kaynaklar canlı düşman birimlerinin bulunduğu hücreler.
   - Tamsayı hücre maliyetleri: open 10, hill 20, rubble 20, forest 30, water geçilmez.
   - İkili yığın; eşit maliyette küçük hücre indeksi önce.
2. **SpatialGrid:** Her tick yeniden kurulur. 2×2 hücrelik kovalar, kova içinde `UnitID` sırası. Komşu aramaları O(n²) değildir.
3. **Karar** (D9):
   - Birim `unitID % 6 == tick % 6` olan tick'lerde kurallarını değerlendirir (30 Hz'de 5 Hz, yük dağıtılmış).
   - Programın ilk eşleşen kuralı seçilir; hiçbiri eşleşmezse örtük davranış "ilerle ve dövüş"tür ve sayaca yazılmaz.
   - Seçili kural değiştiğinde `ruleActivated` olayı yayılır ve o kuralın sayacı 1 artar (kenar tetik).
   - Yeni seçilen kurala en az `minimumCommitTicks` (15) bağlı kalınır. Bu süreyi yalnızca daha yüksek öncelikli bir kuralın eşleşmesi keser.
   - Dağılmış (`moraleBroken`) birim karar vermez.
4. **Steering** (D10): Önceki tick durumundan okunur, yeni tampona yazılır.
   - Niyet (eylemden gelen seek / flee / waypoint / dur) + ayrışma + hizalanma + tutunma + akış takibi, ağırlıklı toplam.
   - Arazi hız çarpanı (`SimulationTuning`); hedef hücre su ya da harita dışıysa eksen bazında kayma, yoksa dur.
5. **Savaş:** Cooldown'lar düşer. Bu tick'in tüm saldırıları toplanır ve birlikte uygulanır.
   - Hasar: `max(1, damage × (counter ? 150 : 100) / 100 − armor)`.
   - Hedef forest veya rubble hücresindeyse menzilli hasar %30 azalır (tamsayı, aşağı yuvarlama).
   - Menzilli vuruş anlıktır; ok uçuşu yalnızca render işidir.
   - Yetenek etkileri bu fazda uygulanır (§5.5).
6. **Ölüm ve moral:** HP ≤ 0 olanlar fazın sonunda ölür.

   | Olay | Moral etkisi |
   |---|---|
   | 3 hücre içinde dost ölümü | −10 |
   | Takımın komutanı öldü (takım geneli, bir kez) | −25 |
   | Arkadan vuruluş (yön · saldırı yönü < 0) | −5 |
   | 4 hücre içinde düşman yokken | +1 / sn |

   Moral `moraleMax`'ın %20'sinin altına düşerse `moraleBroken`: birim 90 tick zorunlu dağılır (`scatter`), sonra moral %35'e toparlanır ve `moraleRecovered` yayılır.
7. **Olay ve checksum:**
   - `move` örneği 3 tick'te bir, yalnızca konumu değişmiş birimler için (10 Hz).
   - Checksum: FNV-1a 64, 30 tick'te bir ve son tick'te; `UnitID` sırasıyla tüm birimlerin ham alanları (konum, hız, hp, moral, cooldown, aktif kural, durum bayrakları) ve tick. `recordEvents: false` iken de hesaplanır.
8. **Bitiş kontrolü:**
   - Bir takımın canlı birimi kalmadıysa `elimination`; canlı birimlerinin tamamı dağılmışsa `rout`.
   - `maxTicks` dolarsa `timeLimit`:
     - `holdLine` hedefinde oyuncunun canlı birimi varsa oyuncu kazanır.
     - `eliminate` hedefinde kalan değer karşılaştırılır: Σ `cost × hp / maxHP` (tamsayı). Eşitse `draw`.
   - İki takım aynı tick'te biterse `draw`.

### 5.3 Koşullar

Sınır anlamları: *Below* = kesin küçük, *Above* = kesin büyük, *Within* = küçük ya da eşit. Mesafeler birim merkezleri arasında, hücre biriminde ölçülür.

| Koşul | Parametre | Anlam | TR metin önerisi |
|---|---|---|---|
| `enemyWithin` | kare 1–10 | Canlı bir düşman ≤ N kare mesafede | düşman N kareden yakınsa |
| `healthBelow` | % 10–90 | `hp × 100 < maxHP × N` | canım %N'in altındaysa |
| `allyCountBelow` | adet 1–10 | 3 kare içindeki canlı dost sayısı (kendisi hariç) < N | yanımda N'den az dost varsa |
| `isFlanked` | — | Son 30 tick içinde arkadan hasar almış | kuşatıldıysam |
| `targetInRange` | UnitTypeID | Kendi menzilinde T tipinde canlı düşman var | menzilimde T varsa |
| `timeAfter` | sn 1–60 | `tick ≥ N × 30` | N. saniyeden sonra |
| `nearestEnemyType` | UnitTypeID | En yakın canlı düşman T tipinde | en yakın düşman T ise |
| `moraleBelow` | % 10–90 | `morale × 100 < moraleMax × N` | moralim %N'in altındaysa |
| `terrainIs` | Terrain | Bulunduğu hücrenin arazisi | ormandaysam / tepedeysem … |
| `commanderDead` | — | Takımın komutanı ölü (komutan yoksa asla) | komutan düştüyse |
| `enemyDensityAbove` | adet 2–8 | 3 kare içindeki canlı düşman sayısı > N | yakınımda N'den fazla düşman varsa |
| `always` | — | Her zaman. Yalnızca programın sonunda, hak tüketmez (D4) | başka durumda |

### 5.4 Eylemler

| Eylem | TR | Anlam |
|---|---|---|
| `advance` | İLERLE | Akış alanını izle; menzildeki en yakın düşmana saldır |
| `retreat` | GERİ ÇEKİL | Akışın tersine git; saldırma |
| `hold` | YERİNDE KAL | Dur; menzildeki en yakın düşmana saldır |
| `focusFire(T?)` | YÜKLEN | Hedef: T tipinin en yakını; T yoksa ya da verilmediyse menzil + 2 içinde hp'si en düşük düşman; o da yoksa `advance` |
| `flankLeft` / `flankRight` | SOLDAN / SAĞDAN KUŞAT | En yakın düşmana göre takım ilerleme yönüne dik ±4 kare waypoint; varınca `advance` |
| `regroup` | TOPLAN | 6 kare içindeki aynı tipte dostların merkezine git; menzildekine saldır |
| `useAbility` | tipe özel | Tipin yeteneğini cooldown hazırsa kullan (§5.5), değilse `hold` |
| `takeCover` | SİPER AL | 5 kare içindeki en yakın forest/rubble hücresine git ve dur; yoksa `hold` |
| `guardCommander` | KOMUTANI KORU | Komutana ≤ 2 kare yaklaş, komutana en yakın düşmana saldır; komutan yoksa `hold` |
| `scatter` | DAĞIL | `DeterministicRNG` ile seçilen rastgele yönde kaç; saldırma |

**Komutan:** Takım başına en fazla bir `UnitPlacement.isCommander`, ordu kurulumunda seçilir. Komutanın ölümü §5.2 moral tablosunu ve `commanderDead` koşulunu tetikler.

### 5.5 Birimler ve yetenekler (F0.9'da sayılar kesinleşir)

| Birim | Rol | Yetenek | Etki |
|---|---|---|---|
| `mizrakci` (mızrakçı) | Süvariye karşı | Mızrak duvarı | Kısa süre durur; süvariden aldığı hasar yarıya iner, süvariye verdiği hasar artar |
| `okcu` (okçu) | Menzilli | Yaylım | Hedef hücre çevresindeki birimlere tek seferlik alan hasarı |
| `suvari` (süvari) | Hızlı, okçuya karşı | Hücum | Kısa süre hız artışı; ilk vuruşta ek hasar |
| `kalkan` (kalkanlı) | Tank | Kalkan duvarı | Kısa süre durur; menzilli hasar büyük ölçüde azalır |

Tüm yetenekler tick bazlı cooldown'ludur; sayılar `units.json` ve `SimulationTuning` içindedir.

### 5.6 Rastgelelik

- Tek bir `DeterministicRNG` config seed'iyle başlatılır ve tüm koşum boyunca **sabit sırayla** kullanılır: fazlar sırasıyla, faz içinde `UnitID` sırasıyla.
- Yalnızca `scatter` yönü ve eşitlik bozmada kalan beraberlikler RNG kullanır. Hasar rastgele değildir; kural etkisi okunabilir kalır.

---

## 6. Yol haritası

Her adımın bir çıktısı ve bitti tanımı vardır. Adım kimlikleri (`F0.1` …) commit mesajlarında ve dokümanlarda kullanılır. Fazın kabul kriterleri karşılanmadan sonraki faza geçilmez.

### FAZ 0 — Simülasyon çekirdeği ve CLI · **2,5 hafta**

UI yok. Xcode projesi yok. Yalnızca SPM paketleri ve komut satırı.

| Adım | Çıktı | Bitti tanımı |
|---|---|---|
| F0.1 | `Packages/FermanCore`, `Packages/FermanContent`, `Tools/fermansim` iskeleti: tools 6.2+, iOS/macOS 27, Swift 6 dil modu, `ExistentialAny`, Core'da `strictMemorySafety`, uyarılar hata. `.swift-format`. `InvariantTests` (Core'da yasak import/API/`Float`/`Double` taraması). `Scripts/check-invariants.sh` | macOS'ta `swift test` yeşil; kasıtlı ihlal testi kırıyor. Linux doğrulaması yerelde yapılmaz, F0.12 CI'ına bırakılır |
| F0.2 | `DeterministicRNG`: xoshiro256**, SplitMix64 tohumlama, Lemire `int(in:)`, `fixedUnit()`, Codable durum | Referans C uygulamasının vektörleriyle birebir |
| F0.3 | `Fixed`, `FixedVector2`, `FixedAngle` (turda 4096 birim), `isqrt`, yuvarlama/taşma politikası; `fermansim gen-tables` → çeyrek dalga sin tablosu (1025 giriş, diğer çeyrekler yansımayla; simetriler kurgu gereği tam) ve atan tablosu; tablo tabanlı `atan2` | Özellik testleri; tablo checksum'u sabit; `gen-tables --check` commit'teki dosyayla aynı |
| F0.4 | §4'teki tipler; `BattleMap` ASCII satır biçimi ve yapısal doğrulaması; `SimulationTuning` (§5 sabitleri) | JSON round-trip testleri; her koşul/eylem/olay için sabitlenmiş JSON; elle yazılmış config fixture'ı çözümleniyor |
| F0.5 | `units.json` (4 birim, tamsayı), iki ayna simetrik harita (`ova`, `gecit`), `ContentCatalog` (doğrulama `throws(ContentError)`; birim sınırları ve katalog kuralları arena config'leri için de gerektiğinden `FermanCore`'daki `UnitType.validateCatalog`'da), `fermansim validate-content` | Hatalı fixture'lar doğru typed hatayı veriyor; paketlenmiş haritalar iki takım için ayna simetrik |
| F0.6 | `SpatialGrid`, `FlowField` | Küçük haritalarda tablo testleri; mikro benchmark |
| F0.7 | `RuleEvaluator` (5 Hz, kenar tetik, histerezis), `RuleValidator` (ordu geneli bütçe) | `@Test(arguments:)` ile her koşul × (N−1, N, N+1) tablosu |
| F0.8 | `Steering` (çift tampon, arazi çarpanı, çarpışma) | Giriş sırası karıştırılınca checksum aynı; suya giren birim yok |
| F0.9 | `Combat`, `Morale`, yetenekler, komutan | Birim testleri; counter 1v1 senaryoları |
| F0.10 | `BattleSimulator.run`: tick hattı, bitiş/hedef, checksum, `recordEvents`, `ruleFireCounts` | Aynı config 1000× özdeş |
| F0.11 | `fermansim run` / `verify` / `batch` (`--jobs`) / `bench`; elle yazılmış argüman ayrıştırma | 24v24 × 1800 tick referansında 10k savaş `--jobs 1` ile < 60 sn; 150 birim stres raporu |
| F0.12 | 5 altın dosya (`FermanCoreTests/Resources/Golden/`); `.github/workflows/core.yml` — Linux: lint, test + kapsam eşiği, verify, değişmez betiği; macOS: aynı altın dosyalar | CI yeşil; arm64 ve x86_64 aynı checksum; kapsam > %85 |
| F0.13 | Denge sorusu: 6 zıt kural seti × eşleşmeler × 1000 seed | `Balance/phase0-report.md`: kurallar kazanma oranını ≥ 20 puan değiştiriyor mu? Değiştirmiyorsa tuning yapılır, UI'ya geçilmez |

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Determinizm | `fermansim verify --runs 1000` → 1000 özdeş checksum |
| Platformlar arası | Altın dosyalar macOS arm64 ve Linux x86_64'te aynı |
| Hız | 10.000 savaş < 60 saniye (M-serisi Mac, tek çekirdek) |
| Test kapsamı | `FermanCore` için > %85 satır kapsamı |
| Altın dosya | 5 referans savaş, sonuçları repoda saklı, CI'da karşılaştırılıyor |
| Bağımlılık | `FermanCore` yalnızca `Foundation` import ediyor; `InvariantTests` yeşil |

**Bu fazın sonunda cevaplanacak soru:** Elle yazılmış kural setleri farklı sonuçlar üretiyor mu? Yani kural yazmak simülasyonda gerçekten fark yaratıyor mu? Yaratmıyorsa denge parametreleri yanlıştır ve UI yazmadan önce düzeltilmelidir (F0.13).

---

### FAZ 1 — Dikey dilim · **5 hafta**

Xcode projesi, SwiftUI, SpriteKit. **LLM kodu bu fazda repoda bulunmaz.**

| Adım | Çıktı | Bitti tanımı |
|---|---|---|
| F1.1 | Kök şablonu kaldır; `App/Ferman.xcodeproj` oluştur: iOS 27, Swift 6, default MainActor, approachable concurrency, uyarılar hata, yerel paket referansları, bundle id `com.hksimsek.FERMAN`, `PrivacyInfo.xcprivacy`, String Catalog, `UIUserInterfaceStyle = Dark`, test planı (paket testleri dahil), Xcode Cloud PR iş akışı | iPhone 18 Pro (iOS 27) simülatöründe `xcodebuild test` yeşil |
| F1.2 | DesignSystem: Asset Catalog renk token'ları (Any/Dark), paketlenmiş fontlar (Archivo, Archivo Narrow, Public Sans + OFL), Dynamic Type için `Font.custom(_:size:relativeTo:)`, boşluk/radius/gölge token'ları. Bileşenler: `OrderCard` (6 durum), `OrderStack`, `ParameterDial`, `UnitToken`, `SandTable` shader, `TriggerBar`, `BudgetMeter`, `FrontFlag`, `BottomSheet`, `PrimaryButton`, outline/ghost/chip, `SpeedControl` | Her durum için `#Preview` (koyu/açık/XXL); `ImageRenderer` tabanlı snapshot referansları |
| F1.3 | `FermanReplay`: `ReplayTimeline` (30 tick keyframe, `frame(at:)`, seek, `fireCounts(upTo:)`), `DebriefAnalyzer` (ölüm kümeleri, hiç çalışmayan/baskın kural, eşzamanlı aktivasyon, hat bütünlüğü, kilit an) | Linux testleri; seek sonucu = baştan katlama |
| F1.4 | `BattleScene` (node havuzu, interpolasyon, `SKEmitterNode` kıvılcım, `SKShader` kum ışığı, dokunmayla birim etiketi), `ReplayClock`, `SpriteView`, `OSSignposter` | Referans cihazda 150 birim 60 fps; kare başına tahsis yok |
| F1.5 | `BattleView` / `BattleModel`: üst bar (ölçülü `glassEffect`), 10 Hz sayaç şeridi, 1×/2×/4×, duraklat, < 100 ms yeniden başlat, brief §3.5 koreografisi (atlanabilir, Reduce Motion), `BattleRunner` (`@concurrent`) | Akış testi; yeniden başlatma ölçümü |
| F1.6 | `FermanAI` iskeleti: `RuleCompiler<Input>`, `CompileContext`, `RuleDraft`, `ManualCompiler` | Testler; `FoundationModels` araması boş |
| F1.7 | `RuleEditorView` / `Model`: birim sekmeleri, `reorderContainer` + `reorderable()`, sabit varsayılan kart, yerinde kadran, seçicilerle ekleme sheet'i (koşul → parametre → eylem), ordu geneli sayaç, geçersiz kart durumu, boş durum, hazır setler, haptik + kâğıt sesi, VoiceOver tek öğe + taşımak için accessibility action, `OrderPhraseFormatter` | 0–100 ek tablosu testi; UI testi (ekle / sırala / düzenle); XXL |
| F1.8 | `ArmySetupView` / `Model`: `draggable` / `dropDestination` (`Transferable`), bütçe aşımı, komutan seçimi, Sis gösterimi | Model tarafında yerleştirme/bütçe testleri |
| F1.9 | `HomeView`, `CampaignView` + seviye sheet'i, `AppRouter` | Navigasyon UI testi |
| F1.10 | `DebriefView` / `Model`: yenilgi ve zafer, içgörü cümlesi, normalize çubuklar, "Bu emir hiç çalışmadı." | Model testleri; snapshot |
| F1.11 | `ProgressStore`: SwiftData v1 (`LevelProgress` + kazanan program, `SavedOrderSet`, `BattleRecord`), `SchemaMigrationPlan`, CloudKit uyumlu şema | In-memory container testleri |
| F1.12 | 8 seviye: 1–3 öğretici (varsayılan emir → tek koşul → sıralama); her seviyeye referans çözüm | `LevelSolvabilityTests` (Linux): referans kazanır; seviye ≥ 2'de yalnız varsayılan emirle kazanılmaz |
| F1.13 | Yerelleştirme ve erişilebilirlik temeli: tüm metinler katalogda, `BannedWordsTests` (xcstrings), VoiceOver çekirdek akış, XXL, Reduce Motion, SFX (`AVAudioSession.ambient`) | `performAccessibilityAudit()` yeşil |
| F1.14 | Kabul ve **KARAR NOKTASI**: Instruments ölçümü, `Package.resolved` boş, en az 5 kişiyle 10 dakikalık playtest | `docs/playtests/phase1.md` ve devam/dur kararı |

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| 8 seviye baştan sona oynanabilir | Manuel test + `LevelSolvabilityTests` |
| LLM bağımlılığı yok | `grep -rI "FoundationModels" App/ Packages/` → boş |
| 3rd party bağımlılık yok | `Package.resolved` boş (`Scripts/check-invariants.sh`) |
| 150 birimde 60 fps | Instruments, referans cihaz |
| Yeniden başlatma < 100 ms | Simülasyon zaten önceden koşuyor |
| Erişilebilirlik temeli | `performAccessibilityAudit()` yeşil, XXL'de kırpılma yok |

> ### 🚦 KARAR NOKTASI
>
> Bu fazın sonunda dikey dilim **LLM olmadan, sadece seçicilerle 10 dakika eğlenceli olmalı.**
>
> Eğlenceli değilse doğal dil katmanı bunu kurtarmaz — sadece kural yazmayı hızlandırır. Projenin üzerinde durduğu tek varsayım budur. Burada durup mekanik değiştirmek, devam etmekten çok daha ucuzdur.

---

### FAZ 2 — Doğal dil derleyici · **2 hafta**

| Adım | Çıktı | Bitti tanımı |
|---|---|---|
| F2.1 | `TemplateCompiler`: TR/EN anahtar kelime, Türkçe ek normalizasyonu, sayı sözcükleri ("üç" → 3) | Doğruluk harness'ında taban çizgisi |
| F2.2 | `Tests/CompilerAccuracy/phrases.json` (150 etiketli TR + EN ifade, beklenen `[Rule]`), alan bazında rapor | Rapor üretiliyor |
| F2.3 | `FoundationModelsCompiler` (D17): availability + `supportsLocale`, durumsuz oturum, `@Generable` ayna tipler + `DynamicGenerationSchema`, greedy sampling, `tokenCount` < 800, `prewarm`, 2 sn → yedeğe düşüş, hata eşleme; testte iOS 27 `LanguageModel` protokolüyle sahte model | > %88 tam eşleşme; iPhone 16 sınıfında p95 < 2,5 sn; ayna case sayısı = `allCases` testi |
| F2.4 | Editörde doğal dil girişi + damgalama animasyonu + zorunlu onay/düzeltme | UI testi |
| F2.5 | `SpeechAnalyzer` / `SpeechTranscriber` (D16): tr/en, `AssetInventory`, izin metinleri | Cihazda, varlık yüklendikten sonra çevrimdışı çalışıyor |
| F2.6 | Apple Intelligence kapalıyken tam işlev | Manuel ve UI testi |

**Şema notu:** `@Generable` tipler çekirdek enum'larının aynasıdır ve yalnızca `FoundationModelsCompiler.swift` içinde tanımlanır. Seviyede kilitli koşul ve eylemler `DynamicGenerationSchema` ile şemadan çıkarılır; model geçersiz bir değer üretemez. Halüsinasyon "yanlış ama geçerli kural" olarak çıkar ve oyuncu düzeltir.

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Derleme doğruluğu | 150 ifadede > %88 tam eşleşme |
| Yedek düşüş | Apple Intelligence kapalı simülatörde oyun tam işlevsel |
| Gecikme | p95 < 2,5 saniye (iPhone 16) |
| Bağlam aşımı | Hiç oluşmuyor — her oturum < 800 token |

---

### FAZ 3 — Zorluk, düşman YZ ve Ayna · **4 hafta**

| Adım | Çıktı | Bitti tanımı |
|---|---|---|
| F3.1 | `DifficultyCurve` tabloları: formüller üretici araçta, runtime tamsayı tablo (D19) | Tablo testi |
| F3.2 | Kısıt kartlarının kesin tanımı ve etkisi. Öneri: **Sis** — düşman kompozisyonu gizli · **Körlük** — algı ≤ 3 kare · **Tek akıl** — tüm tipler tek program · **İnat** — 3 sn bağlılık · **Sessiz emir** — doğal dil yok, sayaç şeridi gizli · **Vekil** — düşmanın yazdığı silinemez üst kural | Simülasyon ve editör testleri |
| F3.3 | Harita tehlikesi H(n) tanımı ve haritalar | İçerik doğrulama |
| F3.4 | Elle yazılmış düşman taktik kütüphanesi (`RuleProgram` arketipleri) + seviye 1–10 | Çözülebilirlik testleri |
| F3.5 | `EnemyAI/EnemyTacticTree` (`GKDecisionTree`, seviye 11–25): oyuncu profili özellikleri → taktik arketipi → Sendable `EnemyTactic` | macOS testleri |
| F3.6 | `EnemyAI/EnemyStrategist` (`GKMonteCarloStrategist`, 26–40): sıralı kompozisyon/konuşlanma `GKGameModel`'i, rollout = `BattleSimulator` (`recordEvents: false`), tohumlu `GKMersenneTwisterRandomSource`, bütçe < 1,5 sn, rakip modeli = oyuncunun son kazanan orduları ya da referans profiller; çıktı `EnemyArmyPlan` denemeye kaydedilir; `@concurrent` giriş | Kalibrasyon: referans profillere karşı hedef kazanma bandı; cihazda gecikme ölçümü |
| F3.7 | Ayna seviyeleri (41+): oyuncunun `n − k` seviyesindeki kazanan programı düşman olur; `k` son 5 sonuca göre 3–8 arasında kayar; program yoksa yedek arketip | Testler |
| F3.8 | 40 seviye | Çözülebilirlik ve kalibrasyon testleri |
| F3.9 | Gecelik denge iş akışı (GitHub Actions schedule, Linux): 10k rastgele set × 50 kompozisyon → CSV + aykırı değer raporu, regresyon eşiği %5 | Artifact üretiliyor |

**Zorluk formülleri** (üretici araçta hesaplanır, tabloya pişirilir):

```
R(n)  = min(12, 3 + n/4)              // ordu geneli kural bütçesi (D4)
U(n)  = min(8, 2 + n/6)               // birim tipi sayısı
C(n)  = min(11, 2 + n/3)              // koşul sözlüğü
B(n)  = round(100 * pow(n, 0.55))     // düşman bütçesi
Bp(n) = round(100 * pow(n, 0.48))     // oyuncu bütçesi
H(n)  = min(4, n/8)                   // harita tehlikesi
```

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Hiçbir birim tipi baskın değil | Batch sonuçlarında kazanma oranı %40–60 bandında |
| Hiçbir kural kombinasyonu "her zaman kazanan" değil | En iyi setin kazanma oranı < %75 |
| Stratejist gecikmesi | Referans cihazda < 1,5 sn |
| Ayna seviyesi kalibrasyonu | Playtest'te ilk denemede kazanma oranı %30–50 |
| Denge koşumu CI'da | Gecelik, regresyon raporu |

---

### FAZ 4 — Meta katman ve sosyal · **4 hafta**

| Adım | Çıktı | Bitti tanımı |
|---|---|---|
| F4.1 | `GameCenterService`: kimlik doğrulama, access point, liderlik tabloları (ilerleme, arena), ~30 başarım, `GKGameActivity` + Challenges (GameKit configuration file) | Sandbox'ta uçtan uca |
| F4.2 | SwiftData CloudKit private senkronu (entitlement, container) — D14 | İki cihazda senkron |
| F4.3 | Hayalet Arena (CloudKit public DB, D5): `DefenseSet`, `AttackReport` (seed, config, outcome, checksum, sim/içerik sürümü), güvenlik rolleri, puan bandına göre eşleşme, savunan tarafın yeniden simülasyonla doğrulaması, sürüm uyuşmazlığı yönetimi, kompozisyondan otomatik set adı (serbest metin yok) | Hileli rapor reddediliyor (test) |
| F4.4 | Çevrimdışı önbellek: `CachedDefenseSet`, `PendingAttackReport` kuyruğu, `NWPathMonitor` ile gönderim | Uçak modu senaryosu |
| F4.5 | `ArenaView`: savunma sicili, haftalık emir, gelen saldırılar + "İzle" (yeniden simülasyon), Game Center sıralaması | UI testi |
| F4.6 | Dost Düellosu (`GKTurnBasedMatch`): davet, `matchData` şeması v1 (sürümlü JSON), 3 tur, iki tarafta checksum doğrulaması, `GKLocalPlayerListener` | İki cihaz arasında tam maç |
| F4.7 | `ClipRenderer` (D15): `SKRenderer` → `AVAssetWriter`, kilit an seçimi, Zafer ve En Kötü Yenilgin şablonları (`ImageRenderer`), `ShareLink` + `Transferable` | 9:16, 20 sn, < 8 MB |
| F4.8 | Emir Kütüphanesi: oluştur/düzenle/sil, etiket, kullanım sayısı, editöre uygula | Model testleri |
| F4.9 | In-App Events yapılandırması | App Store Connect |

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Hayalet arena uçtan uca | İki hesap: savunma yayınla → saldır → doğrula → sicil |
| Dost düellosu uçtan uca | İki cihaz arasında 3 tur |
| Çevrimdışı | İndirilmiş setle internetsiz saldırı, bağlantı gelince rapor gönderiliyor |
| Klip paylaşımı | Fotoğraflar / Mesajlar / TikTok'a çıkıyor |
| Klip boyutu | 9:16, < 8 MB, 20 saniye |

---

### FAZ 5 — Monetizasyon · **2 hafta**

| Adım | Çıktı |
|---|---|
| F5.1 | `RewardedAdProvider` protokolü + `NoopAdProvider` |
| F5.2 | AdMob tek dosyada (`AdMobProvider.swift`; `Package.resolved`'daki tek giriş); UMP rıza → ATT sırası; privacy manifest |
| F5.3 | Ödüllü yerleşimler (yeniden dene · düşman önizlemesi · Arena ekstra maç · ödül 2×) + `RewardedBudget` (oturum başına 3) |
| F5.4 | Banner yalnızca ana menü ve meta ekranlarda; savaş ve editör ekranında asla; ödeme yapan kullanıcıda **yüklenmez** (gizlenmez) |
| F5.5 | StoreKit 2: configuration file, `Transaction.updates` dinleyicisi, `currentEntitlements`, token'larla stillenmiş `SubscriptionStoreView` / `ProductView`, geri yükleme, `EntitlementStore`. Ürünler: Reklamsız $4.99 · Sezon Geçişi $7.99 · Komutanlık $3.99/ay |
| F5.6 | AdAttributionKit |
| F5.7 | `EntitlementIndependenceTests`: hiçbir hak R(n)'i değiştiremez; tasarımdaki "1 240" kaynağının kararı |

**Değişmez kural:** Kural bütçesi `R(n)` satılamaz. Kozmetik, kolaylık ve yatay içerik satılabilir.

---

### FAZ 6 — Beta · **3 hafta**

| Adım | Çıktı |
|---|---|
| F6.1 | Xcode Cloud → TestFlight, 200+ tester |
| F6.2 | Yerel telemetri: derleme düzeltme günlüğü (cihazda, isteğe bağlı dışa aktarım) + MetricKit |
| F6.3 | Denge turu: batch verisi + gerçek oyuncu verisi karşılaştırması |
| F6.4 | Onboarding turu: ilk 5 seviyede bırakma oranı (App Store Connect App Analytics) |
| F6.5 | Tam erişilebilirlik denetimi: VoiceOver tam geçiş, Dynamic Type XXL |
| F6.6 | İngilizce yerelleştirme |
| F6.7 | Açık mod kararı (D22) |
| F6.8 | iPad iki sütun (esnek hedef) |

**Kabul kriteri:** D1 retention > %35, D7 > %16.

---

### FAZ 7 — Lansman · **2 hafta**

- App Store metinleri — kelime yasağına tabi (CLAUDE.md kural 7): "kod", "programlama", "kural motoru" vb. **kullanılmaz**.
- Ekran görüntüleri: emir pusulaları ve savaş. Kod benzeri hiçbir şey görünmez.
- Önizleme videosu (`ClipRenderer` ile): emri yaz → savaş → felaket → düzelt → zafer.
- In-App Events, custom product pages.
- App Privacy etiketleri, yaş derecelendirmesi, Game Center'ın App Store Connect'te açılması.
- Basın kiti; ilk reklam kreatif seti (5 varyant).

---

## 7. Test stratejisi ve CI

| Katman | Yaklaşım |
|---|---|
| `FermanCore` | Swift Testing birim testleri + altın dosya + determinizm testi. Hedef > %85 satır kapsamı |
| `RuleEvaluator` | Tablo testi: her koşul × sınır eşik değerleri (N−1, N, N+1) |
| Determinizm | `fermansim verify --runs 1000`; "giriş sırası karıştırılınca checksum aynı"; arm64 = x86_64 |
| `FermanContent` | `ContentValidator` hatalı fixture testleri; `LevelSolvabilityTests` |
| `FermanReplay` | Seek = baştan katlama; içgörü testleri |
| `RuleCompiler` | Doğruluk harness'ı — 150 etiketli ifade, alan bazında rapor |
| Denge | Gecelik `fermansim batch`, regresyon eşiği %5 |
| App modelleri | Swift Testing, servis sahteleriyle |
| UI | XCUITest kritik akışlar + `performAccessibilityAudit()`; `ImageRenderer` tabanlı snapshot (Emir Editörü, Analiz) |
| Değişmezler | `InvariantTests` + `Scripts/check-invariants.sh` (ARCHITECTURE §14) |

**Altın dosya testi:** `Packages/FermanCore/Tests/FermanCoreTests/Resources/Golden/` altında 5 tam `BattleConfig` ve beklenen `checksum`. Simülasyon mantığı değişirse bu testler kırılır. Kasıtlı değişiklikte `simulationVersion` artırılır, altın dosyalar yeniden üretilir ve commit mesajında gerekçelendirilir. Kasıtsız kırılmada **dur ve nedenini bul**.

**CI (D20)**
- **GitHub Actions `core.yml`** (her push/PR): Linux x86_64 (resmi Swift 6.4 imajı yayımlanana kadar `swift:6.3`; paketler bu yüzden `swift-tools-version: 6.2` kullanır) — `swift format lint`, paket testleri + kapsam eşiği, altın dosyalar, `fermansim verify`, `Scripts/check-invariants.sh`. macOS — paket testleri ve aynı altın dosyalar.
- **GitHub Actions `balance-nightly.yml`** (F3.9): denge batch'i ve rapor artifact'i.
- **Xcode Cloud:** uygulama build/test (PR) ve TestFlight (F6.1).

---

## 8. Bağımlılık politikası

| Faz | İzin verilen |
|---|---|
| 0–4 | **Hiçbiri.** Yalnızca Apple framework'leri ve Swift toolchain |
| 5+ | Google Mobile Ads (AdMob) — `RewardedAdProvider` arkasında, tek dosyada |
| 10.000 DAU sonrası | AppLovin MAX / LevelPlay değerlendirilir |
| Android geldiğinde | RevenueCat değerlendirilir |

`Package.resolved` Faz 5'e kadar boş kalır (`Scripts/check-invariants.sh` denetler). Bir sorunu çözmek için paket eklemek gerekiyorsa önce sorulur.

---

## 9. Riskler ve erken uyarı sinyalleri

| Risk | Erken sinyal | Aksiyon |
|---|---|---|
| Kural yazmak eğlenceli değil | Faz 1 playtest'inde oyuncu tek kural yazıp geçiyor | Mekanik değiştir, devam etme |
| Kurallar sonucu değiştirmiyor | F0.13'te kazanma oranı farkı < 20 puan | Tuning; UI'ya geçme |
| Denge kırık | Batch'te bir kompozisyonun kazanma oranı > %75 | Faz 3'te düzelt, sonraki faza geçme |
| LLM derleme doğruluğu düşük | Faz 2'de < %80 | Sözlüğü daralt, `TemplateCompiler`'ı birincil yap |
| Determinizm kayması | `verify` veya altın dosyada farklı checksum; arm64 ≠ x86_64 | Derhal dur. Yasak API listesini tara, `InvariantTests`'i genişlet |
| Sabit nokta taşması | Uzun haritada/yüksek hızda trap | `ContentValidator` aralıklarını daralt; `Fixed` aralık testleri |
| Türkçe ek uyumu hatalı | "%40'in" gibi metinler | `OrderPhraseFormatter` tablo testi 0–100 |
| GameplayKit stratejist yavaş | Cihazda > 1,5 sn | Rollout sayısını/derinliği azalt, kompozisyon uzayını daralt |
| CloudKit kotası / hile | Public DB istek limitleri, sahte raporlar | Puan bandı sorgu sınırı, yeniden simülasyon doğrulaması, sürüm alanları |
| Tasarım açıkları geç kapanıyor | F1.7'de ekleme akışı çizimi yok | §10 listesini Faz 1 başında kapat |
| Kapsam sürüklenmesi | Faz 3 planlanandan uzun sürüyor | Ayna seviyeleri ve kısıt kartları zaten içerik üretiyor. Yeni özellik ekleme |

---

## 10. Tasarım açıkları

`docs/design/project/FERMAN Ekran Panosu.dc.html` teslimi ile `FERMAN-Design-Brief.md` karşılaştırması. Faz 1 ilgili adımından önce kapatılmalıdır.

**Brief'te olup tasarımda olmayan dokular (brief §3.0):** mühür/damga, tırtıklı kenar, katlanma çizgisi, kurşun altlık.

**Eksik ekran ve durumlar**
- **Seçicilerle yeni pusula ekleme akışı** (koşul → parametre → eylem) — F1.7 için kritik.
- Ayarlar ekranı.
- Zafer analizi ("Hat tutuldu").
- Savaş başlatma koreografisi (brief §3.5).
- Kaydırmalı cephe haritası.
- Dynamic Type XXL, iPad ve açık mod varyantları.

**Tanımsız ya da düzeltilecek kavramlar**
- "1 240": kaynağı tanımlanacak ya da kaldırılacak (F5.7).
- "Bölgende 47.": Game Center'da bölgesel kapsam yok; metin değişecek (D5).
- Bütçe sayacı: D4'e göre varsayılan pusula sayılmaz; "3 / 6" örneği "2 / 6" olur.
- VoiceOver: "Öncelik dokuz" yerine sıra adı okunur ("Birinci emir…", D7).

**Tasarımdan token'a kabul edilenler**
- Renkler: brass-lit `#C2A05C`, brass/iron gradyan uçları.
- Tipografi: sayaçlarda Archivo Narrow.
- Opaklık merdiveni, gölge ve köşe yarıçapı tabloları tasarımdan aynen alınır.

---

## 11. İlk komutlar

```bash
# F0.1 — paket iskeletleri (kökten)
mkdir -p Packages/FermanCore Packages/FermanContent Tools/fermansim Scripts
swift package init --type library --name FermanCore --package-path Packages/FermanCore
swift test --package-path Packages/FermanCore
```

Sonra F0.2 `DeterministicRNG`, F0.3 `Fixed` ve `FixedMath`. Determinizm sözleşmesi ilk günden test altında olmalıdır: `InvariantTests` F0.1'de, `fermansim verify` F0.11'de devreye girer.
