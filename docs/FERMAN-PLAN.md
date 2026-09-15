# FERMAN — Geliştirme Planı

**Hedef:** iOS 26+, Swift 6 dil modu, strict concurrency açık, Xcode 27
**Süre:** ~22 hafta (tam zamanlı tek geliştirici)
**Bu dosya:** Claude Code'un fazları sırayla yürütmesi için yazıldı. Her fazın kabul kriteri ölçülebilir.

---

## 0. Ürün özeti (bağlam)

Oyuncu savaşta hiçbir birime dokunmaz. Savaştan önce birimlerinin davranış kurallarını yazar (doğal dille veya seçicilerle), sonra tamamen deterministik bir simülasyon çalışır. Savaş sonrası, her kuralın kaç kez tetiklendiği gösterilir — öğrenme buradan gelir.

---

## 1. ⚠️ Mimari düzeltme — GameplayKit savaş döngüsünde KULLANILMAYACAK

Erken tasarım notlarında savaş simülasyonunun `GKRuleSystem`, `GKAgent2D` ve `GKGridGraph` üzerine kurulması öneriliyordu. **Bu karar geri alındı.** Gerekçe:

| Sorun | Sonuç |
|---|---|
| `GKAgent`'ın yönlendirme matematiği kapalı kutu | Determinizm garanti edilemez |
| `GKGridGraph` A* uygulaması kapalı kutu | Aynı girdi için aynı yolun garantisi yok |
| GameplayKit `NSObject` mirası taşır | Swift 6 strict concurrency ile `@unchecked Sendable` sarmalayıcı gerekir |
| GameplayKit Foundation dışı bir bağımlılık | Simülasyon çekirdeği Linux/CI üzerinde headless koşamaz |
| Kural değerlendirme zaten önemsiz | Sıralı predicate listesi ~40 satır. `GKRuleSystem`'in bulanık mantığı gereksiz |

**Yeni kural:**

```
FermanCore   →  saf Swift. Yalnızca Foundation. GameplayKit YOK, SpriteKit YOK, UIKit YOK.
FermanAI     →  GameplayKit YALNIZCA burada (savaş öncesi düşman kompozisyon seçimi)
FermanApp    →  SwiftUI + SpriteKit
```

GameplayKit'in projede tek meşru kullanımı **`GKMonteCarloStrategist`**: düşmanın savaş öncesi ordu kompozisyonunu ve konuşlanmasını seçmek. Bu, simülasyonun dışındadır, deterministik olmak zorunda değildir ve gerçekten haftalarca iş tasarrufu sağlar.

Yol bulma, sürü davranışı ve kural değerlendirme elle yazılacak. Toplam ~300 satır, tamamen deterministik, CI'da test edilebilir ve 1000× hızda batch koşabilir.

---

## 2. Proje yapısı

