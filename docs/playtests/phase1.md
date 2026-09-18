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
| 150 birimde 60 fps | **Doğrulanamadı** — bu ortamda fiziksel referans cihaz yok (F1.4'ten beri aynı kısıt); bkz. `CLAUDE.md`'nin F1.14 notu |

Yani mekanik ölçüm tarafı tamam; eksik olan tek şey bu belgenin asıl konusu — gerçek insanların 10 dakika
boyunca bunu eğlenceli bulup bulmadığı.

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
