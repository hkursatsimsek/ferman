# FERMAN — Tasarım Brief'i
### *(Claude Design'a doğrudan yapıştırılacak prompt)*

---

Bir iOS oyununun arayüz tasarımını yapmanı istiyorum. Aşağıda ürünü, duygusal çekirdeğini, sanat yönünü, token sistemini ve ekran ekran içeriği veriyorum. Türkçe metinler gerçek — yer tutucu kullanma, verdiğim metinleri kullan.

---

## 1. Ürün

**FERMAN** — iPhone için tur tabanlı otomatik savaş oyunu.

Oyuncu savaşta hiçbir birime dokunmaz. Savaştan **önce** birimlerinin nasıl düşüneceğini yazar:

> "Okçular düşman üç kareden yakına gelince geri çekilsin."

Bu cümle, ekranda **emir pusulası** adını verdiğimiz küçük fiziksel kartlara dönüşür. Oyuncu pusulaları öncelik sırasına dizer, sonra savaşı başlatır ve 60 saniye boyunca ordusunun kendi yazdığı mantıkla kazanmasını ya da dağılmasını izler.

### Duygusal çekirdek

> **Niyet ile sonuç arasındaki mesafe.**

Askerler emri harfiyen uyguladı. Ve tam da bu yüzden öldüler. Oyuncu savaş sırasında değil, savaştan sonra öğrenir. Arayüzün tamamı bu duyguya hizmet etmeli: yazdığın şey ciddi bir şeydir, sonuçları vardır, ve geri alamazsın.

### Kitle

25–45 yaş, strateji ve bulmaca oyunları oynayan, düşünmeyi seven oyuncular. Programcı değiller ve programcı olmak da istemiyorlar.

---

## 2. En önemli kısıt — bunu ihlal edersen tasarım başarısız

> ## Arayüz bir kod editörüne benzemeyecek.

Bu oyunun ticari hayatındaki bir numaralı risk, oyuncunun mağaza görsellerine bakıp "bu bir programlama oyunu" diye düşünüp geçmesidir.

**Yasak liste:**

| Yasak | Neden |
|---|---|
| Monospace/daktilo yazı tipi (kural editöründe) | Doğrudan "kod" sinyali |
| Sözdizimi renklendirmesi, girintili bloklar | IDE görüntüsü |
| `if` / `else` / `→` / `{}` / `==` sembolleri | Aynı |
| Terminal estetiği (siyah zemin, fosforlu yeşil) | Aynı |
| "Derle", "çalıştır", "debug", "fonksiyon" gibi kelimeler | Kelime seçimi tasarımın parçasıdır |

**Bunun yerine:** kural, üzerine damga vurulmuş bir kâğıt emir pusulasıdır. Onu düzenlemek kod yazmak değil, **bir kartı seçip yerine koymaktır.**

---

## 3. Sanat yönü — "Kum Masası"

### 3.0 İsim ve dozaj — önce bunu oku

**Ferman**, mühürlenmiş ve yazılmış bir emirdir: geri alınamaz, tartışılmaz, harfiyen uygulanır. Oyunun duygusal çekirdeği tam olarak budur.

İsim Osmanlı çağrışımı taşıyor. Aşağıdaki sanat yönü ise kurumsal-askerî ve **dönemsiz**. Bu ikisi arasındaki mesafeyi bilinçli yönet:

| Dozaj | Ne demek |
|---|---|
| ✅ **Alt ses** | Mühür izi, damga dokusu, ferman kâğıdının elyaf deseni, emir pusulalarının katlanma çizgileri, kurşun mühür ağırlığı |
| ❌ **Tam tema** | Tuğra, hat sanatı, çini motifi, kubbe, sarık, altın yaldız, kırmızı-yeşil Osmanlı paleti |

Kural: bir Osmanlı öğesi ancak **fiziksel bir işlev** taşıyorsa girer. Mühür girer, çünkü pusula damgalanır. Tuğra girmez, çünkü sadece süstür.