```
Ferman/
├── CLAUDE.md                        # her oturumda okunacak kurallar
├── FERMAN-PLAN.md                     # bu dosya
├── Package.swift                    # workspace kökü
│
├── Packages/
│   ├── FermanCore/                    # saf Swift — simülasyon çekirdeği
│   │   ├── Sources/FermanCore/
│   │   │   ├── Determinism/
│   │   │   │   ├── DeterministicRNG.swift
│   │   │   │   └── FixedMath.swift          # açı tabloları, sqrt yaklaşımı
│   │   │   ├── Model/
│   │   │   │   ├── UnitType.swift
│   │   │   │   ├── UnitState.swift
│   │   │   │   ├── BattleMap.swift
│   │   │   │   ├── BattleState.swift
│   │   │   │   └── BattleConfig.swift
│   │   │   ├── Rules/
│   │   │   │   ├── Condition.swift
│   │   │   │   ├── Action.swift
│   │   │   │   ├── Rule.swift
│   │   │   │   ├── RuleProgram.swift
│   │   │   │   └── RuleEvaluator.swift
│   │   │   ├── Simulation/
│   │   │   │   ├── BattleSimulator.swift     # ana döngü
│   │   │   │   ├── Steering.swift            # ayrışma/hizalanma/tutunma
│   │   │   │   ├── FlowField.swift           # yol bulma
│   │   │   │   ├── Combat.swift
│   │   │   │   └── Morale.swift
│   │   │   └── Output/
│   │   │       ├── BattleEvent.swift
│   │   │       └── BattleResult.swift
│   │   └── Tests/FermanCoreTests/
│   │
│   ├── FermanContent/                 # seviye, birim, harita verisi (JSON + loader)
│   │   └── Sources/FermanContent/Resources/
│   │       ├── units.json
│   │       ├── levels.json
│   │       └── maps/
│   │
│   └── FermanAI/                      # kural derleyici + düşman stratejisti
│       └── Sources/FermanAI/
│           ├── RuleCompiler.swift            # protokol
│           ├── ManualCompiler.swift          # seçici tabanlı, LLM'siz
│           ├── TemplateCompiler.swift        # anahtar kelime eşleme yedeği
│           ├── FoundationModelsCompiler.swift
│           └── EnemyStrategist.swift         # GKMonteCarloStrategist burada
│
├── Tools/
│   └── fermansim/                     # CLI — headless simülasyon ve denge
│       └── Sources/fermansim/main.swift
│
└── App/
    └── Ferman.xcodeproj
        └── Ferman/
            ├── FermanApp.swift
            ├── Features/
            │   ├── Home/
            │   ├── Campaign/
            │   ├── ArmySetup/
            │   ├── RuleEditor/
            │   ├── Battle/
            │   ├── Debrief/
            │   ├── Arena/
            │   └── Library/
            ├── Rendering/                    # SpriteKit — replay oynatıcı
            │   ├── BattleScene.swift
            │   └── ReplayPlayer.swift
            ├── Services/
            │   ├── ProgressStore.swift       # SwiftData
            │   ├── GameCenterService.swift
            │   ├── ClipRecorder.swift        # ReplayKit
            │   └── Monetization/
            └── DesignSystem/
```

---

## 3. Temel mimari kararlar

### 3.1 Simüle-sonra-oynat (sim-then-render)

Simülasyon savaş başlamadan **tamamına kadar** koşar ve bir olay akışı üretir. SpriteKit bu akışı oynatır.

```
BattleConfig → BattleSimulator.run() → BattleResult (birkaç ms)
                                            ↓
                                   ReplayPlayer → SpriteKit
```

Kazanımlar:
- Anında yeniden başlatma (yeniden simüle etmeye gerek yok)
- Hız kontrolü (1×/2×/4×) ve geri sarma bedava
- Render katmanı oyun mantığını hiç bilmez
- Denge testi için aynı simülatör 1000× hızda batch koşar

Bu mimari zorunludur. Simülasyonu render döngüsüne bağlama.

### 3.2 Determinizm sözleşmesi

Aynı `BattleConfig` + aynı seed = bit düzeyinde aynı `BattleResult`. Her zaman.

**FermanCore içinde yasak:**

| Yasak | Yerine |
|---|---|
| `Date()`, `DispatchTime`, herhangi bir saat | Yalnızca `tick` sayacı |
| `Int.random`, `arc4random`, `SystemRandomNumberGenerator` | `DeterministicRNG` (xoshiro256**) |
| `Dictionary` / `Set` üzerinde sıraya duyarlı iterasyon | Sıralı `Array`, veya `sorted()` |
| `sin`, `cos`, `atan2` doğrudan çağrısı | `FixedMath` içindeki 4096 girişli tablolar |
| `Float80`, `-Ofast`, `@_effects` | — |
| Paralel `for` / `TaskGroup` simülasyon içinde | Tek iş parçacığı |
| `UUID()` çalışma zamanında | Deterministik ID sayacı |

`sqrt` ve temel aritmetik IEEE754 olduğu için serbest. Transandantal fonksiyonlar platform kütüphanesine bağlı olduğu için tablolanır.

### 3.3 LLM disiplini

```
╔════════════════════════════════════════════════════════╗
║  Dil modeli ASLA oyun sonucunu belirlemez.            ║
║                                                        ║
║  Yapabileceği tek şey: metni RuleProgram'a çevirmek.  ║
║  Ürettiği her RuleProgram oyuncuya gösterilir ve      ║
║  oyuncu onaylamadan / düzenlemeden savaş başlamaz.    ║
╚════════════════════════════════════════════════════════╝
```

