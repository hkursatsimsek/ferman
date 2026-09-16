# Faz 0 denge raporu — F0.13

**Soru (`docs/FERMAN-PLAN.md` §6):** Elle yazılmış kural setleri farklı sonuçlar üretiyor mu? Yani kural yazmak
simülasyonda gerçekten fark yaratıyor mu? Yaratmıyorsa denge parametreleri yanlıştır ve UI yazmadan önce
düzeltilmelidir.

**Sonuç:** Evet, çok belirgin şekilde. En iyi ve en kötü kural setinin ortalama kazanma oranı arasında **75 puan**
fark var — %20 eşiğinin 3–4 katı. Faz 1'e geçmeden önce ek tuning gerekmiyor. Yan bulgu için aşağıdaki "Gözlem"
bölümüne bakın; bu, F0.13'ün geçme koşulunu etkilemiyor ama F3.9'daki gece denge koşumu için not edildi.

## Yöntem

**6 zıt kural seti** (her biri okçu ve mızrakçı için ayrı emir listesi taşır):

| Set | Okçu | Mızrakçı |
|---|---|---|
| `pasif` | her zaman → ilerle | her zaman → ilerle |
| `saldirgan` | düşman ≤4 kare → yetenek kullan; her zaman → yüklen (odaklan) | düşman ≤3 kare → yetenek kullan; her zaman → yüklen |
| `savunmaci` | her zaman → yerinde kal | düşman ≤2 kare → yetenek kullan; her zaman → yerinde kal |
| `vurkac` | düşman ≤2 kare → geri çekil; her zaman → yerinde kal | her zaman → yerinde kal |
| `kusatma` | düşman ≤6 kare → soldan kuşat; her zaman → ilerle | düşman ≤5 kare → sağdan kuşat; her zaman → ilerle |
| `toplanma` | dost <2 → topla; düşman ≤4 kare → yüklen; her zaman → ilerle | dost <2 → topla; düşman ≤3 kare → yüklen; her zaman → ilerle |

**Sabit ordu ve harita:** Her iki taraf da 3 okçu + 3 mızrakçı, ayna-simetrik yerleşim (18×8 açık harita, oyuncu
sütun 1, düşman sütun 16, haritanın ortasında simetrik iki hücrelik bir orman bloğu). Değişen tek şey kural
setidir — böylece ölçülen fark yalnızca kurallardan gelir, ordu bileşiminden değil. `objective: eliminate`,
`maxTicks: 900`; birim istatistikleri altın dosyalarla aynı 4 tipten (`kalkan`, `mizrakci`, `okcu`, `suvari`)
okçu ve mızrakçı kullanılıyor.

**Eşleşmeler:** 6×6 = 36 sıralı eşleşme (her set hem oyuncu hem düşman koltuğunda denendi, kendisiyle eşleşme
dahil), her biri 1000 farklı tohumla (`seed: 0..<1000`) — toplam 36.000 savaş.

```bash
swift run -c release --package-path Tools/fermansim fermansim batch \
  --matrix Balance/matrix.json --count 1000 --jobs 12 --out results.csv
```

12 çekirdekte ~33 saniye sürdü. `Balance/matrix.json` 36 eşleşmenin tam `BattleConfig`'lerini taşır (tohum alanı
`batch` tarafından `0..<1000` ile değiştirilir); `Balance/phase0-summary.csv` her eşleşmenin 1000 koşum üzerinden
toplamını taşır.

## Sonuç 1 — Kural seçimi kazanma oranını büyük ölçüde değiştiriyor

Oyuncu koltuğundaki kazanma oranı (satır = oyuncunun seti, sütun = düşmanın seti):

| | pasif | saldirgan | savunmaci | vurkac | kusatma | toplanma |
|---|---|---|---|---|---|---|
| **pasif** | 100 | 0 | 0 | 100 | 100 | 100 |
| **saldirgan** | 100 | 0 | 100 | 100 | 100 | 100 |
| **savunmaci** | 0 | 0 | 0 | 0 | 100 | 0 |
| **vurkac** | 0 | 0 | 0 | 0 | 100 | 0 |
| **kusatma** | 0 | 0 | 0 | 0 | 100 | 0 |
| **toplanma** | 100 | 0 | 100 | 100 | 100 | 10,5 |

Köşegen (bir setin kendisiyle eşleşmesi) hepsi %50 civarında olmalıymış gibi görünebilir ama değil:
`saldirgan_vs_saldirgan` 1000/1000 berabere biterken, `savunmaci_vs_savunmaci`, `vurkac_vs_vurkac` ve
`kusatma_vs_kusatma` **1000 tohumun tamamında** aynı tarafın (sırasıyla düşman, düşman, oyuncu) kazandığı bir
sonuca kilitleniyor — bkz. aşağıdaki gözlem.

