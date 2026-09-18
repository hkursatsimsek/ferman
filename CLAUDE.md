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
**Faz 1 — F1.8 tamamlandı:** `App/Ferman/Features/ArmySetup/` — `ArmySetupModel` yalnızca oyuncunun bölgesini gösteriyor (brief §4.3), `BattleMap.zone(for: .player)`'ın sınırlayıcı dikdörtgenini (`gridColumns`/`gridRows`) hesaplayıp yalnızca o alt-ızgarayı çiziyor. Yerleştirme bütçesi (birim `cost` toplamı) D4'teki kural hakkından farklı bir sayı — D4 yalnızca kural hakkı için, karar yok; aşım engellenmiyor, F1.7'deki gibi sadece `BudgetMeter` kırmızıya dönüyor. `UnitPlacement.isCommander`'ın "takım başına en fazla bir" kısıtı `FermanCore`'da denetlenmiyor (yalnızca dokümante edilmiş) — `setCommander`/`clearCommander` bunu uygulama katmanında zorluyor. Sürükle-bırak: tepsiden hücreye `draggable(_:)` / `dropDestination(for:isEnabled:action:)`, ikisi de düz `String` (birim tipi ham değeri) taşıyor — özel bir `Transferable` tipi, `UTType` ya da Info.plist girdisi gerekmedi (`dropDestination(for:action:isTargeted:)` kullanılmayan eski imza; kullanılan `dropDestination(for:isEnabled:action:)` iOS 26+ için güncel). Komutan seçimi ve kaldırma `contextMenu` ile (F1.7'de kullanılan, çökme riski taşımayan jest). "Sis gösterimi" (F1.8'in kendi satırı) yalnızca görsel bir rozet — `ConstraintCard` `FermanCore`'da henüz yok (yalnızca ARCHITECTURE'ın plan listesinde), gerçek "düşman kompozisyonu gizli" mekaniği F3.2'ye kadar yok; `ArmyConstraintBadge` bir başlık/açıklama çiftini gösteriyor, hiçbir şeyi gizlemiyor. 11 model testi (yerleştirme/bütçe/komutan — F1.8'in istediği kapsam, UI testi bu adımda istenmedi) yeşil; gerçek `ContentCatalog.bundled()` + `ova` haritasıyla simülatörde görsel doğrulama yapıldı (ekran görüntüsü: bütçe, Sis rozeti, 3×14 yerleştirme ızgarası, 4 birimlik tepsi doğru göründü). **Doğrulanamayan:** dokunma/sürükleme etkileşimi elle denenemedi (F1.5'te not edilen `axe`/`SimulatorKit` eksikliği); model testleri mantığı doğruluyor, canlı jestler değil.
**Faz 1 — F1.9 tamamlandı:** `App/Ferman/AppRouter.swift` (D12) — `@Observable @MainActor` bir `[Route]` yığını (`push(_:)`), tipli `Route` enum'u (`.campaign`, `.armySetup(CampaignFront)`); `App/Ferman/Features/Home/` ve `Features/Campaign/` — `HomeView` (brief §4.1: Seferberlik/Arena/Emir Kütüphanesi/Ayarlar dikey menüsü), `CampaignView` (brief §4.2: dikey kaydırmalı cephe hattı, `FrontFlag` iğneleri), `LevelSheet` (`BottomSheet`'in kendi önizlemesindeki mock'un ilk gerçek kullanımı — `.sheet(item:)` + `.presentationDetents([.medium])` + `.presentationBackground(.clear)`). `FermanContent`'te henüz seviye verisi yok (F1.12) ve `ProgressStore` yok (F1.11); `CampaignFront.placeholders` 5 sabit cephe (2 geçildi, 1 açık — brief'teki "14. Cephe — Taş Geçit" örneğiyle aynı sayılar, 2 kilitli) — ayarlanmış içerik değil, gerçek navigasyonu ve sheet düzenini alıştırmak için yeterli, dokümante edilmiş bir yer tutucu (F1.7'nin `RulePreset`'i ve F1.8'in `ArmyConstraintBadge`'i gibi). `ContentView` artık `TokenReferenceView` yerine gerçek `NavigationStack(path:) + navigationDestination(for: Route.self)` köküne sahip; `ContentCatalog.bundled()` bir kez `init()`'te yükleniyor, hata olursa (olması beklenmez, içerik uygulamayla birlikte gönderiliyor) `Logger.critical` ile loglanıp `contentLoadFailed` metniyle çöküş yerine zarif bir düşüş gösteriliyor. Zincir şimdilik `HomeView → CampaignView → LevelSheet "Hazırlan" → ArmySetupView`'da duruyor — `ArmySetupView`'a "Emirleri Yaz" ileri butonu ve `RuleEditor`/`Battle` bağlantısı kasıtlı olarak bu adımın kapsamı dışında (düşman ordusu üretimi olmadan `Battle`'a gerçek bir `BattleConfig` kurulamaz; bu F1.12+ konusu). **Çözülen bir çökme değil ama önemli bir hata:** `HomeView.menuRow` ve `CampaignView.frontRow`'daki `Button` + `.buttonStyle(.plain)` + `Spacer()` ile esneyen bir `HStack` etiketi, satırın ortasını (raporlanan erişilebilirlik çerçevesinin ortası, XCUITest'in `.tap()`'inin hedeflediği nokta) dokunulamaz bırakıyordu — `.plain` stili, etiketin somut içeriğinin (metin/ikon glif'leri) ötesine dokunma alanı eklemiyor. Üç `AppNavigationUITests` testi de bu yüzden başarısız oldu (buton bulunuyor, etkin görünüyor, ama eylemi hiç tetiklenmiyordu); kök neden bir dizi ayıklama denemesiyle (yerel `@State` bayrağı, `NavigationStack`'i çıkarma, minimal bir düğmeyle yeniden üretme) izole edildi ve düzeltme her iki satıra da `.contentShape(Rectangle())` eklemek oldu. `FermanTests`/`FermanUITests` 54/54 (302 test koşumu) yeşil; gerçek `ContentCatalog.bundled()` + `ova` haritasıyla hem `CampaignView` hem `ArmySetupView` simülatörde görsel olarak doğrulandı (ekran görüntüleri: cephe hattı — pirinç/demir bayraklar doğru; ordu kurulumu — front'un bütçesi/Sis rozeti doğru aktı).
**Faz 1 — F1.10 tamamlandı:** `App/Ferman/Features/Debrief/` — `DebriefModel` (`@Observable @MainActor`) tek bir `BattleConfig` + `BattleResult`'tan tamamen türetiliyor, yeniden simülasyon yok. `DebriefInsightFormatter`: `FermanReplay.DebriefAnalyzer.analyze(result:)`'in bulduğu `deathCluster`/`moraleCascade` içgörülerinden, sonuca göre "ilgili taraf" (zaferde düşman, yenilgide oyuncu) için en büyük kümeyi seçip brief §4.6'daki "Okçularının %70'i 12. saniyede aynı anda öldü." kalıbıyla tek bir teşhis cümlesi kuruyor; uygun bir küme yoksa (mesela beraberlikte, ya da temiz bir savaşta) `endReason`'a göre sabit bir cümleye düşüyor ("Düşman ordusu yok edildi." vb.). Başlık ikili: zafer "Hat tutuldu.", yenilgi "Cephe yarıldı." — ikisi de §7'nin metin tonu tablosundan birebir, ikinci bir "zafer ekranı" § 10'da eksik tasarım olarak işaretliydi, bu yüzden mockup'ı olmayan tarafı brief'in kendi ton tablosundan kurdum. `TurkishNumberSuffix`'e üçüncü bir ek eklendi: `possessive(_:)` ("70" → "70'i") — genitive/ablative'in aynı `Terminal` tablosunu paylaşıyor, yalnızca tampon/ünlü seçimi farklı (D21). `OrderPhraseFormatter.pluralPossessiveGenitiveUnitName(_:)` — `unit.<id>.pluralPossessiveGenitive` (4 birim için elle eklendi, D19 gibi): Türkçenin 2. ve 3. şahıs iyelik+tamlayan zincirleri aynı yüzey biçimine ("Okçularının") düştüğü için hem oyuncunun kendi ordusu (örtük "senin") hem "Düşman " önekiyle düşmanınki için aynı katalog girdisi kullanılıyor. Emir satırları `BattleModel.TriggerRow`'un aynı "toplam içindeki pay" formülünü kullanıyor (görsel dil savaş ekranıyla tutarlı); varsayılan emir de (③) diğerleriyle aynı stilde gösteriliyor — brief'in kendi mockup'ı da onu kesikli çerçeveyle ayırmıyor. "Bu emir hiç çalışmadı." uyarısı `Color.alarm` ile (brief §3.1 — bu renk yalnızca yenilgi/kritik uyarı için ayrılmış, tam yeri). "Klibi Paylaş" `ClipRenderer` (D15, F4.7) gelene kadar devre dışı — `HomeView`'in henüz yapılmamış satırlarıyla aynı desen. "Emirleri Düzelt" bir `onFixOrders` callback'i (`LevelSheet.onConfirm` gibi View'da, Model'de değil) — `AppRouter`'a henüz bağlı değil, çünkü `Battle` da bir `Route` hedefi değil (F1.9'un notu). 8 yeni `DebriefModelTests` fonksiyonu (2'si tam "golden" cümle karşılaştırması, biri `EndReason`/`BattleOutcome`'ın 7 kombinasyonu için `@Test(arguments:)` tablo testi) ve `TurkishNumberSuffixTests`'e eklenen 2 `possessive` testi (20 el-doğrulanmış terminal + 0...100 kendiyle-tutarlılık, aynı desende) yeşil; `FermanTests`/`FermanUITests` toplam 64/64 (437 koşum, F1.9'daki 54'ten 10 yeni test). Gerçek `BattleConfig`/`BattleResult` fixture'larıyla (4 okçu, 3'ü aynı anda ölüyor) hem zafer hem yenilgi ekranı simülatörde görsel olarak doğrulandı.
**Faz 1 — F1.11 tamamlandı:** `App/Ferman/Services/ProgressStore.swift` (D14) — `FermanSchemaV1: VersionedSchema` içinde iç içe üç `@Model` sınıfı (Apple'ın kendi göç örneklerindeki gibi; ileride bir `FermanSchemaV2` aynı isimli tipleri çakışmadan tanımlayabilsin diye), boş `stages`'lı bir `FermanMigrationPlan: SchemaMigrationPlan` (v1'in göçeceği önceki bir sürüm yok, ama skill'in kendi önerisi gereği yine de gerçek bir plan olarak tanımlı). CloudKit uyumu baştan: hiçbir alan `@Attribute(.unique)`/`#Unique` kullanmıyor, hepsi opsiyonel ya da varsayılan değerli, ilişki yok. `LevelProgress.levelID` şimdilik `Int` — `CampaignFront.id`'yi yansıtıyor, çünkü `FermanContent`'in kendi seviye tipi F1.12'ye kadar yok; `lastEnemyPlan` de aynı sebeple `EnemyArmyPlan` (F3.6) yerine bugün gerçekten var olan `TeamSetup`'ı saklıyor. `ProgressStoring` protokolü (ARCHITECTURE §7'deki `RuleEditorModel`'in `progress: any ProgressStoring`'i için) yalnızca `Sendable` "snapshot" struct'ları (`LevelProgressSnapshot`, `SavedOrderSetSnapshot`, `BattleRecordSnapshot`) döndürüyor — `@Model` referans tipleri hiç dışarı sızmıyor. `recordBattle`: her deneme `attempts`'i artırır ve `lastEnemyPlan`'ı tazeler; `bestOutcome` yalnızca iyileşir (kazanılmış bir seviye sonraki bir kayıpla "kaybedilmiş" olmaz), ama `winningArmy`/`winningPrograms` her yeni galibiyette güncellenir (F3.7'nin ayna seviyesine oyuncunun *güncel* yaklaşımını vermek için, ilk kazandığı değil). Kimlik bazlı arama (`markOrderSetUsed`/`deleteOrderSet`) `model(for:)`/`registeredModel(for:)` yerine `persistentModelID` üzerinden `#Predicate` kullanıyor — ikisi de bir scratch SwiftData paketiyle elle doğrulandı: `registeredModel(for:)` context'e daha önce fetch edilmemiş bir kimlik için taze bir context'te `nil` dönüyor (snapshot'tan sonra model referansı elden çıkınca tam bu durum), `model(for:)` ise "bulunamazsa sessizce boş bir fault" döndürebiliyor; predicate her ikisinden de öngörülebilir. `UInt64 checksum` hiçbir `.codable` sarmalaması olmadan native alan olarak `UInt64.max` sınırına kadar bit-bit doğru round-trip ediyor (yine scratch pakette doğrulandı) — ARCHITECTURE'ın tablosuyla birebir. `ResultsObserver<FermanSchemaV1.SavedOrderSet, Never>`'ın `store.container`'a karşı gerçekten çalıştığı ayrı bir testle kanıtlandı (ARCHITECTURE §9'un "Modeller... iOS 27 `ResultsObserver` ile izler" taahhüdü) — ama bunu tüketen bir ekran henüz yok, `FermanAI`'ın F1.6'da `RuleEditor`'dan önce gelmesiyle aynı sıra. `ProgressStore` henüz `FermanApp`/`AppRouter`'a ya da hiçbir `Features/` modeline bağlanmadı (F1.11'in "bitti tanımı" zaten yalnızca in-memory container testleri; gerçek tüketici F1.12+ konusu). 12 yeni `ProgressStoreTests` (`App/FermanTests/`) yeşil. Bu adımda ayrıca F1.5'ten kalma gerçek bir yarış bulundu ve düzeltildi: `BattleModel.startSampling()` örnekleyici `Task`'ı asenkron olarak zamanlanıyordu, yani `phase` `.playing`'e döndüğü an `triggerRows` bir sonraki `Task` çalıştırılana kadar boş kalabiliyordu — normalde görünmüyordu ama yeni testlerin eklediği eşzamanlı yük altında `BattleModelTests.skippedStartReachesPlayingWithAResult` tekrarlanabilir şekilde başarısız olmaya başladı (izole çalışınca hep yeşildi); düzeltme `refreshTriggerRows()`'u `Task`'ı başlatmadan önce eşzamanlı çağırmak — hem yarışı kapatıyor hem de gerçek uygulamada oynatmanın ilk anındaki (çok kısa ama gerçek) boş şerit karesini de gideriyor. `FermanTests`/`FermanUITests` toplam 76/76 yeşil (F1.10'daki 64'ten 12 yeni test). **Doğrulanamayan:** disk üzerinde gerçek kalıcılık ve uygulama yeniden başlatmalar arası hayatta kalma (kapsam dışı — bitti tanımı yalnızca in-memory); CloudKit senkronu zaten F4.2 konusu.

**Faz 1 — F1.12 tamamlandı:** `Packages/FermanContent/Sources/FermanContent/LevelDefinition.swift` — saf veri (`id`, `map: MapID`, `objective`, `constraints: RuleConstraints`, `playerBudget`, `seed`, `maxTicks`, `enemy: TeamSetup`, `referenceSolution: TeamSetup`); görünen ad yok, `UnitType.id` gibi App'te `level.<id>` String Catalog anahtarı olacak (D19 deseni). `ContentCatalog` artık isteğe bağlı bir `Resources/levels.json` okuyor (dosya yoksa `levels: []`, hata değil — F0.5'in birim/harita-odaklı fixture'ları hâlâ değişmeden geçiyor) ve varsa `LevelDefinition.validateCatalog` ile çapraz referans denetliyor: sıralı/tekil `id`, `map` katalogda var mı, her iki tarafın da tüm birim tipleri katalogda var mı, yerleşimler doğru bölgede mi, takım başına en fazla bir komutan, `referenceSolution.programs` o seviyenin `constraints`'inden `RuleValidator.validate` ile hatasız geçiyor mu, ve `referenceSolution`'ın toplam birim maliyeti `playerBudget`'ı aşmıyor mu (yeni `LevelError` enum'u, `ContentError.invalidLevelCatalog` ile sarmalı). 8 seviye elle yazıldı (D6 — Seviye 1–10 elle yazılmış düşman kural/ordu; `EnemyAI` F3.4'e kadar yok, hepsi düşman tarafında yalnızca `always → advance`), yeni bir harita `Resources/maps/alan.json` üzerinde (24×14, tam açık arazi, 6 sütunluk simetrik bölgeler — `ova`/`gecit`'in 3 sütunluk kenar bölgesi kiting yapan okçuyu harita kenarına sıkıştırıp deneyi bozuyordu, bu ölçülerek bulundu). Taktik dağarcığı iki eşleşmeye dayanıyor: `mizrakci` `suvari`'yi sertçe sayar (`counters`, %150 hasar) ve `advance` ile bile kazanır; `okcu` menzilli ama `kalkan`'dan (dört birimin tek `okcu`'dan yavaş olanı) daha hızlı, o yüzden `enemyWithin(3) → retreat`, sonra `always → hold` ile sonsuz "kaç-ve-vur" yapabiliyor — `mizrakci`/`suvari`, `kalkan` gibi diğer ikisinden hızlı, bu yüzden bu numara yalnızca `kalkan`'a işliyor. **1 — varsayılan emir:** 4 `mizrakci` (`always → advance`) 3 `suvari`'yi eziyor; `constraints.maxRules = 0` ve `availableConditions/Actions` yalnızca `[.always]`/`[.advance]` — oyuncu başka bir şey yazamıyor, ders zaten varsayılanın yeterli olduğu. **2 — tek koşul:** 3 `okcu` `enemyWithin(3) → retreat` eklemeden 2 `kalkan`'a kaybediyor (kovalanıp yakın dövüşte eziliyor), ekleyince kayıpsız kazanıyor; `maxRules = 1` tam bu tek kuralı zorluyor. **3 — sıralama:** aynı okçular + `healthBelow(40) → takeCover` (en yüksek öncelik) 3 `kalkan`'a karşı; `maxRules = 2`. **4:** 2 `kalkan` (`always → hold`, siper) + 3 kiting `okcu`, 4 `kalkan`'a karşı — ikisi de tek başına yetmiyor, birlikte kayıpsız kazanıyor. **5–8:** `mizrakci` (2/3/4/6, `always → advance`) + kiting `okcu` (4/5/6/8) kombine kolu, gitgide büyüyen `suvari`+`kalkan`+`okcu` yığınına karşı (sırayla 7/10/13/17 düşman) — hepsi `constraints` bütçesi içinde (`maxRules` 3–4) elenmeyle kazanılıyor. **Bulunan gerçek bir tasarım hatası:** "yalnız varsayılan emirle" ("default-only") ne demek belirsizdi — referans çözümün kendi varsayılan eylemini (örn. `hold`) koruyup yalnızca ekstra koşullu kuralları çıkarmak mı, yoksa oyuncunun editöre hiç dokunmadığı hâl mi? İkincisini seçtim: `RuleEditorModel`'in kendi başlangıç değeriyle (`Rule(condition: .always, action: .advance)`, `RuleEditorModel.swift:90`) ve `BattleSimulator`'ın programsız birim için kullandığı örtük davranışla (§5.2) birebir aynı — ilk yorumla 4. seviye "kuralsız" bile kazanıyordu, bu da F1.12'nin bitti tanımını (seviye ≥ 2'de yalnız varsayılanla kazanılmaz) ihlal ediyordu. `LevelSolvabilityTests` (`Packages/FermanContent/Tests/FermanContentTests/`) bu tanımı doğrudan kodluyor: `referenceSolutionWins` (1...8) her seviyenin gerçek `referenceSolution`'ının kazandığını, `defaultOrderAloneLoses` (2...8) her programı bu tek-satırlık `always → advance`'e indirgeyince kaybettiğini `@Test(arguments:)` ile doğruluyor — 8 seviyenin tamamı `fermansim`'in `.build/out/Products/Release` ikilisiyle elle ordu/harita/kural denemeleri yapılarak (bir Python betiğiyle onlarca `fermansim run` çağrısı) dengelendi, sonra Swift'e taşındı; hepsi 8 farklı tohumda (1, 2, 3, 7, 13, 42, 100, 999) aynı sonucu veriyor, tek bir istisna dışında: 4. seviyenin referans çözümü `seed: 100`'de kaybediyor — kesin nedeni izlenmedi (muhtemelen `DeterministicRNG`'nin tek kullanım yeri olan `scatter` yönü ya da eşitlik bozma, çok yakın bir eşleşmede kenara kayıyor), içerikteki `seed: 1` sabit ve orada kazanıyor, ama bu R(n) benzeri bir bütçe formülü olmadan elle dengelemenin ne kadar tohuma-duyarlı olabileceğini gösteriyor. `LevelValidationTests` her `LevelError` durumunu (yinelenen/sırasız `id`, bilinmeyen harita/birim tipi, bölge dışı yerleşim, birden fazla komutan, geçersiz/bütçe aşan referans çözümü) ayrı ayrı test ediyor. `fermansim validate-content` çıktısına seviye sayısı eklendi. `FermanContentTests` 16'dan 27/27'ye çıktı; `swift format lint`, `Scripts/check-invariants.sh`, `fermansim validate-content` yeşil. **Kapsam dışı / doğrulanamayan:** `CampaignFront.placeholders` (F1.9) ve `ArmySetupModel` hâlâ bu gerçek `LevelDefinition`'lara bağlanmadı — F1.12'nin bitti tanımı yalnızca `LevelSolvabilityTests`; gerçek kampanya akışını bu içeriğe bağlamak ayrı bir adım. Linux'ta koşum yok (D23 gereği CI'a kadar ertelendi, her zamanki gibi).

**Faz 1 — F1.13 tamamlandı:** `BannedWordsTests` (`App/FermanTests/`) `Localizable.xcstrings`'e değil, `App/Ferman/**/*.swift`'teki gerçek `Text(`/`String(localized:`/`Button(`/`Label(` metin literallerine bakıyor — Xcode'un String Catalog otomatik çıkarımı yalnızca IDE'nin kendi indeksleme derlemesinde çalışıyor, headless `xcodebuild`'de hiç tetiklenmiyor, o yüzden katalog dosyası eksiksizlik için güvenilir değil. Yasaklı kelimeler kök/gövde eşleşmesiyle denetleniyor ("çalıştır" `çalışmadı`'yı yakalamıyor, CLAUDE.md'nin kendi örneği), "if"/"else" tam kelime eşleşmesiyle (aksi hâlde "hafif"/"iftar" gibi kelimeler yanlış pozitif verirdi). `App/Ferman/Services/AudioService.swift` (`AVAudioSession.ambient`) + iki yer tutucu ses dosyası (`Sounds/stamp.wav`, `Sounds/paper.wav` — Python'ın `wave` modülüyle üretilen basit sönümlü ton/gürültü, gerçek ses tasarımı değil) `BattleModel`'in damgalama koreografisine ve `RuleEditorModel`'in `reorder`/`moveUp`/`moveDown`'ına bağlandı (F1.5 ve F1.7'nin "kâğıt sesi" notları); ikisi de `audio: any AudioPlaying = SilentAudioPlaying()` varsayılan parametresiyle geldi, mevcut çağrı yerleri/testler değişmeden geçti. VoiceOver etiketleri Home/Campaign/ArmySetup/RuleEditor'a eklendi: `FrontFlag` artık durumunu renkten bağımsız anons ediyor (`FrontFlagState.accessibilityDescription`), `ArmySetupView`'ın boş/dolu yerleştirme hücreleri ve birim tepsisi artık etiketli, `TriggerBar`/`BudgetMeter` birleşik tek elemana indirildi. XXL için gerçek kırpılma bulundu ve düzeltildi: `OrderCard`'ın öncelik rozeti ve `TriggerBar`/`DebriefView`'ın sayaç sütunları `frame(width:)` kullanıyordu — ölçeklenen `FermanFont.counter` yazı tipiyle erişilebilirlik boyutlarında metni kırpıyordu; hepsi `frame(minWidth:)`'e çevrildi. `performAccessibilityAudit()` (iOS 17+) `AccessibilityAuditUITests`'te 4 ekrana (Home/Campaign/ArmySetup/RuleEditor — Battle/Debrief hiçbir giriş noktasından erişilemiyor, F1.9/F1.10'un notu, bu adımın kapsamı dışında bırakıldı) karşı koşuluyor. Bu denetim gerçek bir tasarım hatasını buldu: `Brass` renk token'ı (`#9A7B3F`) küçük metinde `SlateRaised`/`Ink` arka planına karşı tam opaklıkta bile WCAG 4.5:1'i geçmiyordu (~3.3:1); zaten "açık cephe" durumu için kullanılan daha aydınlık `#C2A05C`'ye eşitlendi (kullanıcı kararı — bu ton `FrontFlag`'in "geçildi" ile "açık" durumlarını ayıran tek fark olduğundan görsel bir ayrım kayboldu, kabul edilen bir ödünleşim). `CampaignView`'ın cephe satırları artık kum masasının değişken parlaklığına değil `Color.slateRaised.opacity(0.88)` panele karşı çiziliyor. **Kalıcı, çözülmemiş bir bulgu:** Denetim, ikon+metin birleşik satırlarda (`RuleEditorView`'ın birim sekmeleri, `HomeView.menuRow`, `CampaignView.frontRow`) tekrarlayan "Contrast failed" bildiriyor; bir ekran görüntüsünü hedef çerçevede piksel piksel örnekledim (`Okçu` etiketi) — gerçek metin ~(216,217,219) neredeyse-beyaz üzerinde ~(14,21,27) neredeyse-siyah, ~11:1 kontrast, sorun yok. Bildirilen çerçeve metnin üstündeki `UnitToken` ikonunu da kapsıyor; araç o birleşik çerçevenin içinde metin pikselini değil başka bir şeyi örnekliyor gibi görünüyor. Varsayılan gruplamayı açık `accessibilityElement(children: .ignore)` + tek elle yazılmış etikete çevirmek (temiz derlemeyle iki kez doğrulandı) hiçbir fark yaratmadı — `ArmySetupView`'ın tepsi öğeleri aynı deseni kullanıp geçtiği için evrensel bir sorun da değil. Kullanıcı kararıyla daha fazla renk/yeniden yapılandırma denemesi durduruldu; bu belirli etiketler (`AccessibilityAuditUITests.homeKnownIssueLabels`, `.campaignKnownIssueLabels`, RuleEditor'da `["Okçu", "Kalkanlı"]`) piksel kanıtıyla belgelenmiş, incelenmiş, gerçek olmadığı düşünülen bulgular olarak testten hariç tutuluyor — sessizce yutulmuyor, her biri isimle listeleniyor ki gelecekte farklı bir etiket/ekran yeni bir sorunu gizlemesin. `App/FermanTests`+`App/FermanUITests` toplam 85/85 yeşil. **Doğrulanamayan:** Battle/Debrief ekranlarının VoiceOver/XXL/kontrast durumu (erişilemez); gerçek cihazda VoiceOver ile uçtan uca gezinme (bu ortamda `axe`/`SimulatorKit` eksik, F1.5'ten beri aynı kısıt); `AVAudioSession.setActive`'ın ana iş parçacığı uyarısı (işlevsel değil, kozmetik) giderilmedi.

**Sonraki görev:** F1.14 — Kabul ve **KARAR NOKTASI**: Instruments ölçümü, `Package.resolved` boş, en az 5 kişiyle 10 dakikalık playtest.

Faz 1'de UI yazılır; LLM kodu bu fazda repoda bulunmaz (`FoundationModelsCompiler` Faz 2'ye kadar yazılmaz).

---

## Kritik karar noktası (Faz 1 sonu)

Dikey dilim, **LLM olmadan, yalnızca seçicilerle 10 dakika eğlenceli olmalı.**

Değilse doğal dil katmanı bunu kurtarmaz. Projenin üzerinde durduğu tek varsayım budur. O noktada durup mekanik değiştirmek, devam etmekten çok daha ucuzdur.