`RuleCompiler` bir protokoldür. Üç uygulaması vardır ve **uygulamanın tamamı `ManualCompiler` ile oynanabilir olmalıdır.** LLM katmanı bir kolaylıktır, bir bağımlılık değil.

---

## 4. Temel tipler (Faz 0'da yazılacak sözleşme)

Bu imzalar bağlayıcıdır. Faz 1'e geçmeden önce dondurulmalı.

```swift
// ───────────── Determinism ─────────────

public struct DeterministicRNG: Sendable {
    public init(seed: UInt64)
    public mutating func next() -> UInt64
    public mutating func int(in range: ClosedRange<Int>) -> Int
    public mutating func unit() -> Float            // [0, 1)
}

// ───────────── Model ─────────────

public struct UnitTypeID: Hashable, Codable, Sendable { public let raw: String }
public struct UnitID: Hashable, Codable, Sendable { public let raw: UInt32 }
public enum Team: UInt8, Codable, Sendable { case player, enemy }

public struct UnitType: Codable, Sendable {
    public let id: UnitTypeID
    public let displayName: String
    public let cost: Int
    public let maxHP: Int
    public let speed: Float              // kare / saniye
    public let range: Float              // kare
    public let damage: Int
    public let attackInterval: Float     // saniye
    public let armor: Int
    public let moraleBase: Int
    public let counters: [UnitTypeID]    // hasar bonusu verdiği tipler
}

public enum Terrain: UInt8, Codable, Sendable {
    case open, forest, hill, water, rubble
}

public struct BattleMap: Codable, Sendable {
    public let width: Int, height: Int
    public let terrain: [Terrain]        // row-major, width*height
    public let playerZone: [Int]         // yerleştirilebilir kare indeksleri
    public let enemyZone: [Int]
}

public struct UnitState: Sendable {
    public var id: UnitID
    public var type: UnitTypeID
    public var team: Team
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    public var hp: Int
    public var morale: Int
    public var activeRuleIndex: Int?     // şu anda hangi pusula
    public var attackCooldown: Float
    public var isAlive: Bool { hp > 0 }
}

// ───────────── Rules ─────────────

public enum ConditionKind: String, CaseIterable, Codable, Sendable {
    case enemyWithin          // eşik: kare (1–10)
    case healthBelow          // eşik: yüzde (10–90)
    case allyCountBelow       // eşik: adet (1–10)
    case isFlanked            // eşik yok
    case targetInRange        // parametre: UnitTypeID
    case timeAfter            // eşik: saniye (1–60)
    case nearestEnemyType     // parametre: UnitTypeID
    case moraleBelow          // eşik: yüzde (10–90)
    case terrainIs            // parametre: Terrain
    case commanderDead        // eşik yok
    case enemyDensityAbove    // eşik: adet (2–8)
    case always               // varsayılan pusula
}

public enum ActionKind: String, CaseIterable, Codable, Sendable {
    case advance, retreat, hold, focusFire, flankLeft, flankRight,
         regroup, useAbility, takeCover, guardCommander, scatter
}

public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID                  // yalnızca UI kimliği; simülasyona girmez
    public var condition: ConditionKind
    public var threshold: Int
    public var conditionParameter: String?   // UnitTypeID veya Terrain raw değeri
    public var action: ActionKind
    public var actionParameter: String?
    public var priority: Int             // 1–10, yüksek önce
}

public struct RuleProgram: Codable, Sendable {
    public let unitType: UnitTypeID
    public var rules: [Rule]             // en fazla 12, öncelik sırasında
}

// ───────────── Simulation ─────────────

public struct BattleConfig: Sendable {
    public let map: BattleMap
    public let playerUnits: [(UnitTypeID, SIMD2<Float>)]
    public let enemyUnits: [(UnitTypeID, SIMD2<Float>)]
    public let playerPrograms: [UnitTypeID: RuleProgram]
    public let enemyPrograms: [UnitTypeID: RuleProgram]
    public let seed: UInt64
    public let maxTicks: Int             // varsayılan 2700 = 90sn @ 30Hz
}

public enum BattleEvent: Sendable {
    case spawn(UnitID, UnitTypeID, Team, SIMD2<Float>)
    case move(UnitID, SIMD2<Float>)      // her tick değil, 10Hz örneklenmiş
    case ruleFired(UnitID, ruleIndex: Int, tick: Int)
    case attack(UnitID, target: UnitID, damage: Int, tick: Int)
    case death(UnitID, tick: Int)
    case moraleBreak(UnitID, tick: Int)
}

public enum BattleOutcome: Sendable { case playerWin, enemyWin, timeout }

public struct BattleResult: Sendable {
    public let outcome: BattleOutcome
    public let tickCount: Int
    public let events: [BattleEvent]
    public let ruleFireCounts: [UnitTypeID: [Int: Int]]   // tip → pusula indeksi → adet
    public let survivorsPlayer: Int
    public let survivorsEnemy: Int
    public let checksum: UInt64                            // determinizm testi için
}

public struct BattleSimulator: Sendable {
    public static func run(_ config: BattleConfig) -> BattleResult
}

// ───────────── AI ─────────────

public protocol RuleCompiler: Sendable {
    func compile(_ text: String, context: CompileContext) async throws -> [Rule]
}

public struct CompileContext: Sendable {
    public let unitType: UnitTypeID
    public let availableConditions: [ConditionKind]   // seviyeye göre kilitli
    public let availableActions: [ActionKind]
    public let availableUnitTypes: [UnitTypeID]
    public let remainingRuleBudget: Int
}
```

