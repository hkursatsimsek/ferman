# CLAUDE.md — FERMAN

Bu dosya her oturumda okunur. Kısa tutulmuştur; ayrıntılı faz planı `FERMAN-PLAN.md` içindedir.

---

## Proje

iOS oyunu. Oyuncu savaşta hiçbir birime dokunmaz — savaştan önce birimlerinin davranış kurallarını yazar ("emir pusulaları"), sonra deterministik bir simülasyon çalışır. Savaş sonrası her kuralın kaç kez tetiklendiği gösterilir; öğrenme buradan gelir.

**Hedef:** iOS 26+, Swift 6 dil modu, strict concurrency `complete`, Xcode 27.

---

## Değişmez kurallar

Bunlar tartışmaya açık değildir. Bir görev bunlardan birini ihlal etmeyi gerektiriyorsa, kodu yazma — önce sor.

### 1. `FermanCore` saf kalır

`FermanCore` yalnızca `Foundation` import eder. GameplayKit, SpriteKit, UIKit, SwiftUI, Combine — hiçbiri yok. Paket Linux'ta derlenip test edilebilmelidir.

### 2. Determinizm sözleşmesi

Aynı `BattleConfig` + aynı seed = bit düzeyinde aynı `BattleResult`. Her zaman, her koşumda.

`FermanCore` içinde **yasak**:

| Yasak | Yerine |
|---|---|
| `Date()`, `DispatchTime`, herhangi bir saat | `tick` sayacı |
| `Int.random`, `arc4random`, `SystemRandomNumberGenerator` | `DeterministicRNG` |
| `Dictionary` / `Set` üzerinde sıraya duyarlı iterasyon | Sıralı `Array` veya `.sorted()` |
| `sin`, `cos`, `atan2` doğrudan çağrısı | `FixedMath` tabloları |
| `UUID()` çalışma zamanında | Deterministik ID sayacı |
| `TaskGroup`, `async let`, paralel `for` simülasyon içinde | Tek iş parçacığı |
| `Float80`, `-Ofast` | — |

`sqrt` ve temel aritmetik serbest (IEEE754 deterministik). Transandantal fonksiyonlar platform kütüphanesine bağlı olduğu için tablolanır.

Determinizmi bozan bir değişiklik yaptıysan `fermansim verify --runs 1000` kırılır. Kırıldığında **dur ve nedenini bul** — altın dosyaları yeniden üreterek geçiştirme.

### 3. Dil modeli asla sonucu belirlemez

```
Modelin yapabileceği tek şey: metni Rule dizisine çevirmek.
Ürettiği her Rule oyuncuya gösterilir. Oyuncu görmeden savaş başlamaz.
```

`RuleCompiler` bir protokoldür. Uygulamanın tamamı `ManualCompiler` (seçici tabanlı) ile oynanabilir olmalıdır. LLM bir kolaylıktır, bağımlılık değil.

`FoundationModels` import'u yalnızca `FermanAI/FoundationModelsCompiler.swift` içinde bulunabilir. Başka hiçbir dosyada olamaz.

### 4. Simüle-sonra-oynat

Simülasyon savaş başlamadan tamamına kadar koşar ve olay akışı üretir. SpriteKit bu akışı **oynatır**.

```
BattleConfig → BattleSimulator.run() → BattleResult → ReplayPlayer → BattleScene
```

Simülasyonu render döngüsüne bağlama. `BattleScene` oyun kurallarını bilmez, yalnızca olayları çizer.

### 5. GameplayKit'in tek meşru kullanımı

`FermanAI/EnemyStrategist.swift` içinde `GKMonteCarloStrategist` — düşmanın savaş öncesi ordu kompozisyonunu seçmek için. Bu simülasyonun dışındadır.

Yol bulma, sürü davranışı, kural değerlendirme elle yazılır. `GKAgent`, `GKGridGraph`, `GKRuleSystem` kullanma — kapalı kutu oldukları için determinizmi garanti edemeyiz.

### 6. Bağımlılık yok

Faz 5'e kadar `Package.resolved` boş kalır. Faz 5'te tek istisna: Google Mobile Ads, `RewardedAdProvider` protokolü arkasında, tek dosyada izole.

