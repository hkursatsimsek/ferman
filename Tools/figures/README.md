# Tools/figures — birim sanatı (D24, D25)

Birim görselleri `App/Ferman/Assets.xcassets/Units.spriteatlas/` altındadır ve **commit edilir**; normal
derleme bu klasördeki hiçbir aracı çalıştırmaz. Adlar `UnitArt` (`App/Ferman/DesignSystem/UnitArt.swift`)
kuralını izler:

| Görsel | Ad |
|---|---|
| Figür | `<birim>-<malzeme>-<poz>` — malzeme `brass` (oyuncu) / `iron` (düşman), poz `base` · `strike` · `brace` · `fallen` |
| Gölge | `shadow-<birim>`, `shadow-<birim>-fallen` |
| Seçim halkası | `ring-selection` |

Her figür 48×48 pt kare tuval, altlık merkezde, figür **yukarı** bakar; @2x ve @3x. `UnitArtTests`
paketlenmiş katalogdaki her birim × takım × poz için görselin varlığını ve boyutunu doğrular.

## Yer tutucular (şu an kullanılan)

```bash
swift Tools/figures/placeholders.swift App/Ferman/Assets.xcassets/Units.spriteatlas
```

Core Graphics ile çizilmiş, bağımlılıksız. Aynı girdiyle bayt bayt aynı çıktıyı üretir.

## Blender (G5)

Blender render'ları aynı adlarla bu dosyaların üstüne yazılacak; Swift kodu değişmez. Betik, sabitlenmiş Blender
sürümü ve doğrulama adımları G5'te bu belgeye eklenecek.
