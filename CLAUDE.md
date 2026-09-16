# CLAUDE.md — FERMAN

Bu dosya her oturumda okunur. Kısa tutulmuştur.
- Yol haritası ve simülasyon semantiği: [`docs/FERMAN-PLAN.md`](docs/FERMAN-PLAN.md)
- Modüller ve katmanlar: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Kararlar (`D#`): [`docs/DECISIONS.md`](docs/DECISIONS.md)

---

## Proje

iOS oyunu. Oyuncu savaşta hiçbir birime dokunmaz — savaştan önce birimlerinin davranış kurallarını yazar ("emir pusulaları"), sonra deterministik bir simülasyon çalışır. Savaş sonrası her kuralın kaç kez tetiklendiği gösterilir; öğrenme buradan gelir.

**Hedef:** iOS 27+ (D1), Swift 6.4 / Swift 6 dil modu, strict concurrency `complete`, Xcode 27.

---

## Değişmez kurallar

Bunlar tartışmaya açık değildir. Bir görev bunlardan birini ihlal etmeyi gerektiriyorsa, kodu yazma — önce sor.

### 1. `FermanCore` saf kalır

`FermanCore` yalnızca `Foundation` import eder. GameplayKit, SpriteKit, UIKit, SwiftUI, Combine, simd — hiçbiri yok. Paket Linux'ta derlenip test edilebilmelidir. Aynısı `FermanContent` ve `FermanReplay` için de geçerlidir.

### 2. Determinizm sözleşmesi

Aynı `BattleConfig` + aynı seed = bit düzeyinde aynı `BattleResult`. Her zaman, her koşumda, her platformda (macOS arm64 = Linux x86_64).

`FermanCore` içinde **yasak**:

| Yasak | Yerine |
|---|---|
| `Float`, `Double`, `CGFloat`, `SIMD*` | `Fixed` (Q16.16) ve `FixedVector2` (D2) |
| `Date()`, `DispatchTime`, herhangi bir saat | `tick` sayacı |
| `Int.random`, `arc4random`, `SystemRandomNumberGenerator` | `DeterministicRNG` |
| `hashValue`, `Hasher` ile mantık | Açık sıralama anahtarı |
| `Dictionary` / `Set` üzerinde sıraya duyarlı iterasyon | Sıralı `Array` veya `.sorted()` |
| `sin`, `cos`, `atan2`, `sqrt`, `pow` | `FixedMath` tabloları, tamsayı `isqrt` |
| `UUID()` çalışma zamanında | Deterministik ID sayacı |
| `TaskGroup`, `async let`, paralel `for` simülasyon içinde | Tek iş parçacığı |

