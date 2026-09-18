# FERMAN — Sanat yönü ve kopyalama sınırları

Faz 1.5 (görsel geçiş) için sanat yönünün uygulanabilir hâli. Üst kaynaklar: `docs/FERMAN-Design-Brief.md` §3
(duygusal çekirdek, palet, tipografi), `docs/DECISIONS.md` D24–D27. Bu belge brief'le çelişirse brief'in son
güncellemeleri ve D kayıtları geçerlidir.

---

## 1. Tek cümle

Gece yarısı bir karargâh odası, tek bir lamba, bir kum masası; üzerinde **komutanın elinin oynattığı** pirinç ve demir
döküm minyatürler. Ekranda "dijital" görünen tek şey kıvılcımdır — ve o da yalnızca senin emrin işlediğinde çakar.

## 2. Okunabilirlik gerçeği (ölçülmüş)

WCAG göreli parlaklık karşıtlığı, brief paletiyle:

| Çift | Karşıtlık |
|---|---|
| demir `#6C6660` / kum `#5E6A63` | 1,00:1 |
| pirinç `#9A7B3F` / aydınlık kum `#7A8780` | 1,06:1 |
| pirinç / demir | 1,42:1 |
| mürekkep `#0F161B` / kum · aydınlık kum | 3,2:1 · 4,9:1 |

Sonuç: **renk hiçbir şeyi tek başına taşıyamaz.** Figürü kumdan ayıran mürekkep rengi kontak gölgesi ve koyu
kenardır; takımı ayıran malzeme + **altlık şekli**dir; tipi ayıran silüettir.

Dikey masa (D26) ile hücre ≈ 23–28 pt, figür tuvali 32 pt (mızrakçı/süvari 32×44 pt) sahne noktası.

## 3. Figürler (D24)

Kamera tam yukarıdan. Tek poz seti, `zRotation` ile döner; sanat **+Y yönüne bakar**.

| Birim | Silüet kimliği | `brace` pozu |
|---|---|---|
| Mızrakçı | Mızrak gövdenin 1,5–1,7 katı ileri uzanır — şekil bir çizgidir | Mızrak indirilir, öne uzar (kirpi duvarı) |
| Okçu | İnce gövde, zırh yığını yok; önde net yay kavisi ("D"), sırtta sadak çıkıntısı | — (yaylım: 3–5 okluk yelpaze) |
| Süvari | At gövdesi yaya figürün ~1,8 katı, baş ve boyun önde; binici küçük daire | Hücum: 1,08 uzama + toz izi |
| Kalkanlı | Önü ~%60 kaplayan geniş kavisli kalkan; en geniş figür | Kalkan öne ve yana açılır (kalkan duvarı) |

**Her figürde:**
- Döküm altlık: oyuncu **yuvarlak**, düşman **sekizgen** (Bizans kurşun mührü / Kriegsspiel bloğu çağrışımı).
- Altlık kenarı takım malzemesinde: pirinç (yarıklarda bakır yeşili patina) · ham dökme demir (mat).
- Mürekkep rengi kontak gölgesi, ~%60 opaklık; lamba merkezinden uzağa 1,5–3 pt kaydırılmış.
- 1–1,5 px koyu kenar.
- En parlak noktalar üst yüzeylerde (miğfer, kalkan göbeği, at sırtı) — ışık tam tepeden pişirilir, böylece döndürünce bozulmaz.
- Küçük boyutta yedek: altlığa kazınmış tip sembolü.

**Pozlar:** `base`, `strike`, `brace`, `fallen` (+ süvari için iki kareli dörtnal). Yürüme döngüsü yok.

**Kabul testi:** her figür gri tonlamada, cihazda 1× boyutta, hem aydınlık hem karanlık kum üstünde tipi ve takımı
söylenebilir olmalı.

## 4. Hareket dili (D27)

