# Faz 1 playtest protokolü — F1.14

**Soru (`docs/FERMAN-PLAN.md` §6, KARAR NOKTASI):** Dikey dilim, LLM olmadan, yalnızca seçicilerle 10 dakika
eğlenceli mi? Değilse doğal dil katmanı bunu kurtarmaz — projenin üzerinde durduğu tek varsayım budur.

**Durum:** Bu belge şu an yalnızca bir protokol + boş sonuç şablonu. Gerçek oturumlar (**en az 5 kişi, 10
dakika**) henüz yürütülmedi. Playtest insan katılımcı gerektirir; bu bir ajan tarafından yürütülemez veya
simüle edilemez — "Sonuçlar" ve "Karar" bölümleri kullanıcı gerçek oturumları yürüttükten sonra doldurulmalı.
O ana kadar F1.14 açık kalır.

## Neyin hazır olduğu

Bu protokolü yürütmeden önce doğrulanan, otomatik kontrol edilebilir kısımlar (F1.14'ün kendi kabul
kriterleri tablosu):

| Kriter | Durum |
|---|---|
| 8 seviye baştan sona oynanabilir | `LevelSolvabilityTests` yeşil (referans çözüm her seviyeyi kazanıyor, 2–8 arası yalnız varsayılan emirle kaybediliyor) |
| Uçtan uca gezinme | Ev → Sefer → Ordu Kurulumu → Emir Editörü → Savaş → Muhasebe artık gerçek `AppRouter` rotalarıyla bağlı (bu adımda yapıldı — önceden `RuleEditor`/`Battle`/`Debrief` hiçbir ekrandan erişilemiyordu) |
| LLM bağımlılığı yok | `grep -rI "FoundationModels" App/ Packages/` boş |
| 3. parti bağımlılık yok | `Package.resolved` hiçbir pakette yok |
| Yeniden başlatma < 100 ms | `BattleModelTests.restartReseeksWithoutResimulating` yeşil |
| Erişilebilirlik temeli | `performAccessibilityAudit()` yeşil (F1.13, bilinen/belgelenmiş istisnalar hariç) |
| 150 birimde 60 fps | **Evet** (G16, aşağıda) — simülatörde ve gerçek iPhone'da (Instruments, Release) 150 figürde 1× ve 4×'te 60 fps; açılış dışında kendiliğinden hitch yok. 8. cephe kaydı ve `update` p99 değeri hâlâ eksik |

Yani mekanik ölçüm tarafı tamam; eksik olan tek şey bu belgenin asıl konusu — gerçek insanların 10 dakika
boyunca bunu eğlenceli bulup bulmadığı.

## Performans ölçümü (G16)

**Stres girişi:** `-uiTestStressBattle YES` — taraf başına 75 figür (4 tipin hepsi, iki tarafta aynı emirler:
kalkan/mızrak duvarı, süvari hücumu, okçu siper + geri çekil), 8. cephenin arazili masası `vadi`
(`App/Ferman/Features/Battle/StressBattle.swift`). `StressBattleTests` ilk 20 saniyede hiçbir tarafın silinmediğini,
10. saniyede masada 75'ten fazla figür kaldığını doğruluyor.

**Bulunan ve düzeltilen darboğaz:** Savaş ekranı (`BattleView.body`) üst bardaki saat için `clock.currentTick`'i
okuyordu; `BattleScene` saati her karede ilerlettiği için gövde her karede yeniden değerlendiriliyordu. Her
değerlendirmede `BattleSceneView.init`, `State(initialValue:)`'a verdiği yepyeni bir `BattleScene` kuruyordu
(masa dokusu pişirme, `FigureMotion`, `BattleSoundscape`), SwiftUI da ilkini tuttuğu için bu sahne hemen çöpe
gidiyordu. Apple'ın `State` belgesi tam bunu söylüyor: varsayılan değer görünüm her kurulduğunda oluşturulur,
pahalı işi `init`'e koyma. Düzeltme: sahne görünüm ilk göründüğünde bir kez kuruluyor, `ReplayClock` saniye ve
bitiş değerlerini (`elapsedSeconds`, `isFinished`) yalnızca değiştiklerinde yazıyor, üst bar bunları okuyor
(`ReplayClockTests` bir karenin saat okuyucularını uyandırmadığını doğruluyor).