Pratikte bu, palette hiçbir değişiklik demek değil — §3.1 olduğu gibi kalıyor. Fark yalnızca doku ve detayda: pusula kâğıdının kenarı düz kesik değil hafif tırtıklı, damga dairesel ve aşınmış, birim jetonlarının altlığı dökme kurşun.



Oyunun dünyası gece yarısı bir karargâh odasıdır. Tek bir lamba var. Odanın ortasında bir **kum masası** — üzerine haritanın kabartıldığı, birliklerin küçük döküm figürlerle temsil edildiği fiziksel bir masa. Duvarda emir pusulalarının asıldığı bir pano.

Her şey **malzeme**dir: soğuk kum, ham kâğıt, oksitlenmiş pirinç, çiğ demir, kurşun boya. Ekranda "dijital" görünen tek bir şey var, o da §3.2'de.

### 3.1 Renk

Palet neredeyse tamamen malzeme renklerinden oluşur. Marka rengi yok.

```
--ink          #0F161B    Uygulama zemini — gece odası, mavi-gri, sıcak değil
--slate        #1B262D    Panel ve yüzeyler
--slate-raised #24323A    Yükseltilmiş yüzey (kart, sheet)
--sand         #5E6A63    Kum masası yüzeyi — soğuk gri-yeşil
--sand-lit     #7A8780    Lambanın vurduğu bölge (masada tek ışık kaynağı)
--paper        #D6D0C2    Emir pusulası — soğuk ham kâğıt, krem DEĞİL
--paper-ink    #2A2622    Pusula üstündeki mürekkep
--brass        #9A7B3F    Senin ordun. Metal kenarlar, çerçeve detayı
--iron         #6C6660    Düşman ordusu. Boyasız dökme demir
--spark        #6FE3F5    ⚡ §3.2'ye bak
--alarm        #B34A3A    Yalnızca yenilgi ve kritik uyarı
```

Kum masası düz renk değil: `--sand-lit` merkezden `--sand`'e doğru yumuşak bir ışık düşüşü var. Işık tek yönlü ve yukarıdan.

### 3.2 ⚡ Tek cesur hamle: kıvılcım

`--spark` rengi arayüzün **hiçbir yerinde** kullanılmaz. Butonlarda yok, başlıklarda yok, vurgu olarak yok.

Yalnızca **bir kural tetiklendiği anda** görünür:
- Savaş ekranında, o kuralı uygulayan birimin üzerinde bir kıvılcım çakar
- Sağdaki pusula listesinde ilgili pusula bir an için kıvılcım rengiyle çerçevelenir
- Savaş sonrası analizde, tetiklenen kuralların sayaç çubukları bu renktedir

Böylece renk bir dekorasyon değil, oyunun anlamının kendisi olur: *senin yazdığın mantık şu anda işliyor.*

Tüm cesareti buraya harca. Başka hiçbir yerde parlak renk kullanma.

### 3.3 Tipografi

İki aile. İkisi de kurumsal/resmî karakterde — askerî bir kurumun basılı evrakı gibi, ama modern ve temiz.

| Rol | Yazı tipi | Kullanım |
|---|---|---|
| Başlık ve etiket | **Archivo** (SIL Open Font License) | Dar, sıkı harf aralığı, "tabela" karakteri. Sıkıştırılmış varyantı seviye numaraları ve sayaçlar için |
| Gövde ve pusula metni | **Public Sans** (Open Font License) | Hümanist, yüksek okunabilirlik, resmî evrak karakteri |

İkisi de açık lisanslı ve ikisi de yapay zekânın varsayılan tercihi değil.

**Tip ölçeği:**

```
Ekran başlığı      Archivo Semibold   28 / 32   tracking −0.02em
Bölüm başlığı      Archivo Medium     20 / 26   tracking −0.01em
Pusula koşulu      Public Sans Reg    17 / 24
Pusula eylemi      Public Sans Bold   17 / 24
Gövde              Public Sans Reg    15 / 22
Yardımcı metin     Public Sans Reg    13 / 18   opaklık 0.65
Sayaç / rakam      Archivo Medium     tabular figures
```