Her setin koltuktan bağımsız ortalama kazanma oranı (oyuncu olarak 6 rakibe karşı ortalama, düşman olarak 6
rakibe karşı ortalama, ikisinin ortalaması — böylece hiçbir set "koltuk avantajından" haksız pay almaz):

| Sıra | Set | Oyuncu% | Düşman% | Ortalama% |
|---|---|---|---|---|
| 1 | `saldirgan` | 83,3 | 83,3 | **83,3** |
| 2 | `toplanma` | 68,4 | 51,7 | 60,1 |
| 3 | `pasif` | 66,7 | 50,0 | 58,3 |
| 4 | `savunmaci` | 16,7 | 66,7 | 41,7 |
| 5 | `vurkac` | 16,7 | 50,0 | 33,3 |
| 6 | `kusatma` | 16,7 | 0,0 | **8,3** |

**En iyi (`saldirgan`, %83,3) − en kötü (`kusatma`, %8,3) = 75 puan.** Eşik %20; bu fark eşiğin 3,75 katı.
Oyuncunun yazdığı emirler savaşın sonucunu köklü şekilde değiştiriyor.

## Gözlem — yakın eşleşmeler tohuma değil, konum/sıra detaylarına duyarlı

36 eşleşmenin 35'i 1000 tohumun **tamamında** birebir aynı sonucu üretti (yalnızca `toplanma_vs_toplanma`
gerçekten tohuma göre değişti: 105 oyuncu / 103 düşman / 792 berabere). Bunun nedeni basit: `DeterministicRNG`
bu simülasyonda yalnızca `scatter` yönü için kullanılıyor (§5.6), ve bu 36 eşleşmenin neredeyse tamamında hiçbir
birim morali kırılıp dağılmıyor — yani tohum hiç tüketilmiyor ve sonuç tohumdan tamamen bağımsız kalıyor. Sonuç
olarak "1000 tohum" bu eşleşmelerin çoğu için 1000 bağımsız örnek değil, aynı deterministik sonucun 1000
kopyasıdır.

Bunun en çarpıcı örneği kendisiyle eşleşmeler (köşegen): iki taraf *birebir aynı* emirleri taşısa bile sonuç
genelde berabere değil, kesin bir tarafın zaferi. `saldirgan_vs_saldirgan` 1000/1000 berabere biterken,
`savunmaci_vs_savunmaci` ve `vurkac_vs_vurkac` 1000/1000 **düşman** kazanıyor, `kusatma_vs_kusatma` ise
1000/1000 **oyuncu** kazanıyor — hepsi aynı ordu, aynı harita, aynı kurallarla.

Bu aynı zamanda ilginç bir yan etki doğuruyor: `savunmaci` seti oyuncu koltuğunda %16,7 kazanırken düşman
koltuğunda %66,7 kazanıyor — yani *aynı* rakiplere karşı, *aynı* emirlerle, sadece hangi taraf olduğuna bağlı
olarak sonuç tersine dönebiliyor. Harita gerçekten ayna-simetrik olduğu doğrulandı (orman bloğu merkeze göre
simetrik test edildi, sonuç değişmedi), dolayısıyla bu haritadan gelmiyor. En olası açıklama D10'un mesafe-sonra-
`UnitID` eşitlik bozma kuralı: oyuncu birimleri her zaman daha düşük ID alır (`TeamSetup` dokümantasyonu,
"oyuncu takımı önce"), ve tamamen deterministik, düşük-varyans bir çarpışmada bu küçük yapısal avantaj —
şans faktörü olmadığı için — geniş marjlı bir zafere büyüyebiliyor.

Bu, F0.13'ün geçme koşulunu **etkilemiyor** (ölçüm her setin ortalamasını hem oyuncu hem düşman koltuğunda
alarak bu etkiyi zaten dengeliyor). Ama F3.9'un gece denge koşumu için not edilmeye değer: yakın dövüşlerde
gerçek istatistiksel çeşitlilik için tohumun yanına küçük bir başlangıç konumu jitter'ı ya da koltuk
döndürmesi eklenmesi gerekebilir — bkz. `docs/FERMAN-PLAN.md` §9.

## Karar

Faz 1'e (dikey dilim) geçmeden önce F0.13 için ek tuning gerekmiyor. Mekanik zaten anlamlı taktik farklar
üretiyor; asıl açık soru (Faz 1'in kendi karar noktası) UI'nın bunu oyuncuya *eğlenceli* şekilde hissettirip
hissettirmediği.

## Yeniden üretme

```bash
swift run -c release --package-path Tools/fermansim fermansim batch \
  --matrix Balance/matrix.json --count 1000 --jobs <çekirdek sayınız> --out results.csv
```

`Balance/matrix.json` içindeki her `config.seed` alanı `batch` tarafından zaten göz ardı edilir (bkz.
`BattleConfig.withSeed`), bu yüzden `--count` kaç tohum denenecek olduğunu belirler.