**Simülatör, iPhone 18 Pro, Release, 2026-09-24** (SpriteKit sayaçları `-showsDrawCount YES`; kare süreleri
`BattleScene`'in `OSSignposter` "update" aralıklarından, `xctrace record --instrument os_signpost`):

| Senaryo | Önce | Sonra |
|---|---|---|
| 8. cephe (~25 figür) | 20 fps · 317 düğüm · 15 çizim | **60 fps** · 317 düğüm · 17 çizim |
| Stres, 150 figür, 1× | 8,6 fps · 1031 düğüm · 29 çizim | **60 fps** · 1031 düğüm · 28–32 çizim |
| Stres, 150 figür, 1×, 40 sn | — | `update` ort. 0,98 ms · p95 1,41 · p99 1,62 · en çok 1,94 ms; kare aralığı ort. 16,69 ms, 2430 karenin 5'i > 25 ms |
| Stres, 150 figür, 4×, 25 sn | — | `update` ort. 0,84 ms · p99 1,47 ms; ilk kare 11,2 ms (tek seferlik); kare aralığı ort. 16,73 ms |

Çizim çağrısı sayısı birim sayısıyla değil katman × dokuyla büyüyor (G5'in hedefi): 25 figürde 17, 150 figürde
~30. Simülatör Mac'in GPU'sunu ve CPU'sunu kullanıyor; bu rakamlar gerçek cihazın yerine geçmez ama darboğazın
çizim değil, her karede tekrarlanan SwiftUI işi olduğunu, sahnenin kendisinin ise 16,7 ms'lik bütçenin ~%6'sını
kullandığını gösteriyor.

**Gerçek cihazda ölçüm (kullanıcı):**

1. Uygulamayı cihaza Release yapılandırmasıyla kur. Xcode'da şema → Run → Build Configuration: Release,
   Arguments: `-uiTestStressBattle YES -uiTestSandbox` (sayaçları görmek için `-showsDrawCount YES` da ekle).
2. Instruments → **Animation Hitches** şablonu (Time Profiler + Hitches). Hedef: Ferman, kayıt ~40 sn;
   `-settings.defaultSpeed 4` argümanıyla bir kez de 4× kaydet.
3. Bak: kare hızı 60'ta sabit mi (ProMotion'lı cihazda 120'ye çıkabilir), hitch sayısı, **Points of
   Interest / os_signpost** altında `BattleScene` → `update` süreleri (simülatörde ~1 ms).
4. Sonuçları bu tabloya ekle:

| Cihaz | iOS | Senaryo | fps | Hitch | `update` p99 | Not |
|---|---|---|---|---|---|---|
| iPhone 17 (ProMotion) | 27.0 | Stres 1×, 47 sn | 60 (SpriteKit sayacı, savaş boyunca) | 4 · toplam 187,5 ms · en uzun 133 ms | ölçülmedi | Dördü de ilk ~4 sn'de (açılış); sonraki ~43 sn'de hitch yok. Sayaç: 1031 düğüm |
| iPhone 17 | 27.0 | Stres 4×, 41 sn | 60 (sayaç) | 16 · toplam 708 ms · en uzun 217 ms | ölçülmedi | Açılışta birkaç; 27–31. sn arasında uygulama etkin değildi (ekran görüntüsü alındı) ve hitch'lerin çoğu orada; 34. ve 36. sn'de iki tekil hitch açıklanamadı. Sayaç: 1031 düğüm, 3 çizim |
| | | 8. cephe | | | | |

Notlar: en kısa hitch süresi 8,33 ms, yani ekran 120 Hz; sahne 60 fps'e sabit (SpriteKit'in varsayılanı), bu
yüzden Instruments kare aralığı 16,7 ms'dir. 4× kaydındaki 27–31. sn kümesi `Foreground - Active` izindeki
boşlukla çakışıyor; uygulama o sırada sistemin ekran görüntüsü arayüzü yüzünden etkin değildi, oyunun
kendi takılması sayılmadı. Savaş stres düzeneğinde 1:30'dan sonra kilitlendi (iki taraf aynı emirlerle
karşılıklı kalkan duvarında duruyor) ve ölü figürler masada kaldığı için 1031 düğümün hepsi çizilmeye devam etti.

## Kurulum

- **Build:** `App/Ferman.xcodeproj`, şema `Ferman`, `CODE_SIGNING_ALLOWED=NO` bu makinede gerekli (bkz. kök
  `CLAUDE.md` — Komutlar). Simülatörde (iPhone 18 Pro) ya da gerçek bir cihazda çalıştırılabilir; gerçek cihaz
  tercih edilir (150 birim/60 fps sorusunu da aynı oturumda gözlemlemek için).