**Kurallar:**
- Rakamlar için ayrı bir monospace aile kullanma. Gövde ailesinin **tabular figür** varyantını kullan.
- Tümü büyük harf (ALL CAPS) etiket kullanma. Cümle düzeni yeterli.
- Başlıkta tek bir kelimeyi renkle veya italikle vurgulama.
- Satır uzunluğu 60 karakteri geçmesin.

### 3.4 Köşe yarıçapı — hiyerarşiye göre değişir

Tek bir yarıçapı her şeye uygulama. Malzeme ne ise yarıçap odur:

```
Emir pusulası     2pt      kâğıt keskin kesilir
Panel / sheet    14pt      ahşap / metal muhafaza
Buton             8pt
Birim jetonu    tam yuvarlak   döküm figür (düşman: sekizgen altlık — D24)
Kum masası        0pt      masanın kendisi, kenarı yok
```

### 3.5 Hareket

**Tek koreografik an var.** "Savaşı başlat"a basıldığında:

```
1. Pusulalar sırayla damgalanır (her biri 60ms arayla, hafif ölçek darbesi + haptik)
2. Pusula yığını panodan kayar ve kadraj dışına çıkar
3. Kamera kum masasına iner (0.5sn, yumuşak)
4. Lamba bir an titrer, sonra savaş başlar
```

Toplam ~1.4 saniye. Atlanabilir (dokununca hızlanır).

Bunun dışında: sadece kullanıcının eylemine cevap veren hareket. Her kartta hover geçişi, her bölümde fade-and-slide-up girişi **yapma**. Reduce Motion açıkken tüm sekans anında kesilir.

---

## 4. Ekranlar

iPhone dikey, 393×852pt referans. Karanlık mod birincil; açık mod varyantını da üret ama karanlık olan asıl tasarımdır.

### 4.1 Ana Menü

Kum masası kısmen görünür, üzerinde son savaşın donmuş kadrajı. Alt kısımda dikey menü.

```
Seferberlik        →  14. cephe
Arena              →  3 maç bekliyor
Emir Kütüphanesi
Ayarlar
```

Üst sağda küçük kaynak göstergesi. Reklam yok, banner yok, oyuncu sayısı yok.

### 4.2 Seviye Haritası — "Cephe"

Dikey kaydırmalı bir hat. Her seviye kum masasına saplanmış bir bayrak iğnesi. Geçilen seviyeler pirinç, kilitli olanlar demir.

Bir iğneye dokununca alttan sheet açılır:

```
14. Cephe — Taş Geçit

Düşman bütçesi     420 puan
Senin bütçen       310 puan
Kural hakkın       6
Kısıt              Sis — düşman kompozisyonu gizli

[ Hazırlan ]
```