Bir sorunu çözmek için paket eklemeyi düşünüyorsan, önce sor.

### 7. Kelime yasağı

Kullanıcıya görünen hiçbir metinde (UI, App Store, hata mesajı) şunlar geçmez:

> kod · derle · fonksiyon · debug · script · algoritma · kural motoru · if · else · programla

Kullanılacak karşılıklar: **emir**, **pusula**, **yaz**, **düzelt**, **öncelik**.

Kod içinde teknik isimler serbest (`RuleCompiler`, `compile`) — kısıt yalnızca kullanıcı arayüzü metinleri içindir.

---

## Dizin yapısı

```
Packages/FermanCore/      saf Swift simülasyon — Foundation dışı import YOK
Packages/FermanContent/   JSON veri: birimler, seviyeler, haritalar
Packages/FermanAI/        RuleCompiler uygulamaları + EnemyStrategist
Tools/fermansim/          CLI: run / batch / verify
App/Ferman/               SwiftUI + SpriteKit
  Features/             ekran başına klasör
  Rendering/            SpriteKit replay oynatıcı
  Services/             SwiftData, GameKit, ReplayKit, monetizasyon
  DesignSystem/         token'lar ve ortak bileşenler
```

---

## Komutlar

```bash
# Test
swift test --package-path Packages/FermanCore

# Determinizm doğrulaması — her simülasyon değişikliğinden sonra
swift run fermansim verify --config Tests/Golden/battle-01.json --runs 1000

# Tek savaş
swift run fermansim run --config Tests/Golden/battle-01.json

# Denge batch'i
swift run fermansim batch --matrix Balance/matrix.json --count 10000 --out results.csv

# Uygulama
xcodebuild -project App/Ferman.xcodeproj -scheme Ferman -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Kod tarzı

- Swift 6, strict concurrency `complete`. `@unchecked Sendable` kullanma — gerekiyorsa tasarım yanlıştır.
- `FermanCore` tipleri `struct` ve `Sendable`. Simülasyon içinde referans tipi yok.
- Alan adları Türkçe değil İngilizce (`playerUnits`, `ruleFireCounts`). Yalnızca kullanıcıya görünen metinler Türkçe.
- Kısaltma kullanma: `ruleIndex`, `ri` değil.
- Zorunlu olmadıkça yorum yazma. Yazıyorsan *neden*'i yaz, *ne*'yi değil.
- SwiftUI: `@Observable`, `@MainActor`. `ObservableObject` kullanma.
- Her `Feature/` klasöründe: `XView.swift` + `XModel.swift`. Görünüm mantığı model tarafında.

---

## Test beklentisi

| Ne | Nerede | Eşik |
|---|---|---|
| Simülasyon birim testleri | `FermanCoreTests` | > %85 satır kapsamı |
| Determinizm | `fermansim verify` | 1000 koşumda özdeş checksum |
| Altın dosyalar | `Tests/Golden/` | 5 referans savaş, CI'da karşılaştırılır |
| Kural değerlendirme | Tablo testi | Her koşul × sınır eşik değerleri |
| Derleyici doğruluğu | `Tests/CompilerAccuracy/` | 150 ifadede > %88 |

Yeni simülasyon mantığı yazarken önce testi yaz. Altın dosya kırıldığında, kasıtlı bir değişiklikse yeniden üret ve commit mesajında gerekçelendir.

---

## Şu anki durum

**Faz:** 0 — Simülasyon çekirdeği
**Sonraki görev:** `DeterministicRNG` (xoshiro256**), ardından `FixedMath`, ardından `BattleMap`.

Faz 0 bitmeden Xcode projesi açma. UI yazma. `FERMAN-PLAN.md` §5'teki kabul kriterleri karşılanmadan Faz 1'e geçme.

---

## Kritik karar noktası (Faz 1 sonu)

Dikey dilim, **LLM olmadan, yalnızca seçicilerle 10 dakika eğlenceli olmalı.**

Değilse doğal dil katmanı bunu kurtarmaz. Projenin üzerinde durduğu tek varsayım budur. O noktada durup mekanik değiştirmek, devam etmekten çok daha ucuzdur.