---

## 5. Fazlar

### FAZ 0 — Simülasyon çekirdeği ve CLI · **2 hafta**

UI yok. Xcode projesi yok. Yalnızca SPM paketi ve komut satırı.

**Görevler**

- [ ] `Package.swift` workspace, `FermanCore` hedefi (yalnızca Foundation bağımlılığı)
- [ ] `DeterministicRNG` — xoshiro256**, seed'lenebilir, `Codable` durum
- [ ] `FixedMath` — 4096 girişli sin/cos tablosu, tablo tabanlı `atan2`
- [ ] `BattleMap` + `Terrain` + JSON yükleyici
- [ ] 4 birim tipi: `mizrakci`, `okcu`, `suvari`, `kalkan` (`units.json`)
- [ ] `RuleEvaluator` — öncelik sırasında ilk eşleşen kural kazanır
- [ ] `FlowField` — hedefe doğru akış alanı, terrain maliyetli. Birim başına A* değil, takım başına tek alan
- [ ] `Steering` — ayrışma + hizalanma + tutunma + akış takibi, ağırlıklı toplam
- [ ] `Combat` — menzil kontrolü, cooldown, zırh, counter bonusu
- [ ] `Morale` — yakın ölümler morali düşürür, eşik altında `scatter`
- [ ] `BattleSimulator.run` — 30Hz sabit adım, olay akışı üretir
- [ ] `checksum` — tüm birim durumlarının FNV-1a özeti, her 30 tick'te güncellenir
- [ ] CLI `fermansim`:
  - `fermansim run --config battle.json` → sonuç + checksum
  - `fermansim batch --matrix matrix.json --count 10000 --out results.csv`
  - `fermansim verify --config battle.json --runs 1000` → tüm checksum'lar aynı mı

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Determinizm | `fermansim verify --runs 1000` → 1000 özdeş checksum |
| Hız | 10.000 savaş < 60 saniye (M-serisi Mac, tek çekirdek) |
| Test kapsamı | `FermanCore` için > %85 satır kapsamı |
| Altın dosya | 5 referans savaş, sonuçları repoda saklı, CI'da karşılaştırılıyor |
| Bağımlılık | `FermanCore` yalnızca `Foundation` import ediyor |

**Bu fazın sonunda cevaplanacak soru:** Elle yazılmış kural setleri, farklı sonuçlar üretiyor mu? Yani kural yazmak simülasyonda gerçekten fark yaratıyor mu? Yaratmıyorsa denge parametreleri yanlıştır ve UI yazmadan önce düzeltilmelidir.

---

### FAZ 1 — Dikey dilim · **4 hafta**

Xcode projesi, SwiftUI, SpriteKit. **LLM kodu bu fazda repoda bulunmayacak.**