Bütçe farkı (420'ye karşı 310) görsel olarak vurgulanmalı — bu kasıtlı bir dengesizlik ve oyuncunun bunu fark etmesi gerekiyor.

### 4.3 Ordu Kurulumu

Kum masası dikey durur (D26): senin konuşlanma bölgen masanın alt kısmında, düşman bölgesi üstte (Sis varsa toz perdesiyle örtülü). Altta birim tepsisi.

```
┌────────────────────────────────┐
│  Bütçe   248 / 310             │
├────────────────────────────────┤
│                                │
│     ▫ ▫ ▫                      │   yerleştirme ızgarası
│     ▫ ● ▫        (kum masası)  │   ● = yerleştirilmiş birim
│     ▫ ▫ ▫                      │
│                                │
├────────────────────────────────┤
│  Mızrakçı  Okçu  Süvari  Kalkan│   tepsi — sürükle-bırak
│    40p      55p    80p     35p │
├────────────────────────────────┤
│         Emirleri Yaz  →        │
└────────────────────────────────┘
```

Birimler döküm metal figür gibi: silüet okunaklı, detay az, altlarında hafif gölge. Seçili birim pirinç bir halka ile çevrelenir.

> **Güncelleme (Faz 1.5, D24):** Figürler üstten görülen döküm minyatürlerdir ve tipleri silüetten okunur — mızrakçının mızrağı gövdesinden uzun, okçunun önünde yay kavisi ve sırtında sadak, süvarinin at gövdesi, kalkanlının geniş kavisli kalkanı. Oyuncu figürleri yuvarlak, düşman figürleri sekizgen altlıkta durur; gölge mürekkep rengindedir, çünkü pirinç ve demir kum üstünde neredeyse aynı parlaklıktadır. Ayrıntı: `docs/design/ART-DIRECTION.md`.

### 4.4 Emir Editörü — **oyunun kalbi**

En çok özen isteyen ekran. Üstte birim seçici, ortada pusula yığını, altta giriş alanı.

```
┌────────────────────────────────┐
│  ◀  Okçu              6 pusula ▸│   birim sekmeleri, yatay kaydırma
│     Mızrakçı · Okçu · Süvari    │
├────────────────────────────────┤
│                                │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━┓  │
│  ┃ ① düşman 3 kareden yakınsa┃  │   ← emir pusulası
│  ┃   GERİ ÇEKİL              ┃  │      kâğıt dokusu, 2pt köşe
│  ┃                     ⠿     ┃  │      sağda tutamak (sürükle)
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━┛  │
│                                │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━┓  │
│  ┃ ② canım %35'in altındaysa ┃  │
│  ┃   SİPER AL           ⠿    ┃  │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━┛  │
│                                │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐  │
│  │ ③ başka durumda           │  │   ← varsayılan pusula
│  │   İLERLE                  │  │      kesikli kenar, silik
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  │
│                                │
├────────────────────────────────┤
│ 🎙  Emri söyle ya da yaz        │   ← doğal dil girişi
│                      [ Yaz ]   │
├────────────────────────────────┤
│         ▶  Savaşı Başlat       │
└────────────────────────────────┘
```

**Pusula anatomisi — çok önemli:**

Her pusula iki bölümdür ve bu bölümler **tipografiyle** ayrılır, renkle veya kutuyla değil:

- **Koşul** — normal ağırlık, mürekkep rengi: *"düşman 3 kareden yakınsa"*
- **Eylem** — kalın, biraz büyük: **"GERİ ÇEKİL"**

Sayısal parametreler (`3`, `%35`) pusulanın içinde dokunulabilir. Dokununca pusulanın üzerinde küçük bir kadran açılır — ayrı bir ekrana gitmez. Bu, "düzenlemek kolay" hissinin kaynağı.

Sol üstteki daire içindeki numara öncelik sırasıdır. Pusulayı sürükleyip yığında yukarı taşımak önceliği artırır. Bu jest **fiziksel** hissetmeli: kâğıt sesi, haptik darbe, hafif eğilme.

**Doğal dil girişi:** Oyuncu yazar veya söyler. Sonuç bir pusula olarak yığına **damgalanarak** eklenir. Yanlışsa dokunup düzeltir. Bu alan öne çıkarılmaz — küçük ve mütevazı durur, çünkü oyunun asıl arayüzü pusulalardır.

**Boş durum:**

```
Henüz emir yok.

Askerlerin emir almazsa düşmana doğru
yürür ve öldürülene kadar dövüşür.

[ Hazır emir setlerini gör ]
```

Özür dileyen değil, yönlendiren bir ton. Ne olacağını açıkça söylüyor.

### 4.5 Savaş Ekranı

Tam ekran kum masası, üstten görünüm. Kontrol yok, sadece izleme.

> **Güncelleme (Faz 1.5, D26/D27):** Masa dikey durur — senin ordun altta, düşman üstte, savaş aşağıdan yukarı akar. Figürler komutanın eliyle oynatılıyormuş gibi hareket eder (zıplama, hamle, uçan oklar); ölen figür devrilir ve masada kalır. Vuruş parlaması kâğıt rengindedir; kıvılcım yalnızca senin emrin tetiklendiğinde çakar.

```
┌────────────────────────────────┐
│  00:23          ⏸  1× 2× 4×    │   minimal üst bar
├────────────────────────────────┤
│                                │
│         (kum masası)           │
│      ●●●      ▪▪▪              │
│     ●  ●     ▪   ▪             │
│                                │
│              ⚡ ②              │   ← kural tetiklendi
│                                │
├────────────────────────────────┤
│  ① ━━━━━                       │   pusula sayaçları
│  ② ━━━━━━━━━━━━━  ⚡           │   canlı dolar
│  ③ ─                           │
└────────────────────────────────┘
```

Alttaki şerit en önemli parça: her pusulanın kaç kez tetiklendiği **canlı olarak** dolar. Oyuncu savaşı izlerken hangi mantığının çalıştığını eş zamanlı görür. Bir pusula tetiklendiğinde o çubuk kıvılcım rengiyle bir an parlar.

Bir birime dokunulduğunda üzerinde küçük bir etiket belirir: şu anda hangi pusulayı uyguluyor.

### 4.6 Savaş Sonrası Analiz

Oyunun öğretme mekanizması burada. Zafer ekranı değil, **teşhis ekranı**.

```
┌────────────────────────────────┐
│           Cephe Yarıldı        │   Archivo Semibold 28
│                                │
│  Okçularının %70'i 12. saniyede│
│  aynı anda öldü.               │
│                                │
├────────────────────────────────┤
│  EMİRLERİN                     │
│                                │
│  ① düşman 3 kareden yakınsa    │
│     GERİ ÇEKİL                 │
│     ━━━━━━━━━━━━━━━━  14 kez   │
│                                │
│  ② canım %35'in altındaysa     │
│     SİPER AL                   │
│     ━━━━                3 kez  │
│                                │
│  ③ başka durumda İLERLE        │
│     ────────            0 kez  │
│     ⚠ Bu emir hiç çalışmadı.   │
│                                │
├────────────────────────────────┤
│  [ Emirleri Düzelt ]           │
│  [ Klibi Paylaş ]              │
└────────────────────────────────┘
```

"Bu emir hiç çalışmadı" uyarısı en değerli tek bilgi — oyuncuya kendi mantık hatasını doğrudan gösterir. Görsel olarak öne çıkmalı ama suçlayıcı olmamalı.

Yenilgi metni **asla** oyuncuyu teselli etmez ("Az kalmıştı!" gibi). Ne olduğunu söyler. Bu oyunun sesi budur.

### 4.7 Klip Paylaşımı

Savaş klibinin üzerine emir metni yerleştirilmiş bir paylaşım kartı. Bu, oyunun organik büyüme motoru — tasarımın kendisi reklam olmalı.

```
┌────────────────────────────────┐
│                                │
│      (savaş klibi, 9:16)       │
│                                │
│  ┌──────────────────────────┐  │
│  │ "düşman yaklaşınca        │  │   ← alt üçte birde
│  │  geri çekil"              │  │      pusula metni
│  │                           │  │
│  │  → 40 okçu 12 saniyede    │  │
│  │    yok oldu               │  │
│  └──────────────────────────┘  │
│                                │
│         FERMAN · Cephe 14        │
└────────────────────────────────┘
```

İki şablon gerekli: **Zafer** ve **En Kötü Yenilgin**. İkincisi daha çok paylaşılacak; komik olmalı ama oyuncuyla dalga geçmemeli.

### 4.8 Arena

Asenkron PvP. Diğer oyuncuların emir setleri sana saldırır, senin setin onlara savunma yapar.

```
Savunma sicilin      11 / 14 saldırı püskürtüldü
Bu haftaki emrin     "Kalkanlar önde, okçular geride"
Sıra                 Bölgende 47.

Gelen saldırılar
  ▸ Kerem'in Süvari Akını      [ İzle ]
  ▸ Zeynep'in Kuşatması        [ İzle ]
```

### 4.9 Emir Kütüphanesi

Kaydedilmiş, adlandırılmış emir setleri. Fiziksel bir dosya çekmecesi metaforu: sekmeli kartlar, elle yazılmış gibi duran etiketler.

---

## 5. Bileşen envanteri

Bunları yeniden kullanılabilir bileşen olarak üret:

| Bileşen | Notlar |
|---|---|
| `EmirPusulası` | Durumlar: normal · sürükleniyor · tetiklendi · devre dışı · varsayılan (kesikli) |
| `PusulaYığını` | Sürükle-sırala, öncelik numarası otomatik |
| `ParametreKadranı` | Pusula içinde açılan küçük sayı seçici |
| `BirimJetonu` | Boyut: tepsi / masa / sonuç. Takım rengi: pirinç / demir |
| `KumMasası` | Işık düşüşü, ızgara katmanı, arazi katmanı |
| `TetiklenmeÇubuğu` | Canlı dolan sayaç, kıvılcım parlaması |
| `BütçeGöstergesi` | Kullanılan / toplam, aşım durumu |
| `CepheBayrağı` | Harita iğnesi, durum: geçildi / açık / kilitli |
| `AltSheet` | 14pt köşe, yükseltilmiş yüzey |
| `BirincilButon` | Tek ekranda yalnızca bir tane |

---

## 6. Platform gereklilikleri

- **iOS 26+**, SwiftUI. Liquid Glass materyalini **ölçülü** kullan: yalnızca üst bar ve alt sheet'lerde, ve şeffaflık açıkken kum masasının üzerinde okunabilirliği doğrula.
- **Dynamic Type** XXL'e kadar kırılmadan çalışmalı. Emir pusulaları büyük tipte iki satıra sarmalı, kesilmemeli.
- **VoiceOver**: pusula tek bir öğe olarak okunmalı — *"Birinci emir. Düşman üç kareden yakınsa geri çekil. Öncelik dokuz. Düzenlemek için çift dokunun."*
- **Reduce Motion**: §3.5'teki sekans anında kesilir, geçişler çapraz solmaya döner.
- **Renk körlüğü**: kıvılcım rengi tek başına bilgi taşımaz — tetiklenme aynı anda sayaç rakamı ve çubuk uzunluğuyla da kodlanır.
- Güvenli alan: alttaki birincil buton her zaman `safeAreaInset` içinde, klavye açıkken de erişilebilir.
- iPad: iki sütun (sol pusula yığını, sağ kum masası önizlemesi). İkincil öncelik.

---

## 7. Metin tonu

Arayüz, deneyimli ve sakin bir subay gibi konuşur. Ne neşeli ne de dramatik.

| Yapma | Yap |
|---|---|
| "Harika iş! 🎉" | "Hat tutuldu." |
| "Ah, olmadı! Tekrar dene!" | "Cephe yarıldı." |
| "Emirlerinizi gönderin" | "Savaşı başlat" |
| "Hata oluştu" | "Bu emir hiç çalışmadı." |
| "Kural derle" | "Yaz" |

Emir kipi, cümle düzeni, dolgu kelimesi yok. Bir buton neye basıldığını söyler ve sonucu aynı kelimeyle bildirir.

---

## 8. Teslim sırası

1. **Token sistemi** — renk, tip ölçeği, boşluk, yarıçap, gölge. Tek bir referans sayfası.
2. **Emir Editörü** (4.4) — önce bu. Oyunun kalbi burası; diğer her şey buna uyum sağlayacak.
3. **Savaş Sonrası Analiz** (4.6) — ikinci en önemli ekran.
4. **Savaş Ekranı** (4.5)
5. **Ordu Kurulumu** (4.3) ve **Seviye Haritası** (4.2)
6. **Ana Menü** (4.1), **Arena** (4.8), **Kütüphane** (4.9)
7. **Paylaşım kartları** (4.7) — iki şablon
8. **Bileşen kütüphanesi** — §5'teki her bileşen, tüm durumlarıyla

Her ekran için karanlık mod asıl, açık mod varyant.

---

## 9. Kendine sorman gereken tek soru

Emir Editörü ekranının görüntüsünü, programlama bilmeyen birine gösterdiğinde:

> **"Bu ne?"** diye mi soruyor, yoksa **"bunu ben de yazabilirim"** mi diyor?

İkincisi olana kadar tasarım bitmemiştir.
