# Sesler — kaynak ve lisans

Bu klasördeki **her ses sentezdir**: `Tools/sounds/synthesize.py` tarafından sıfırdan üretilir. Kayıt, örnek
(sample), ses kütüphanesi ya da yapay zekâ üretimi yoktur; üçüncü taraf lisansı yoktur. Lisans: proje malı.

```bash
python3 Tools/sounds/synthesize.py App/Ferman/Sounds          # numpy yeterli
# ya da sabitlenmiş Blender'ın Python'uyla (numpy içinde gelir):
blender --background --factory-startup --python Tools/sounds/synthesize.py -- App/Ferman/Sounds
```

Gürültü sayaç + SplitMix64'ten, WAV'lar standart kütüphaneyle yazılır: iki ortam (numpy 2.0 ve 2.3) bayt bayt aynı
dosyaları üretti. Biçim: 16 bit mono PCM, 44,1 kHz (ortam döngüsü 22,05 kHz).

| Dosya | Oyunda | Tarif |
|---|---|---|
| `stamp` | Açılışta pusulaların damgalanması | Masaya inen gövde (125→60 Hz kayan sinüs) + masa rezonansı (230/470/760/1240 Hz modlar) + ezilen kâğıt (süzülmüş gürültü) + mürekkepli taşın kalkışı |
| `paper` | Emir sırası değişince | Tanecik zarflı 1,5–7 kHz gürültü (hışırtı) + yumuşak kayma |
| `slip` | Sonuç pusulası masaya düşünce | Geniş bantlı şaplak + 260→170 Hz gövde + hışırtı |
| `result-victory` | Sonuç pusulasının altında, zaferde | Küçük pirinç kaseye tek vuruş: 660 Hz ve iki inharmonik üst mod, uzun sönüm (fanfar değil, subay sakinliği) |
| `result-defeat` | Sonuç pusulasının altında, yenilgide | Masaya tek boğuk ahşap vuruş (196/412/690 Hz modlar) + gövde |
| `dial` | Parametre kadranının her çentiği | Pirince değen ahşap cırcır: çok kısa tıklama + 4,2 kHz rezonans |
| `order-1…3` | Oyuncunun emri işlediğinde, eylem sesinin altında "tık" | 2,4–9 kHz kısa tıklama + 3,1 kHz kâğıt rezonansı + ikinci yumuşak esneme |
| `place-1…2` | Ordu Kurulumu'nda figür bırakma/taşıma | Döküm metal şıngırtısı (inharmonik modlar ~2,3 kHz) + masa "tok"u + küçük sekme |
| `action-advance` | İlerle | Kâğıtla boğulmuş küçük davul, "dum-dum": zar modları (1 / 1,59 / 2,14 / 2,30 ×) kayarak, 1,5 kHz üstü kısık |
| `action-retreat` | Geri çekil | Kumda sürüklenen altlık: tanecik darbeleri × iki bantlı gürültü, parlaklığı giderek sönen |
| `action-flank` | Sola/sağa kanat | Kısa kum savurması; oyunda ilgili yana kaydırılır (pan) |
| `action-hold` | Mevzini koru | Tek alçak ahşap "tok" (410 Hz modal) |
| `action-focus` | Hedefe odaklan | Masaya iki kez vuran işaret çubuğu, "tak-TAK" |
| `action-regroup` | Toplan | Hızlanarak toplanan çakıllar, sonunda ahşap üstüne konuş |
| `action-scatter` | Dağıl | Kum serpintisi + seyrelerek dağılan çakıl tıkırtıları |
| `action-cover` | Siper al | Kalkana vuruş: inharmonik levha modları (520 Hz tabanlı) + hafif detune ile titreşim |
| `action-guard` | Komutanı koru | Küçük pirinç el çanı (çan oranları 0,5 / 1 / 1,18 / 1,51 / 2 …) |
| `release-1…3` | Ok fırlatılırken | Karplus–Strong yay teli (172–200 Hz) + kolluğa çarpma + uzaklaşan ıslık |
| `land-1…3` | Ok indiğinde (vuruş anı) | Kuma/ahşaba boğuk darbe + şaft titreşimi (~900 Hz, vibrato) |
| `hit-1…4` | Yakın dövüş vuruşu | Döküm metal modları (1,7–2,3 kHz) + ahşap gövde + geçici tıklama, oranı varyanta göre |
| `fall-1…3` | Ölüm: figür devriliyor | Altlıkta sallanma + metal çarpma + iki küçük sekme + yuvarlanma tıkırtıları |
| `rout` | Moral çöktü | Masada titreyen figürün tıkırtıları |
| `ability-spear-wall` | Kirpi duvarı | Art arda inen ahşap şaftlar + uçların metal tıkı |
| `ability-shield-wall` | Kalkan duvarı | Üst üste iki kalkan çınlaması + yere oturan gövde |
| `ability-charge` | Hücum | Yaklaşan nal "tak"ları (620 Hz / 1,3 kHz modlar + gövde), ikişer üçlü |
| `ambience` | Tüm ekranlarda, uygulama öndeyken döngü | Gece karargâh odası: 1/f alçak oda tonu, çok hafif lamba cızırtısı, başka bir odada saniyede bir "tik-tak" eden saat (duvarın arkasından, süzülmüş), dışarıda yükselip alçalan rüzgâr. Tüm tampon üzerinde frekans alanında süzüldüğü ve yalnızca döngü süresini bölen periyotlarla değiştiği için döngüde ek yeri yok (16 sn) |

Telefon hoparlörü ~250 Hz altını neredeyse vermez; bu yüzden hiçbir "gümleme" yalnızca alçak sinüs değildir,
her birinin birkaç yüz hertzlik bir gövde rezonansı vardır — masadaki küçük bir nesnenin sesi de zaten budur.