**Görevler**

- [ ] Xcode projesi, iOS 26 hedef, Swift 6 dil modu, strict concurrency `complete`
- [ ] `DesignSystem` — Claude Design çıktısından token'lar (renk, tip, boşluk, yarıçap)
- [ ] `ReplayPlayer` — `BattleResult.events` akışını zaman damgasına göre kuyruğa alır
- [ ] `BattleScene` (SpriteKit) — jeton render, hareket enterpolasyonu, kıvılcım efekti
- [ ] `SpriteView` ile SwiftUI köprüsü, üst bar ve pusula sayaç şeridi SwiftUI katmanında
- [ ] `ArmySetupView` — ızgaraya sürükle-bırak, bütçe kontrolü
- [ ] `RuleEditorView` — **yalnızca seçicilerle**. Pusula yığını, sürükle-sırala, parametre kadranı
- [ ] `ManualCompiler` — seçici çıktısını `Rule`'a çevirir (LLM yok)
- [ ] `DebriefView` — `ruleFireCounts` görselleştirmesi, "hiç çalışmadı" uyarısı
- [ ] `ProgressStore` (SwiftData) — seviye ilerlemesi, kaydedilmiş emir setleri
- [ ] 8 seviye (`levels.json`), elle dengelenmiş
- [ ] Hız kontrolü 1× / 2× / 4×, duraklama, anında yeniden başlat

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| 8 seviye baştan sona oynanabilir | Manuel test |
| LLM bağımlılığı yok | `grep -ri "FoundationModels" App/ Packages/` → boş |
| 3rd party bağımlılık yok | `Package.resolved` boş |
| 150 birimde 60fps | Instruments, iPhone 15 |
| Yeniden başlatma < 100ms | Simülasyon zaten önceden koşuyor |

> ### 🚦 KARAR NOKTASI
>
> Bu fazın sonunda dikey dilim **LLM olmadan, sadece seçicilerle 10 dakika eğlenceli olmalı.**
>
> Eğlenceli değilse doğal dil katmanı bunu kurtarmaz — sadece kural yazmayı hızlandırır. Projenin üzerinde durduğu tek varsayım budur. Burada durup mekanik değiştirmek, devam etmekten çok daha ucuzdur.

---

### FAZ 2 — Doğal dil derleyici · **2 hafta**

**Görevler**

- [ ] `FoundationModelsCompiler` — `@Generable` yapılar, `@Guide` ile kapalı enum kısıtı
- [ ] `SystemLanguageModel.availability` kontrolü, `contextSize` ve `tokenCount(for:)` ön kontrolü
- [ ] Durumsuz oturum deseni — her derleme yeni `LanguageModelSession`, konuşma geçmişi yok
- [ ] 2 saniye zaman aşımı → `TemplateCompiler`'a düşüş
- [ ] `TemplateCompiler` — anahtar kelime eşleme, LLM'siz cihazlar için
- [ ] Derleme doğruluk test koşumu: `Tests/CompilerAccuracy/phrases.json` — 150 etiketli Türkçe + İngilizce ifade, beklenen `Rule` çıktısı
- [ ] Damgalama animasyonu (Design brief §3.5)
- [ ] Ses girişi: `SFSpeechRecognizer` on-device, opsiyonel

**`@Generable` sözleşmesi**

```swift
@Generable
struct CompiledRule {
    @Guide(description: "Kuralın tetiklenme koşulu")
    let condition: ConditionKind

    @Guide(.range(0...100))
    let threshold: Int

    @Guide(description: "Koşul tetiklendiğinde yapılacak eylem")
    let action: ActionKind

    @Guide(.range(1...10))
    let priority: Int
}

@Generable
struct CompiledProgram {
    @Guide(.count(1...3))
    let rules: [CompiledRule]     // tek cümleden en fazla 3 kural
}
```

Enum'lar kapalı olduğu için model geçersiz değer üretemez. Halüsinasyon burada "yanlış ama geçerli kural" olarak çıkar ve oyuncu düzeltir.

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Derleme doğruluğu | 150 ifadede > %88 tam eşleşme |
| Yedek düşüş | Apple Intelligence kapalı simülatörde oyun tam işlevsel |
| Gecikme | p95 < 2.5 saniye (iPhone 16) |
| Bağlam aşımı | Hiç oluşmuyor — her oturum < 800 token |

