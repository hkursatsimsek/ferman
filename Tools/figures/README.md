# Tools/figures — birim sanatı (D24, D25)

Figürler, gölgeleri, seçim halkası, ok ve masa süsleri (ağaç, taş) **betikli Blender** ile üretilir ve
**commit edilir**; normal derleme bu klasördeki hiçbir aracı çalıştırmaz. Yapay zekâ sanatı yok, dışarıdan
model/doku yok: her şey `figures.py` içindeki primitiflerden (küre, tüp, silindir, kavisli levha) kurulur.

```bash
blender --background --factory-startup --python Tools/figures/figures.py -- \
  --atlas App/Ferman/Assets.xcassets/Units.spriteatlas \
  --terrain App/Ferman/Assets.xcassets/Terrain \
  --contact-sheet /tmp/figures.png            # isteğe bağlı: renkli + gri tonlamalı kontak sayfası
# --only okcu : yalnızca bir birim tipini yeniden üret (figür üzerinde çalışırken)
```

**Sabitlenmiş sürüm: Blender 5.2.2 LTS** (Cycles, CPU). Aynı sürüm aynı baytları yazar (sabit tohum,
uyarlamalı örnekleme ve gürültü giderme kapalı, PNG'ler betiğin kendi kodlayıcısıyla, meta verisiz) — iki koşum
`diff -r` ile doğrulandı. Başka bir sürüm küçük piksel farkları üretebilir; sürüm değişirse tüm set yeniden
üretilip gözden geçirilir. Tam set M-sınıfı bir Mac'te ~1 dakika.

## Adlar

`UnitArt` (`App/Ferman/DesignSystem/UnitArt.swift`) ve `TerrainSprites` (`App/Ferman/Rendering/`) bu kuralı izler:

| Görsel | Ad | Tuval |
|---|---|---|
| Figür | `<birim>-<malzeme>-<poz>` — malzeme `brass` (oyuncu) / `iron` (düşman), poz `base` · `strike` · `brace` · `fallen` | 48×48 pt |
| Gölge | `shadow-<birim>`, `shadow-<birim>-fallen` | 48×48 pt |
| Seçim halkası | `ring-selection` | 48×48 pt |
| Ok ve gölgesi | `arrow`, `shadow-arrow` | 6×18 pt |
| Ağaç ve gölgesi | `terrain-tree-<0…3>`, `terrain-tree-<0…3>-shadow` | 24×24 pt |
| Taş kümesi (gölgesi içinde) | `terrain-stones-<0…2>` | 12×12 pt |

Figürler altlık merkezde, **yukarı** (+Y) bakar; SpriteKit `zRotation` ile döndürür. @2x ve @3x yazılır.
`UnitArtTests` paketlenmiş katalogdaki her birim × takım × poz için görselin varlığını ve boyutunu, ok ve masa
süslerinin varlığını doğrular.

## Nasıl üretiliyor

- **Sahne birimi = tuval noktası.** Ortografik kamera tam tepeden 48×48 pt'lik kareyi çerçeveler; 6 px/pt'de
  render edilir, doğrusal ışıkta kutu süzgeciyle @3x'e (÷2) ve @2x'e (÷3) küçültülür.
- **Tek lamba, Z eksenine göre simetrik:** tam tepeden yumuşak bir güneş + yalnızca yüksekliğe bağlı bir gökyüzü.
  Bir yüzeyin parlaklığı yalnızca ne kadar yukarı baktığına bağlıdır; figür döndürülünce ışık bozulmaz
  (ART-DIRECTION §3), en parlak yerler miğfer, kalkan göbeği, at sırtı olur.
- **Malzemeler:** pirinç (girintilerde ambient occlusion ile bulunan bakır yeşili patina) · ham dökme demir (mat,
  girintilerde siyah kabuk). Altlığın üst yüzü ayrı, pürüzlü ve koyu bir "zemin"dir — düz metal yüz lambayı
  aynalayıp figürü bastırıyordu.
- **Takım şekille:** oyuncu yuvarlak, düşman sekizgen altlık (D24). Altlığın arkasına tipin sembolü kazınır
  (mızrak │, ok ^, at nalı ∩, kalkan ○) — kabartma denendi, sadak ucuyla birlikte küçük boyutta bir "surat" gibi okundu.
- **Mürekkep kenar:** figürün alfa maskesi ~0,5 pt büyütülüp mürekkep renginde altına konur (ART-DIRECTION §2 —
  demir ile kum aynı parlaklıkta, onları ayıran bu kenar ve gölgedir).
- **Gölgeler** gerçek: figür kameraya görünmez yapılır, gölge yakalayıcı düzlem yalnızca düşürdüğü gölgeyi
  kaydeder; mürekkep rengine, %62 opaklığa çevrilir. Oyunda lambadan uzağa 2–4 sahne noktası kaydırılır
  (`BoardProjection.shadowOffset`).
- **Devrik (`fallen`)** poz ayrıca modellenmez: ayakta figür altlığıyla birlikte yan yatırılır, masaya oturtulur,
  hücreye ortalanır ve soldurulur.

## Kabul kontrolü (G5)

1. **Gri tonlama okunabilirliği:** `--contact-sheet` iki sayfa yazar; gri olanda her figürün tipi silüetten, takımı
   altlık şeklinden, üç kum tonunda (normal, aydınlık, koyu kenar) söylenebilmeli.
2. **Toplu çizim:** uygulamayı `-uiTestBattle 8 -showsDrawCount YES` ile aç. Figürler, gölgeler, halka ve oklar
   tek atlastan geldiği için çizim çağrısı birim sayısına değil katman sayısına bağlıdır (2026-09-19, iPhone 18 Pro
   simülatörü, 8. cephe: 317 düğüm, 16 çizim).