- **Katılımcı:** en az 5 kişi, birbirinden bağımsız oturumlar (birbirlerinin oynayışını görmemeli — sonraki
  katılımcı önceki katılımcının bulduğu numarayı öğrenmemeli).
- **Facilitator (siz):** sessizce izler, yalnızca katılımcı tamamen tıkanırsa müdahale eder. Katılımcıya
  hangi tuşun ne yaptığını göstermeyin — arayüz kendi başına anlaşılır olmalı; anlaşılmıyorsa bu da bir
  bulgudur, not edin.
- **Seviye seçimi:** katılımcıyı 1. seviyeden başlatın (varsayılan emir yeterli — ısıtma turu), sonra 2.
  seviyeye geçirin (tam olarak tek bir kural eklemek gerekiyor — mekaniğin çekirdek anını en saf haliyle
  test eden seviye budur). 10 dakika yeterse 3–4. seviyeye devam edebilirler; zorunlu değil.

## Oturum akışı (~10 dakika)

1. Katılımcıya uygulamayı elden verin, tek cümlelik bir çerçeve dışında yönlendirme yapmayın: "Bu bir savaş
   oyunu ama savaşırken hiçbir şeye dokunamıyorsun — savaştan önce askerlerine ne yapacaklarını yazıyorsun."
2. Katılımcı Seferberlik → Cephe → Ordu Kurulumu → Emirleri Yaz → Savaşa Başla → Sonuç zincirini kendi
   başına yürütsün.
3. 1. seviyeyi bitirdikten sonra 2. seviyeye geçmesini söyleyin (varsayılan emirle kaybedeceği, en az bir
   kural yazması gerekeceği seviye).
4. 10 dakika dolunca (ya da katılımcı kendiliğinden dursa bile) durdurun ve görüşme sorularına geçin.

## Gözlem şablonu (her katılımcı için doldurulacak)

| Alan | Not |
|---|---|
| Katılımcı # / tarih | |
| Cihaz (simülatör / gerçek cihaz, model) | |
| Düşman ordusunu (seviye kartındaki "Karşındaki ordu" ya da masanın üstündeki demir figürler) kendi ordusunu kurmadan önce fark etti mi? | |
| İlk kuralı yazmaya kadar geçen süre | |
| Emir Editörü'nde tıkandığı an oldu mu? Nerede? | |
| Seçici akışını (koşul → parametre → eylem) kendi başına mı çözdü, yoksa açıklama mı gerekti? | |
| Kaç seviye bitirdi (10 dakikada)? | |
| Sonuç ekranını (Muhasebe) fark etti mi, okudu mu? | |
| "Bu emir hiç çalışmadı" uyarısına tepkisi | |
| Sözel tepki / yüz ifadesi (sıkılma, gülümseme, hayal kırıklığı, vb.) | |
| Kendiliğinden bir sonraki seviyeye geçmek istedi mi, yoksa durdu mu? | |
| 150 birim/60 fps hissi (gerçek cihazdaysa) | |

## Görüşme soruları (oturum sonunda)

1. Ne yaptığını bir cümleyle anlatır mısın?
2. En kafa karıştırıcı an neydi?
3. Bir kuralın işe yarayıp yaramadığını nasıl anladın?
4. Devam etmek ister miydin? Neden?
5. (1–5) Bunu tekrar oynar mıydın?

## Karar rubriği

`docs/FERMAN-PLAN.md` §9'un kendi erken uyarı sinyali: *"Faz 1 playtest'inde oyuncu tek kural yazıp
geçiyor → mekanik değiştir, devam etme."* Somutlaştırılmış eşikler:

- **Devam:** 5 katılımcının çoğunluğu (≥3/5) kendiliğinden birden fazla seviye oynadı, en az bir kuralın
  "işe yaradığını" kendi başına fark etti, ve soru 5'e ortalama ≥3 verdi.
- **Dur, mekanizmayı gözden geçir:** katılımcıların çoğunluğu tek kural yazıp bıraktı, ya da seçici akışını
  yönlendirme olmadan çözemedi, ya da soru 5'e ortalama <3 verdi.

Bu eşikler bir başlangıç noktası — 5 oturumdan çıkan asıl örüntü (nerede tıkandılar, ne güldürdü, ne
sıktı) sayılardan daha belirleyici olmalı.

## Sonuçlar

_(Boş — gerçek oturumlar yürütüldükçe doldurulacak. Her katılımcı için yukarıdaki gözlem şablonunu kopyalayın.)_

## Karar

_(Boş — 5 oturum tamamlanmadan verilemez.)_