---

### FAZ 3 — Zorluk, düşman YZ ve Ayna · **4 hafta**

**Görevler**

- [ ] Zorluk formülleri (`DifficultyCurve.swift`):
  ```
  R(n) = min(12, 3 + n/4)              // kural bütçesi
  U(n) = min(8, 2 + n/6)               // birim tipi sayısı
  C(n) = min(11, 2 + n/3)              // koşul sözlüğü
  B(n) = round(100 * pow(n, 0.55))     // düşman bütçesi
  Bp(n) = round(100 * pow(n, 0.48))    // oyuncu bütçesi
  H(n) = min(4, n/8)                   // harita tehlikesi
  ```
- [ ] Kısıt kartları: Sessiz emir, Körlük, Tek akıl, İnat, Sis, Vekil
- [ ] `EnemyStrategist` — `GKMonteCarloStrategist` ile kompozisyon seçimi (**GameplayKit'in tek kullanımı**)
- [ ] Seviye 1–10: elle yazılmış düşman kural setleri
- [ ] Seviye 11–25: `GKDecisionTree` taktik seçimi
- [ ] Seviye 26–40: Monte Carlo kompozisyon araması, bütçe seviyeyle artar
- [ ] **Ayna seviyeleri (41+):** oyuncunun `n−k` seviyesindeki kendi kural programı düşman olur. `k`, son 5 seviyedeki başarı oranına göre 3–8 arasında kayar
- [ ] 40 seviyeye çıkış
- [ ] Gecelik denge koşumu: `fermansim batch` ile 10.000 rastgele kural seti × 50 kompozisyon, CSV çıktısı, aykırı değer raporu

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Hiçbir birim tipi baskın değil | Batch sonuçlarında kazanma oranı %40–60 bandında |
| Hiçbir kural kombinasyonu "her zaman kazanan" değil | En iyi setin kazanma oranı < %75 |
| Ayna seviyesi kalibrasyonu | Playtest'te ilk denemede kazanma oranı %30–50 |
| Denge koşumu CI'da | Gecelik, regresyon raporu |

---

### FAZ 4 — Meta katman ve sosyal · **3 hafta**

**Görevler**

- [ ] Game Center: liderlik tabloları, ~30 başarım, Challenges
- [ ] `GKSavedGame` ile cihazlar arası senkron
- [ ] **Arena:** `GKTurnBasedMatch` `matchData` içinde kural programı + ordu (~1 KB)
  - Skor = kaç saldırının püskürtüldüğü (savunma tarafı)
  - Her savaş saldıranın cihazında simüle edilir
- [ ] `ClipRecorder` — `RPScreenRecorder` ile savaş klibi
- [ ] Paylaşım kartı üretici: klip + emir metni overlay. İki şablon: Zafer, En Kötü Yenilgin
- [ ] Emir Kütüphanesi — adlandırılmış kural setleri, SwiftData
- [ ] In-App Events yapılandırması (App Store Connect)

**Kabul kriterleri**

| Kriter | Ölçüm |
|---|---|
| Arena maçı uçtan uca | İki cihaz arasında tam tur |
| Klip paylaşımı | Fotoğraflar / Mesajlar / TikTok'a çıkıyor |
| Klip boyutu | 9:16, < 8 MB, 20 saniye |

---

### FAZ 5 — Monetizasyon · **2 hafta**

**Görevler**

- [ ] `RewardedAdProvider` protokolü, `AdMobProvider` ve `NoopAdProvider`
- [ ] AdMob SDK — **tek dosyada izole**, `AppDelegate`'e sızmayacak
- [ ] Ödüllü yerleşimler: yeniden dene · düşman önizlemesi · Arena ekstra maç · ödül 2×
- [ ] Oturum başına 3 ödüllü limiti (`RewardedBudget`)
- [ ] Banner: yalnızca ana menü ve meta ekranlar. Savaş ve editör ekranında asla
- [ ] StoreKit 2: Reklamsız $4.99 · Sezon Geçişi $7.99 · Komutanlık $3.99/ay
- [ ] `Transaction.currentEntitlements` ile hak doğrulama, sunucu yok
- [ ] AdAttributionKit entegrasyonu
- [ ] Ödeme yapan kullanıcıda banner **yüklenmez** (gizlenmez)

**Değişmez kural:** kural bütçesi `R(n)` satılamaz. Kozmetik, kolaylık ve yatay içerik satılabilir.

---

### FAZ 6 — Beta · **3 hafta**

- [ ] TestFlight, hedef 200+ tester
- [ ] Analitik: hangi kural ifadeleri en çok yanlış derleniyor (yerel toplama, kişisel veri yok)
- [ ] Denge turlaması — batch verisi + gerçek oyuncu verisi karşılaştırması
- [ ] Onboarding turlaması: ilk 5 seviyede bırakma oranı
- [ ] Erişilebilirlik denetimi: VoiceOver tam geçiş, Dynamic Type XXL

**Kabul kriteri:** D1 retention > %35, D7 > %16.

---

### FAZ 7 — Lansman · **2 hafta**

- [ ] App Store metinleri — "programlama", "kod", "kural motoru" kelimeleri **kullanılmayacak**
- [ ] Ekran görüntüleri: emir pusulaları ve savaş. Kod benzeri hiçbir şey görünmeyecek
- [ ] Önizleme videosu: emri yaz → savaş → felaket → düzelt → zafer
- [ ] In-App Events
- [ ] Basın kiti
- [ ] İlk reklam kreatif seti (5 varyant)

---

## 6. Test stratejisi

| Katman | Yaklaşım |
|---|---|
| `FermanCore` | Birim testi + altın dosya + determinizm testi. Hedef > %85 kapsam |
| `RuleEvaluator` | Tablo testi: her koşul × her eşik sınır değeri |
| `RuleCompiler` | Doğruluk koşumu — 150 etiketli ifade, CI'da oran raporu |
| Denge | Gecelik `fermansim batch`, regresyon eşiği %5 |
| UI | Snapshot testi kritik ekranlar için (Emir Editörü, Analiz) |
| Erişilebilirlik | XCUITest ile VoiceOver geçişi |

**Altın dosya testi:** `Tests/Golden/` altında 5 tam `BattleConfig` ve beklenen `checksum`. Simülasyon mantığı değişirse bu testler kırılır — kasıtlı değişiklikte altın dosyalar yeniden üretilir ve commit mesajında gerekçelendirilir.

---

## 7. Bağımlılık politikası

| Faz | İzin verilen |
|---|---|
| 0–4 | **Hiçbiri.** Yalnızca Apple framework'leri |
| 5+ | Google Mobile Ads (AdMob) — protokol arkasında, tek dosyada |
| 10.000 DAU sonrası | AppLovin MAX / LevelPlay değerlendirilir |
| Android geldiğinde | RevenueCat değerlendirilir |

`Package.resolved` Faz 4 sonuna kadar boş kalmalı.

---

## 8. Riskler ve erken uyarı sinyalleri

| Risk | Erken sinyal | Aksiyon |
|---|---|---|
| Kural yazmak eğlenceli değil | Faz 1 playtest'inde oyuncu tek kural yazıp geçiyor | Mekanik değiştir, devam etme |
| Denge kırık | Batch'te bir kompozisyonun kazanma oranı > %75 | Faz 3'te düzelt, sonraki faza geçme |
| LLM derleme doğruluğu düşük | Faz 2'de < %80 | Sözlüğü daralt, `TemplateCompiler`'ı birincil yap |
| Determinizm kayması | `verify` testinde farklı checksum | Derhal dur. Yasak API listesini tara |
| Kapsam sürüklenmesi | Faz 3 planlanandan uzun sürüyor | Ayna seviyeleri ve kısıt kartları zaten içerik üretiyor. Yeni özellik ekleme |

---

## 9. İlk komut

```bash
mkdir -p Ferman && cd Ferman
swift package init --type empty
```

Sonra Faz 0'ın ilk üç görevi: `DeterministicRNG`, `FixedMath`, `BattleMap`. Bunlar bittiğinde `fermansim verify` koşabilir olmalı — determinizm sözleşmesi daha ilk günden test altında olmalı.
