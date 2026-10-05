# Faz 2 — cihazda elle yapılacak kontroller (F2.3, F2.5, F2.6)

Bu kontroller fiziksel bir iPhone gerektiriyor. Simülatörde ya da Mac'te yapılamıyor: Apple'ın canlı ses örneği simülatörde çalışmıyor, modelin hızı da cihaza bağlı. Otomatik testlerin kapsadıkları en altta listeleniyor.

Her kontrolün sonucunu tarih ve cihazla birlikte "Sonuç" sütununa yaz.

## Hazırlık

- iOS 27 yüklü bir iPhone. F2.3'ün gecikme hedefi iPhone 16 sınıfı için tanımlı.
- Uygulamanın cihaza kurulu bir derlemesi.
- Bir seferliğine internet bağlantısı (ses paketini indirmek için).

## F2.6 — Apple Intelligence kapalıyken

Ayarlar → Apple Intelligence ve Siri → Apple Intelligence: **kapalı**.

| # | Adım | Beklenen | Sonuç |
|---|---|---|---|
| 1 | Sefer → 3. cephe → Hazırlan → 3 okçu yerleştir → Emirleri Yaz | Editör açılıyor, alttaki alan "Emri yaz" diyor | |
| 2 | "düşman 3 kareden yakınsa geri çekil" yaz → Yaz | Pusula anında, mürekkeple yazılarak iniyor; "Mühürle" görünüyor | |
| 3 | "selam komutan" yaz → Yaz | Bekleme yok; altta örnekli bir cümle çıkıyor, pusula inmiyor | |
| 4 | "protect the general if morale is under 30%" yaz | Model kapalı olduğu için şablonun yanıtı: "Ne yapacaklarını anlayamadım…" cümlesi çıkıyor | |
| 5 | 2. adımdaki pusulayı mühürle → Savaşı Başlat → Sonuç | Savaş oynuyor, Muhasebe açılıyor | |
| 6 | Mikrofon (aşağıdaki F2.5 kurulumundan sonra) | Mikrofon Apple Intelligence'tan bağımsız; çalışıyor | |

## F2.3 — Apple Intelligence açıkken

| # | Adım | Beklenen | Sonuç |
|---|---|---|---|
| 1 | Editörü aç, 2–3 sn bekle, "protect the general if morale is under 30%" yaz | Pusula: "moralim %30'un altındaysa KOMUTANI KORU"; ~2 sn içinde | |
| 2 | "düşman 3 kareden yakınsa geri çekil" yaz | Anında (şablon okuyor, model sorulmuyor) | |
| 3 | Şablonun okuyamadığı 10 farklı cümleyi yaz, her birinin süresini kronometreyle ölç | p95 < 2,5 sn; 2 sn'yi geçen cümlede şablonun yanıtı geliyor | |
| 4 | Instruments → Foundation Models aracı, bir oturum | Her oturum < 800 token | |

## F2.5 — Sesli emir

| # | Adım | Beklenen | Sonuç |
|---|---|---|---|
| 1 | Editörde alanın içindeki mikrofona dokun | "Sesle emir" iletişim kutusu: paket bir kez iner, sonra internetsiz çalışır | |
| 2 | "Ses paketini indir" | İlerleme çubuğu, ardından mikrofon hazır | |
| 3 | Mikrofona dokun → mikrofon iznini ver | Sistem izin metni Türkçe: "Emirlerini sesle söyleyebilmen için…" | |
| 4 | "düşman üç kareden yakınsa geri çekil, başka durumda ilerle" de → Söylemeyi bitir | Konuşurken metin canlı akıyor; bitince iki pusula iniyor (koşullu emir + varsayılan) | |
| 5 | **Uçak modunu aç**, 4. adımı tekrarla | Aynı sonuç: döküm çevrimdışı çalışıyor (F2.5'in bitti tanımı) | |
| 6 | Mikrofon iznini Ayarlar'dan kapat, mikrofona dokun | "Mikrofon izni kapalı…" cümlesi; uygulama çökmüyor | |
| 7 | Konuşurken oyun sesleri (ortam döngüsü) | Kayıt sırasında ve sonrasında sesler bozulmuyor; bitince ortam sesi geri geliyor | |
| 8 | Cihazın dili İngilizce iken "retreat if an enemy is within three cells" de | İngilizce döküm ve doğru pusula | |

## Otomatik testlerin kapsadıkları

- Model kapalıyken baştan sona akış: `AppleIntelligenceOffUITests.testAWholeFrontIsPlayableWithoutTheModel` (simülatör, `-uiTestAppleIntelligenceOff`).
- Zincirin model kapalı/yavaş/hatalıyken şablona düşmesi: `CompilerChainTests`.
- Sahte modelle derleyici: `FoundationModelsCompilerTests`.
- Gerçek modelle doğruluk (Mac): `FERMAN_MODEL_ACCURACY=1 swift test --package-path Packages/FermanAI --filter "chainOn|modelOn" --no-parallel`, raporlar `Packages/FermanAI/Tests/CompilerAccuracy/Reports/`.
- Mikrofon akışı (sahte dinleyici): `SpokenOrdersTests`, `RuleEditorUITests.testASpokenOrderLandsAsSlipsToSeal`.
- Gerçek Türkçe döküm metinleri (Mac'te, sistemin Türkçe sesiyle): `TemplateCompilerTests.readsTranscribedSpeech`.
