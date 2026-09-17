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
App/Ferman.xcodeproj/     Xcode projesi (F1.1'de oluşturuldu, D3)
App/Ferman/               SwiftUI + SpriteKit
  Features/             ekran başına klasör: XView + XModel
  Rendering/            SpriteKit replay oynatıcı, ClipRenderer
  Services/             BattleRunner, SwiftData, GameKit, CloudKit, konuşma, monetizasyon
  DesignSystem/         token'lar ve ortak bileşenler
```

---

## Komutlar

```bash
# Paket testleri (macOS). Linux doğrulaması yerelde yapılmaz, CI'da koşar (F0.12).
swift test --package-path Packages/FermanCore
swift test --package-path Packages/FermanContent
swift test --package-path Packages/FermanReplay
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
# CODE_SIGNING_ALLOWED=NO gerekli: bu makinede macOS 27.0 (26A428) + Xcode 27.0 (27A266a) ikilisinde codesign,
# içinde "Resources/" alt klasörü olan her bundle'ı (SPM kaynak paketleri dahil) imzalarken ortam hatasıyla düşüyor.
xcodebuild -project App/Ferman.xcodeproj -scheme Ferman -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test CODE_SIGNING_ALLOWED=NO

# SandTable'ın Metal shader'ı derlenecekse (F1.2+), bu makinede bir kerelik indirme gerekir:
xcodebuild -downloadComponent MetalToolchain
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

**Faz:** 1 — Dikey dilim (`docs/FERMAN-PLAN.md` §6)
**Faz 0 — tamamlanan:** F0.1 paket iskeleti ve değişmez denetimleri · F0.2 `DeterministicRNG` · F0.3 `Fixed` / `FixedMath` · F0.4 tip sözleşmesi · F0.5 içerik kataloğu ve doğrulama · F0.6 `SpatialGrid` / `FlowField` · F0.7 `RuleEvaluator` / `RuleValidator` · F0.8 `Steering` · F0.9 `Combat` / `Morale` / `Abilities` · F0.10 `BattleSimulator.run` (tick hattı, checksum, `ruleFireCounts`) · F0.11 `fermansim run` / `verify` / `batch` (`--jobs`) / `bench` — hız hedefi kısmen karşılandı, bkz. `docs/FERMAN-PLAN.md` §9 risk satırı · F0.13 denge sorusu — 6 zıt kural seti × 36 eşleşme × 1000 tohum; en iyi/en kötü set arası 75 puan fark (eşik %20), rapor: `Balance/phase0-report.md`
**Faz 0 — ertelendi:** F0.12'nin "CI yeşil" alt kriteri. 5 altın dosya eklendi ve yerelde doğrulandı (test, kapsam > %85, `fermansim verify`), ama `.github/workflows/core.yml` henüz yok; bu doğrulama proje bitimine (Faz 7 öncesi) kadar ertelendi — kullanıcı kararı, bkz. [D23](docs/DECISIONS.md). Bu pencerede Linux'a özgü bir determinizm kırılması CI olmadan yakalanamaz; her `FermanCore` değişikliğinden sonra yerelde (macOS) `fermansim verify --runs 1000` çalıştırmaya devam et.
**Faz 1 — F1.1 tamamlandı** (Xcode Cloud PR iş akışı hariç — App Store Connect'te elle kurulmalı, CLI'dan yapılamaz): Kök `FERMAN.xcodeproj` kaldırıldı, `App/Ferman.xcodeproj` oluşturuldu (D3) — iOS 27, Swift 6 dil modu, `SWIFT_APPROACHABLE_CONCURRENCY` + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `ExistentialAny` açık, uyarılar hata, `FermanCore`/`FermanContent` yerel paket referansları, bundle id `com.hksimsek.FERMAN` korunuyor, `PrivacyInfo.xcprivacy`, `Localizable.xcstrings` (kaynak dil `tr`), `UIUserInterfaceStyle = Dark`, paylaşılan şema + `Ferman.xctestplan`. iPhone 18 Pro simülatöründe `xcodebuild test` yeşil (bkz. Komutlar — `CODE_SIGNING_ALLOWED=NO` gerekli, bu makineye özgü bir codesign ortam hatası nedeniyle). `Ferman.xctestplan`'a `FermanCoreTests`/`FermanContentTests`'i eklemek denendi, Xcode'un yerel SPM hedef kimliği biçimi bulunamadığı için sessizce düştü — plan yalnızca `FermanTests`/`FermanUITests` içeriyor, paket testleri `swift test --package-path` ile ayrı koşuyor.
**Faz 1 — F1.2 tamamlandı:** DesignSystem — Asset Catalog'da 11 malzeme rengi (Any/Dark; açık mod değerleri türetilmiş, D22 gereği v1'de kullanılmıyor), Archivo/Archivo Narrow/Public Sans (OFL, statik ağırlıklar halinde paketlendi) `FontRegistrationTests` ile doğrulanıyor, tip ölçeği + 4pt boşluk + malzemeye göre yarıçap + gölge tokenları, ve tasarım brief'i §5'teki 10 bileşenin tamamı: `OrderCard` (6 durum), `OrderStack`, `ParameterDial`, `UnitToken`, `SandTable` (gerçek Metal shader — bu makinede `xcodebuild -downloadComponent MetalToolchain` ile bir kerelik ~840 MB indirme gerektirdi), `TriggerBar`, `BudgetMeter`, `FrontFlag`, `BottomSheet`, `FermanButton` (primary/outline/ghost/chip), `SpeedControl`. Hepsi #Preview (koyu/açık/XXL) ile. `TokenReferenceView` (tek referans sayfası) şimdilik `ContentView` olarak bağlı; gerçek `HomeView` F1.9'da yerini alacak.
**Faz 1 — F1.3 tamamlandı:** `Packages/FermanReplay` (D11) — saf paket, yalnızca `FermanCore`'a bağımlı, Foundation import'u bile yok. `ReplayTimeline`: 30 tick'te bir keyframe, `frame(at:)`, `fireCounts(upTo:)`; "seek sonucu = baştan katlama" `keyframeInterval: .max` ile aynı sonuca zorlayan bir testle doğrulanıyor. `DebriefAnalyzer`: ölüm kümesi, moral çöküşü ("hat bütünlüğü" — brief'te kesin formül yok, benim yorumum: bir takımın birimlerinin ≥ %33'ü aynı 0,5sn penceresinde moral kaybediyor), hiç çalışmayan/baskın kural, eşzamanlı aktivasyon, kilit an — hepsi typed `DebriefInsight`, metinleştirme yok (D11). 11 test, `swift test --package-path Packages/FermanReplay` yeşil.
**Faz 1 — F1.4 tamamlandı:** `App/Ferman/Rendering/` — `BattleScene` (SKScene) `ReplayTimeline`'ı çizer, oyun kuralı bilmez (kural 4): spawn taramasından tek seferlik oluşturulan birim havuzu (kare başına düğüm yok), kesirli tick üzerinden interpolasyon, kural tetiklenince pooled `SKEmitterNode` kıvılcım, kum ışığı için gerçek `SKShader` (`SandLight.fsh` — DesignSystem'in Metal shader'ının GLSL karşılığı), dokunmayla birim etiketi (şimdilik yalnızca yapısal veri — birim tipi + emir index'i; gerçek Türkçe emir metni RuleProgram/String Catalog'un olduğu F1.7+'ta eklenir), `OSSignposter` ile `update(_:)` ölçümü. `ReplayClock` (`@Observable @MainActor`) oynatma/duraklatma/hız/seek'i sürüyor, `BattleConfig.ticksPerSecond` kullanıyor. `BattleSceneView` `SpriteView` ile sarmalıyor. Senkronik bir hata bulundu ve düzeltildi: ilk denemede olayları tick sırasına göre eklemedim, `ReplayTimeline`'ın sıralı akış varsayımını kırdı — artık dokümante edilmiş bir önkoşul. Simülatörde gerçek bir savaşla (20 birim, hareket/ölüm/kural olayları) görsel doğrulama yapıldı. **Doğrulanamayan:** "referans cihazda 150 birim 60 fps" — Instruments/gerçek cihaz gerektiriyor, bu ortamda yok; mimari (havuzlama, kare başına tahsis yok) buna göre kuruldu ama ölçülmedi.
**Faz 1 — F1.5 tamamlandı:** `App/Ferman/Services/BattleRunner.swift` (`@concurrent`, `BattleSimulator.run`'ı ana aktör dışına taşır) ve `Features/Battle/` — `BattleModel` (`@Observable @MainActor`) savaşı bir kez simüle eder, brief §3.5 koreografisini (pusulalar sırayla damgalanır → yığın kayar → kamera kum masasına iner → lamba titrer → savaş başlar) durum makinesiyle sürer, sonra `ReplayClock`/`ReplayTimeline`'ı kurup oynatmaya geçer. Koreografi atlanabilir (dokununca hızlanır) ve Reduce Motion'da anında `.playing`'e geçer. Alt şerit `ReplayTimeline.fireCounts(upTo:)`'u kendi 10 Hz döngüsüyle örnekliyor (SpriteKit'in 60 fps kare döngüsüne bağlı değil, ARCHITECTURE §8). Bir birime dokununca (yalnızca oyuncu tarafı) şerit o birimin tipinin programına geçiyor. `restart()` yalnızca `clock.seek(to: 0)` yapıyor, yeniden simülasyon yok. `BattleHUD` üst bar (süre, geri sar, duraklat, `SpeedControl`, `glassEffect`) ve tetiklenme şeridini çiziyor. Metin: çağıran taraf zaten biçimlendirilmiş `OrderStack.Item` dizisi veriyor — `BattleModel` `Condition`/`Action` bilmiyor, o `OrderPhraseFormatter`'ın işi (F1.7). 4 model testi (`BattleModelTests`) yeşil; simülatörde gerçek bir savaşla görsel doğrulama yapıldı (üst bar, koreografi, kum masası, tetiklenme şeridi çalışıyor). **Doğrulanamayan:** dokunmayla birim seçme davranışı — bu makinede `axe`/`SimulatorKit` eksik olduğu için simülatörde dokunma otomasyonu çalışmıyor; kod incelemesiyle doğrulandı, elle dokunulmadı. Koreografinin tam 1,4 sn'lik hissi de (F1.4'teki fps gibi) ölçülmedi.
**Faz 1 — F1.6 tamamlandı:** `Packages/FermanAI` (D18) — yalnızca `FermanCore`'a bağımlı yeni paket (Linux zorunluluğu yok, ama bu adımda Foundation dışı bir import da yok). `RuleCompiler<Input>: Sendable` protokolü (`compile(_:context:) async throws(RuleCompileError) -> [Rule]`), `CompileContext` (unitType, constraints, availableUnitTypes, remainingRuleBudget), `RuleDraft` (seçici durumu: `conditionKind` + duruma göre tek bir parametre alanı — numeric/unitType/terrain —, `actionKind` + `focusFire`'ın opsiyonel hedefi). `ManualCompiler: RuleCompiler<RuleDraft>` her `ConditionKind`/`ActionKind`'i derliyor; eksik parametre `RuleCompileError.missingConditionParameter` fırlatıyor (`RuleValidator`'a hiç ulaşmadan). 9 test yeşil. `grep -rI "FoundationModels" App/ Packages/` boş (F1.6'nın bitti tanımı). Henüz App'e paket referansı olarak eklenmedi — ilk tüketici F1.7'deki `RuleEditorModel`.
**Faz 1 — F1.7 tamamlandı:** `App/Ferman/Features/RuleEditor/` — `RuleEditorModel` (`@Observable @MainActor`) her birim tipi için `ordersByUnitType` + sabit `defaultRuleByUnitType` (koşulu her zaman `.always`, eylemi düzenlenebilir) tutuyor, `ManualCompiler` üzerinden derliyor, her değişiklikte `RuleValidator.validate` çalıştırıp geçersiz kartları `OrderCardState.disabled`'a çeviriyor. `RuleEditorView`: birim sekmeleri, `BudgetMeter` (ordu geneli sayaç, D4), boş durum + "Hazır emir setlerini gör" (3 dahili `RulePreset`, F4.8'in Emir Kütüphanesi'nden farklı — kayıtlı değil, sabit), `reorderContainer(for:isEnabled:move:)` + `reorderable()`, sayısal parametreye dokununca `ParameterDial` yerinde açılıyor (mevcut F1.2 bileşeni yeniden kullanıldı), tam seçici sheet'i `RulePickerSheet` (koşul → parametre → eylem, varsayılan emrin eylemini de aynı sheet düzenliyor), VoiceOver `moveUp`/`moveDown` accessibility action'ları. `OrderPhraseFormatter` + `TurkishNumberSuffix`: FERMAN-PLAN §5.3/5.4'teki TR metinler, 0–100 arası genitif/ablatif ek uyumu (D21) — `String(localized: String.LocalizationValue(interpolatedKey))` dinamik anahtar için YANLIŞ çıktı: interpolasyon anahtarın kendisinde yer tutucuya dönüşüyor (`"%d elmam var"` deseni için tasarlanmış, anahtar seçmek için değil); düzeltme `Bundle.localizedString(forKey:value:table:)` ile yapıldı — `unit.<id>` (D19) için 4 katalog girdisi elle eklendi. `FermanAI` Xcode projesine yerel paket referansı olarak eklendi (pbxproj elle düzenlendi — bu projede ilk üçüncü paket dışı ekleme). `RuleEditorModel.move(_:)` `ReorderDifference`'ı açığa çıkarıyor ama gerçek mantık test edilebilen `reorder(sources:before:)`'da (`ReorderDifference`'ın herkese açık initializer'ı yok). `FermanTests` 29/29, `FermanUITests` 4/4 yeşil (F1.7'nin yeni testleri dahil; RuleEditor'a `-uiTestRuleEditor` launch argument'ıyla erişiliyor, `AppRouter` henüz yok); simülatörde görsel doğrulama yapıldı. **Doğrulanamayan / risk:** Canlı sürükleyerek sıralama — XCUITest'in `press(forDuration:thenDragTo:)` sentetik jesti bu `reorderContainer`/`reorderable()` çiftinde uygulamayı güvenilir şekilde çökertti (çökme AppKit/UIKit'in kendi `DragContainerStorage.payload(for:)` içinde bir `preconditionFailure` — bizim kodumuz değil). API WWDC26 ile geldiği için simülatöre/sentetik jeste özgü olabilir; gerçek cihazda elle denenmeden gönderilmemeli. "Kâğıt sesi" (F1.7'nin "haptik + kâğıt sesi" maddesi) eklenmedi — `AudioService`/ses varlıkları F1.13'e kadar yok; haptik (`sensoryFeedback`) var.
**Sonraki görev:** F1.8 — `ArmySetupView` / `ArmySetupModel`: `draggable` / `dropDestination` (`Transferable`), bütçe aşımı, komutan seçimi, Sis gösterimi.

Faz 1'de UI yazılır; LLM kodu bu fazda repoda bulunmaz (`FoundationModelsCompiler` Faz 2'ye kadar yazılmaz).

---

## Kritik karar noktası (Faz 1 sonu)

Dikey dilim, **LLM olmadan, yalnızca seçicilerle 10 dakika eğlenceli olmalı.**

Değilse doğal dil katmanı bunu kurtarmaz. Projenin üzerinde durduğu tek varsayım budur. O noktada durup mekanik değiştirmek, devam etmekten çok daha ucuzdur.