Birbirinden bağımsız koşumların paralel çalışması (`fermansim batch --jobs`, stratejist rollout'ları) serbesttir; tek bir koşum her zaman tek iş parçacığıdır.

Determinizmi bozan bir değişiklik yaptıysan `fermansim verify --runs 1000` ve altın dosyalar kırılır. Kırıldığında **dur ve nedenini bul** — altın dosyaları yeniden üreterek geçiştirme.

### 3. Dil modeli asla sonucu belirlemez

```
Modelin yapabileceği tek şey: metni Rule dizisine çevirmek.
Ürettiği her Rule RuleValidator'dan geçer ve oyuncuya gösterilir. Oyuncu görmeden savaş başlamaz.
```

`RuleCompiler<Input>` bir protokoldür (D18). Uygulamanın tamamı `ManualCompiler` (`Input = RuleDraft`, seçici tabanlı) ile oynanabilir olmalıdır. LLM bir kolaylıktır, bağımlılık değil.

`FoundationModels` import'u yalnızca `FermanAI/Sources/FermanAI/FoundationModelsCompiler.swift` ve onun test dosyasında bulunabilir.

### 4. Simüle-sonra-oynat

Simülasyon savaş başlamadan tamamına kadar koşar ve olay akışı üretir. SpriteKit bu akışı **oynatır**.

```
BattleConfig → BattleSimulator.run() → BattleResult → ReplayTimeline → BattleScene
```

Simülasyonu render döngüsüne bağlama. `BattleScene` oyun kurallarını bilmez, yalnızca `ReplayFrame` çizer.

### 5. GameplayKit yalnızca düşman seçiminde (D6)

- `import GameplayKit` yalnızca `Packages/FermanAI/Sources/FermanAI/EnemyAI/` klasöründe bulunabilir.
- Meşru kullanımlar: `EnemyTacticTree` (`GKDecisionTree`, seviye 11–25) ve `EnemyStrategist` (`GKMonteCarloStrategist`, seviye 26–40). İkisi de savaştan **önce** çalışır.
- `NSObject` tabanlı GameplayKit tipleri o klasörden dışarı çıkmaz; dışa açık API yalnızca Sendable değer tipleri alır ve döndürür.
- Simülasyon içinde GameplayKit yok: `GKAgent`, `GKGridGraph`, `GKRuleSystem` ve GameplayKit rastgele kaynakları kullanılmaz. Yol bulma, sürü davranışı, kural değerlendirme elle yazılır.

### 6. Bağımlılık yok

Faz 5'e kadar `Package.resolved` boş kalır. Faz 5'te tek istisna: Google Mobile Ads, `RewardedAdProvider` protokolü arkasında, tek dosyada izole.

Bir sorunu çözmek için paket eklemeyi düşünüyorsan, önce sor.

### 7. Kelime yasağı

Kullanıcıya görünen hiçbir metinde (UI, App Store, hata mesajı) şunlar geçmez:

> kod · derle · fonksiyon · debug · script · algoritma · kural motoru · if · else · programla · programlama · çalıştır

Kullanılacak karşılıklar: **emir**, **pusula**, **yaz**, **düzelt**, **öncelik**. ("Bu emir hiç çalışmadı." serbesttir.)

Kod içinde teknik isimler serbest (`RuleCompiler`, `compile`) — kısıt yalnızca kullanıcı arayüzü metinleri içindir.

---

## Dizin yapısı

```
CLAUDE.md
.swift-format
.github/workflows/        core.yml (F0.12), balance-nightly.yml (F3.9)
Scripts/                  check-invariants.sh
docs/                     FERMAN-PLAN.md · ARCHITECTURE.md · DECISIONS.md · tasarım brief'i ve teslimi
Packages/FermanCore/      saf Swift simülasyon — Foundation dışı import YOK
Packages/FermanContent/   JSON veri: birimler, seviyeler, haritalar + doğrulayıcı
Packages/FermanReplay/    ReplayTimeline + DebriefAnalyzer (D11)
Packages/FermanAI/        RuleCompiler uygulamaları + EnemyAI/ (GameplayKit)
Tools/fermansim/          CLI: run / verify / batch / bench / validate-content / gen-tables
Balance/                  denge matrisleri ve raporları
App/Ferman/               SwiftUI + SpriteKit (F1.1'de oluşturulur, D3)
  Features/             ekran başına klasör: XView + XModel
  Rendering/            SpriteKit replay oynatıcı, ClipRenderer
  Services/             BattleRunner, SwiftData, GameKit, CloudKit, konuşma, monetizasyon
  DesignSystem/         token'lar ve ortak bileşenler
```

Kökteki `FERMAN.xcodeproj` Xcode şablonudur; F1.1'e kadar dokunulmaz (D3).

---

## Komutlar

```bash
# Paket testleri (macOS). Linux doğrulaması yerelde yapılmaz, CI'da koşar (F0.12).
swift test --package-path Packages/FermanCore
swift test --package-path Packages/FermanContent
swift test --package-path Tools/fermansim

# Değişmez denetimleri
Scripts/check-invariants.sh

# Biçim
swift format lint --strict --recursive Packages Tools
swift format --in-place --recursive Packages Tools

# Determinizm doğrulaması — her simülasyon değişikliğinden sonra (F0.11+)
swift run -c release --package-path Tools/fermansim fermansim verify \
  --config Packages/FermanCore/Tests/FermanCoreTests/Resources/Golden/battle-01.json --runs 1000

# Tek savaş
swift run -c release --package-path Tools/fermansim fermansim run --config <config.json>

# Denge batch'i
swift run -c release --package-path Tools/fermansim fermansim batch \
  --matrix Balance/matrix.json --count 10000 --jobs 8 --out results.csv

# Trigonometri tablolarını yeniden üret (--check: yalnızca güncel mi diye bak)
swift run --package-path Tools/fermansim fermansim gen-tables \
  --out Packages/FermanCore/Sources/FermanCore/Determinism/FixedMathTables.swift

# FermanCore kapsamı (eşik > %85)
swift test --package-path Packages/FermanCore --enable-code-coverage
xcrun llvm-cov report Packages/FermanCore/.build/out/Products/Debug/FermanCoreTests.xctest/Contents/MacOS/FermanCoreTests \
  -instr-profile Packages/FermanCore/.build/out/Products/Debug/codecov/default.profdata -ignore-filename-regex '(Tests|\.build)/'

# Uygulama (F1.1+)
xcodebuild -project App/Ferman.xcodeproj -scheme Ferman -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

---

## Kod tarzı

- Swift 6, strict concurrency `complete`. `@unchecked Sendable` ve `nonisolated(unsafe)` kullanma — gerekiyorsa tasarım yanlıştır.
- Paketler: `ExistentialAny` açık, uyarılar hata. `FermanCore`'da `strictMemorySafety` açık.
- `FermanCore` tipleri `struct`/`enum` ve `Sendable`. Simülasyon içinde referans tipi yok.
- Hatalar typed throws ile (`throws(ContentError)`). Force unwrap, `try!` ve `fatalError` ile akış kontrolü yok.
- Alan adları Türkçe değil İngilizce (`playerUnits`, `ruleFireCounts`). Yalnızca kullanıcıya görünen metinler Türkçe ve String Catalog'da (D21).
- Kısaltma kullanma: `ruleIndex`, `ri` değil.
- Zorunlu olmadıkça yorum yazma. Yazıyorsan *neden*'i yaz, *ne*'yi değil.
- Testler Swift Testing ile (`@Test`, `#expect`, `@Test(arguments:)`); UI testleri XCUITest.
- SwiftUI: `@Observable`, app target varsayılan `MainActor`, `@Entry` ile environment, `NavigationStack(path:)` + typed `Route`. `ObservableObject` ve Combine kullanma (D12, D13).
- Her `Features/` klasöründe: `XView.swift` + `XModel.swift`. Görünüm mantığı model tarafında.
- Loglama `Logger` (OSLog) ile; `print` yalnızca `fermansim` çıktısında.
- Bir Apple API'sini kullanmadan önce güncel dokümantasyonda erişilebilirliğini ve deprecation durumunu kontrol et.

---

## Test beklentisi

| Ne | Nerede | Eşik |
|---|---|---|
| Simülasyon birim testleri | `FermanCoreTests` | > %85 satır kapsamı |
| Değişmezler | `InvariantTests`, `Scripts/check-invariants.sh` | Her zaman yeşil |
| Determinizm | `fermansim verify` | 1000 koşumda özdeş checksum |
| Altın dosyalar | `FermanCoreTests/Resources/Golden/` | 5 referans savaş, arm64 = x86_64, CI'da karşılaştırılır |
| Kural değerlendirme | Tablo testi | Her koşul × sınır eşik değerleri |
| Seviyeler | `LevelSolvabilityTests` | Her seviye referans çözümle kazanılır |
| Derleyici doğruluğu | `Tests/CompilerAccuracy/` | 150 ifadede > %88 |

Yeni simülasyon mantığı yazarken önce testi yaz. Altın dosya kırıldığında, kasıtlı bir değişiklikse `simulationVersion`'ı artır, yeniden üret ve commit mesajında gerekçelendir.

---

## Şu anki durum

**Faz:** 0 — Simülasyon çekirdeği (`docs/FERMAN-PLAN.md` §6)
**Tamamlanan:** F0.1 paket iskeleti ve değişmez denetimleri · F0.2 `DeterministicRNG` · F0.3 `Fixed` / `FixedMath` · F0.4 tip sözleşmesi · F0.5 içerik kataloğu ve doğrulama · F0.6 `SpatialGrid` / `FlowField` · F0.7 `RuleEvaluator` / `RuleValidator` · F0.8 `Steering` · F0.9 `Combat` / `Morale` / `Abilities` · F0.10 `BattleSimulator.run` (tick hattı, checksum, `ruleFireCounts`) · F0.11 `fermansim run` / `verify` / `batch` (`--jobs`) / `bench` — hız hedefi kısmen karşılandı, bkz. `docs/FERMAN-PLAN.md` §9 risk satırı
**Kısmen tamamlanan:** F0.12 — 5 altın dosya eklendi ve yerelde doğrulandı (test, kapsam > %85, `fermansim verify`). `.github/workflows/core.yml` kasıtlı olarak ertelendi (kullanıcı kararı); F0.12'nin "CI yeşil" kabul kriteri bu yüzden henüz karşılanmadı.
**Tamamlanan:** F0.13 denge sorusu — 6 zıt kural seti × 36 eşleşme × 1000 tohum; en iyi/en kötü set arası 75 puan fark (eşik %20). Rapor: `Balance/phase0-report.md`.
**Sonraki görev:** `.github/workflows/core.yml` eklenip CI doğrulanınca F0.12 kapanır. Faz 0'ın kalan kabul kriterleri karşılandığında Faz 1'e (F1.1) geçilebilir.

Faz 0 bitmeden Xcode projesi açma. UI yazma. Faz 0 kabul kriterleri ve F0.13 denge sorusu karşılanmadan Faz 1'e geçme.

---

## Kritik karar noktası (Faz 1 sonu)

Dikey dilim, **LLM olmadan, yalnızca seçicilerle 10 dakika eğlenceli olmalı.**

Değilse doğal dil katmanı bunu kurtarmaz. Projenin üzerinde durduğu tek varsayım budur. O noktada durup mekanik değiştirmek, devam etmekten çok daha ucuzdur.