Figürler insan değil minyatürdür. Uzuvlar canlandırılmaz; **onları hareket ettiren el** canlandırılır.

| Olay | Görsel |
|---|---|
| Konum değişiyor | Kat edilen mesafeye bağlı zıplama + eğilme (yaya 0,35 hücre, atlı 0,6 hücre adım; ±4°; tepede +%4 ölçek; gölge ayrılır) |
| `attack` | Hedefe 3–4 pt hamle (80 ms git, 150 ms dön); kalkanlıda kalkan darbesi, okçuda 1–2 pt geri tepme |
| Okçu `attack` | Ok, uçuş süresi (0,25–0,5 sn) kadar önce fırlar, kavis çizer, `attack` tick'inde iner; ayrı yer gölgesi |
| `attack` hedefi | Kâğıt rengine (`#D6D0C2`) 70 ms parlama + 1,5 pt geri itilme. **Asla kıvılcım rengi değil** |
| `death` | 120 ms devrilme, `fallen` pozu, alt katmanda **masada kalır**, küçük toz |
| `moraleBroken` | En yakın düşmandan dönme, ±0,8 pt titreme (birim kimliği + tick hash'i), hafif soluklaşma |
| `abilityUsed` | `brace` pozu / hücum uzaması + toz / ok yelpazesi |
| `ruleActivated` (yalnızca oyuncu) | Kıvılcım figürü izler; figürde 2–3 karelik duraksama; emir numarası kısa süre mühür gibi belirir |

Kurallar: her poz replay zamanının saf fonksiyonudur; ekran sarsıntısı yok (en fazla hat çöktüğünde 1–2 pt'lik tek
"masa vuruşu"); Azaltılmış Hareket açıkken zıplama/geri itme/titreme kapanır, parlama ve poz değişimi kalır.

## 5. Masa ve arazi

Harita başına bir kez pişirilen doku (`TerrainBaker`):

| Arazi | Görünüş |
|---|---|
| Açık | Kum; lamba düşüşü `SandLight` ile aynı matematik |
| Tepe | Lehmann (1799) yükseklik tarama çizgileri — eğim yönünde kısa, dik yerde kalın çizgiler, kuma bastırılmış gibi |
| Orman | Maket ağaç kümeleri (Blender render'ı), kum üstünde |
| Su | Koyu reçine kanal, lamba parıltısı |
| Moloz | Dağınık küçük taşlar |

Hücre ızgarası çok silik ve hücre boyutuna bağlı. Masa kenarı + koyu kenar durağı olan vinyet. Yerleşimler hücre
koordinatı hash'inden türetilir (rastgelelik yok, her açılışta aynı).

## 6. Kâğıt ve mühür

- Pusula: soğuk ham kâğıt, **tırtıklı** kenar, bir katlanma çizgisi, elyaf dokusu, 2 pt köşe.
- Mühür: Osmanlı mühürü gibi ters oyulmuş, **mürekkeple** basılmış (mumla değil); her baskı hafif farklı (mürekkep
  açlığı, baskı basıncı). Yalnızca fiziksel işlevi olduğu yerde: pusula damgalanırken.
- Tuğra, hat, çini, kubbe, altın yaldız yok (brief §3.0).

## 7. Ses dili

"Gözünü kapat, yine anla." Her eylemin kendi sesi vardır; kural tetiklenmesi üstüne kâğıt "tık"ı eklenir.
Kaynak: yalnızca CC0 ya da sentez; her dosya `App/Ferman/Sounds/SOURCES.md`'de kaynak ve lisansıyla.

| Olay | Ses |
|---|---|
| Geri çekil | Kum sürtünmesi |
| Siper al | Kalkan çınlaması |
| İlerle | Kâğıtla boğulmuş davul |
| Ok | Yay bırakma + iniş |
| Vuruş | Metal / ahşap |
| Ölüm | Figür devrilme tıkırtısı |
| Kural tetiklenmesi (oyuncu) | Kâğıt "tık"ı |
| Figür bırakma | Metal |
| Damga | Mühür vuruşu |

Haptik: kâğıt = yumuşak, metal = sert, damga = orta. Savaşta yalnızca oyuncu kural tetiklenmesi (hız sınırlı) ve sonuç.

## 8. Doğal dil girişinin görsel dili (Faz 2 — yalnızca tarif)

Oyuncunun söylediği ya da yazdığı emir, boş bir pusulaya bir kâtip eliyle **mürekkeple yazılır**. Belirsiz kısım
altı çizili boş bir alan olarak kalır ve oyuncu onu kadranla doldurur ("hangi mesafe?"). Ayrıştırılmış biçim asla
gösterilmez; tek çıktı kâğıt pusuladır. Hiçbir şey kod, terminal ya da "yapay zekâ" estetiği taşımaz (brief §2).

---

## 9. Kopyalama sınırları — kontrol listesi

Mekanikler ve genel ilkeler serbesttir; korunan **ifade** ve **ticari görünüm**dür.
- *Tetris Holding v. Xio Interactive* (2012): figürleri döndürme fikri korunmaz, bileşenlerin tasarımı ve bütünsel görünüm korunur.
- *Spry Fox v. 6waves* (2012): ızgara eşleştirme fikri serbest, özgün nesne hiyerarşisi ve karakter korunur.
- *DaVinci Editrice v. ZiKo* (2016): neredeyse aynı kurallar + farklı tema ve sanat = ihlal yok.
- App Store 4.1 (taklit), 4.3 (spam), 5.2.1 (fikri mülkiyet).

**Yap**
1. Mekanik ve ilkeleri serbestçe ödünç al: öncelik listesi, koşul → eylem, yerleştirme ızgarası, replay, hız, hasar dökümü.
2. Görünen her öğe FERMAN malzeme dilinden (kum, kâğıt, pirinç, demir, mürekkep mühür) ya da kamu malı tarihten gelsin; kaynağı §10'a yazılsın.
3. Kendi terimlerini kullan: pusula, mühür, cephe, doktrin. "Gambit", "tactics slot" gibi terimler yok.
4. Onaydan önce **silüet testi**: ekranın gri silüetini 5 kişiye göster, "hangi oyun bu?" diye sor. Biri belirli bir oyunun adını verirse yeniden tasarla. Sonuçlar §11'e.
5. Mağaza görselleri ve reklamlar gerçek oynanış olsun.
6. Yalnızca lisansı elde olan font ve ses.

**Yapma**
1. Hiçbir oyunun ekranını, arayüz çerçevesini, ikonunu ya da birimini çizme, üstünden boyama, renk değiştirme — "yer tutucu" için bile. Yer tutucular gönderilir.
2. Bir **birleşimi** kopyalama: yerleşim + oran + renk kodu + hareket birlikte.
3. Tanınır ticari görünüm yok: Supercell'in altın/ahşap düğmeleri, Into the Breach'in yeşil ızgarası, Gladiabots'un düğüm şekilleri, Papers, Please'in kırmızı/yeşil damgaları, FF XII'nin gambit sütunu.
4. Başka oyunun adı ya da terimleri meta veride, anahtar kelimelerde yok.
5. Eski işverenlerden dosya, belge ya da kod getirilmez.
6. CC-BY / CC-BY-SA (App Store DRM çelişkisi) ve GPL sanat kullanılmaz.
7. **Yapay zekâ ile üretilmiş sanat gönderilmez** (D25).
8. Tuğra ve hat yok.

**Ad notu:** App Store'da başka kategoride "Ferman: AI Voice Notes" adlı bir uygulama var. Lansman öncesi
TÜRKPATENT / EUIPO / USPTO sınıf 9 ve 41 marka taraması yapılmalı (Faz 7).

---

## 10. Referans günlüğü

Her ilham kaynağı: ne olduğu, lisans/durum, **neden** (yalnızca ilke, yalnızca ışık, yalnızca kompozisyon…).
Görsel dosya repoya konmaz; yalnızca bağlantı.

### Kamu malı / tarihî kaynaklar

| Kaynak | Durum | Neden |
|---|---|---|
| Kriegsspiel, Reisswitz 1824 — [archive.org](https://archive.org/details/reisswitz-1824), [Commons](https://commons.wikimedia.org/wiki/Category:Kriegsspiel) | Kamu malı | Kurgu: yazılı emir, harfiyen uygulama, harita başında muhasebe; tipli metal bloklar → sekizgen düşman altlığı |
| Askerî kum masası fotoğrafları — [Commons](https://commons.wikimedia.org/wiki/Category:Sand_tables) | Çoğu ABD federal eseri (kamu malı; dosya bazında doğrula) | Masa, kenar ve ışık kompozisyonu |
| Zinnfiguren (düz teneke askerler) — [Der Kulturbrief](https://derkulturbrief.substack.com/p/the-art-of-the-zinnfigur) | Tarihî gelenek | Döküm figür malzeme hissi; profil görünüm F4.7'ye |
| Lehmann yükseklik taraması (1799) — [Wikipedia](https://en.wikipedia.org/wiki/Hachure_map) | Tarihî teknik | Tepe arazisinin çizim dili |
| Bizans kurşun mühürleri — [Dumbarton Oaks](https://www.doaks.org/resources/seals) | Tarihî nesne | Döküm altlık ve kabartma hissi |
| Osmanlı mühür pratiği (ters oyma, mürekkep) | Tarihî pratik | Damga davranışı; mühür dokusu |

### İlke kaynağı oyunlar (hiçbir görsel öğe alınmaz)

| Oyun | Alınan ilke | Alınmayan |
|---|---|---|
| Final Fantasy XII, Dragon Age: Origins | "İlk doğru emir kazanır" öğretilmesi zor → değerlendirme kalemi | Terimler, menü düzeni |
| Gladiabots, 7 Billion Humans | Birime dokununca canlı karar; adım adım replay | Ağaç editörü, düğüm şekilleri, sanat |
| Unicorn Overlord | Koşul dağarcığı bilerek eksik tutulur (bulmaca hissi) | Resimsel sanat, menüler |
| Into the Breach | Netlik her şeyden önce; canlı gösterim | Piksel sanat, yeşil ızgara |
| Bad North | Sesle okunabilirlik | Prosedürel adalar, palet |
| Clash Royale | Silah abartısı; takım = şekil + renk | Çizgi film stili, arena, arayüz çerçevesi |
| Mechabellum, Backpack Battles | Replay'de ana atlama, tıklanabilir kayıt | Birlikler, arayüz |
| Legion TD 2 | Zaman ekseninde sonuç | Arayüz |
| Wartile | Can çubuğu yerine altlık durumu | Boyalı minyatürler |
| Papers, Please, Frostpunk | Damga = geri alınamaz taahhüt | Damga görünümü, kitap arayüzü |
| Kingdom Rush, Marvel Snap | Yeni öğe tam zamanında | Harita görünümü, kartlar |

### Kullanılan varlıklar

| Varlık | Kaynak | Lisans |
|---|---|---|
| Archivo, Archivo Narrow, Public Sans | Google Fonts / USWDS | SIL OFL (`App/Ferman/Fonts/LICENSE-OFL.txt`) |
| Figürler, arazi objeleri, mühür, ikon | `Tools/figures/` (özgün, betikli Blender) | Proje malı |
| Sesler | `App/Ferman/Sounds/SOURCES.md` | CC0 / sentez |

## 11. Silüet testi günlüğü

_(G15'te doldurulur: ekran, tarih, katılımcı sayısı, "hangi oyun?" cevapları, alınan aksiyon.)_
