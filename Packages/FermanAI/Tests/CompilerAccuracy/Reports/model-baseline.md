# Compiler accuracy — FoundationModelsCompiler

**Exact match: 97/150 (64.7%)**

Time per phrase: p50 1481 ms · p95 1950 ms · max 4046 ms

| By language | Exact |
|---|---|
| tr | 44/76 (57.9%) |
| en | 53/74 (71.6%) |

| By kind of phrase | Exact |
|---|---|
| one order | 66/82 (80.5%) |
| bare action | 7/24 (29.2%) |
| several orders | 14/23 (60.9%) |
| refusal | 10/21 (47.6%) |

| By field | Right |
|---|---|
| number of orders | 116/129 (89.9%) |
| condition kind | 125/160 (78.1%) |
| condition number / unit / terrain | 95/104 (91.3%) |
| action kind | 138/160 (86.3%) |
| action target unit | 4/12 (33.3%) |
| refusal reason | 10/21 (47.6%) |

| Kind of miss | Count |
|---|---|
| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | 33 |
| Valid order refused | 9 |
| Text that is no order accepted as one | 6 |

## Misses (53)

- `tr-003` "canım %20'nin altına düşerse geri çekil"
  - expected: healthBelow(percent: 20) → retreat
  - got: moraleBelow(percent: 20) → retreat
- `tr-004` "can yüzde 50'nin altındaysa siper al"
  - expected: healthBelow(percent: 50) → takeCover
  - got: moraleBelow(percent: 50) → takeCover
- `tr-008` "etrafımda 5'ten fazla düşman olursa geri çekil"
  - expected: enemyDensityAbove(count: 5) → retreat
  - got: allyCountBelow(count: 5) → retreat
- `tr-009` "30. saniyeden sonra ilerle"
  - expected: timeAfter(seconds: 30) → advance
  - got: timeAfter(seconds: 30) → useAbility
- `tr-019` "menzilime süvari girerse süvarilere yüklen"
  - expected: targetInRange(suvari) → focusFire(Optional(suvari))
  - got: refused noOrderRecognized
- `tr-023` "canım %30'un altındaysa komutanı koru"
  - expected: healthBelow(percent: 30) → guardCommander
  - got: moraleBelow(percent: 30) → guardCommander
- `tr-025` "40 saniye sonra soldan kuşat"
  - expected: timeAfter(seconds: 40) → flankLeft
  - got: refused noOrderRecognized
- `tr-026` "25 saniye sonra sağdan kuşat"
  - expected: timeAfter(seconds: 25) → flankRight
  - got: refused noOrderRecognized
- `tr-037` "ilerle"
  - expected: always → advance
  - got: enemyWithin(cells: 1) → advance
- `tr-039` "ilerlemeye devam et"
  - expected: always → advance
  - got: enemyWithin(cells: 10) → advance
- `tr-040` "komutanı koru"
  - expected: always → guardCommander
  - got: terrainIs(FermanCore.Terrain.water) → guardCommander
- `tr-041` "okçulara odaklan"
  - expected: always → focusFire(Optional(okcu))
  - got: targetInRange(okcu) → focusFire(nil)
- `tr-042` "siper al"
  - expected: always → takeCover
  - got: terrainIs(FermanCore.Terrain.open) → takeCover
- `tr-043` "dağıl"
  - expected: always → scatter
  - got: refused missingConditionParameter:enemyWithin
- `tr-044` "toplanın"
  - expected: always → regroup
  - got: healthBelow(percent: 50) → regroup
- `tr-045` "yeteneğini kullan"
  - expected: always → useAbility
  - got: refused noOrderRecognized
- `tr-046` "sağdan dolan"
  - expected: always → flankRight
  - got: isFlanked → flankRight
- `tr-049` "canım %30'un altına düşerse siper al. düşman 4 kareye girerse yüklen. aksi halde ilerle"
  - expected: healthBelow(percent: 30) → takeCover | enemyWithin(cells: 4) → focusFire(nil) | always → advance
  - got: moraleBelow(percent: 30) → takeCover | enemyWithin(cells: 4) → useAbility | always → advance
- `tr-052` "10 saniye sonra soldan kuşat ve düşman 3 kareden yakınsa süvarilere yüklen"
  - expected: timeAfter(seconds: 10) → flankLeft | enemyWithin(cells: 3) → focusFire(Optional(suvari))
  - got: timeAfter(seconds: 10) → flankLeft | enemyWithin(cells: 3) → useAbility
- `tr-053` "ormandaysam yerinde kal, açıktaysam ilerle"
  - expected: terrainIs(FermanCore.Terrain.forest) → hold | terrainIs(FermanCore.Terrain.open) → advance
  - got: terrainIs(FermanCore.Terrain.open) → hold | terrainIs(FermanCore.Terrain.open) → advance
- `tr-054` "yanımda 3'ten az dost varsa toplan, düşman 2 kareden yakınsa saldır, yoksa yerinde kal"
  - expected: allyCountBelow(count: 3) → regroup | enemyWithin(cells: 2) → advance | always → hold
  - got: allyCountBelow(count: 3) → regroup | enemyWithin(cells: 2) → focusFire(Optional(mizrakci)) | always → hold
- `tr-055` "20 saniye sonra ilerle, öncesinde yerinde kal"
  - expected: timeAfter(seconds: 20) → advance | always → hold
  - got: refused multipleActions
- `tr-057` "okçulara yüklen ve düşman 2 kareden yakınsa geri çekil"
  - expected: enemyWithin(cells: 2) → retreat | always → focusFire(Optional(okcu))
  - got: enemyWithin(cells: 2) → retreat | targetInRange(okcu) → useAbility
- `tr-059` "düşman 5 kareye girince okçulara yüklen yoksa ilerle"
  - expected: enemyWithin(cells: 5) → focusFire(Optional(okcu)) | always → advance
  - got: enemyWithin(cells: 5) → advance
- `tr-061` "canım yüzde kırk beşin altına düşerse siper al"
  - expected: healthBelow(percent: 45) → takeCover
  - got: moraleBelow(percent: 45) → takeCover
- `tr-062` "on beş saniye sonra ilerle"
  - expected: timeAfter(seconds: 15) → advance
  - got: timeAfter(seconds: 5) → advance
- `tr-069` "düşman görünce saldır"
  - expected: refused unrecognizedCondition
  - got: refused missingConditionParameter:enemyWithin
- `tr-070` "canım %60'ın üstündeyse ilerle"
  - expected: refused unsupportedComparison:healthBelow
  - got: refused unsupportedComparison:moraleBelow
- `tr-071` "düşman 3 kareden uzaksa yerinde kal"
  - expected: refused unsupportedComparison:enemyWithin
  - got: enemyWithin(cells: 3) → hold
- `tr-072` "düşman 3 kareden yakınsa"
  - expected: refused missingAction:enemyWithin
  - got: enemyWithin(cells: 3) → scatter
- `tr-073` "ilerle, aksi halde geri çekil"
  - expected: refused conflictingDefaultOrders
  - got: enemyWithin(cells: 2) → advance | always → retreat
- `tr-074` "ilk 10 saniye bekle sonra ilerle"
  - expected: refused multipleActions
  - got: refused noOrderRecognized
- `en-002` "if enemies are within 2 cells, hold position"
  - expected: enemyWithin(cells: 2) → hold
  - got: enemyDensityAbove(count: 2) → hold
- `en-017` "focus fire on archers when cavalry is in range"
  - expected: targetInRange(suvari) → focusFire(Optional(okcu))
  - got: targetInRange(okcu) → focusFire(Optional(mizrakci))
- `en-027` "if cavalry is in my range, shoot them"
  - expected: targetInRange(suvari) → focusFire(nil)
  - got: targetInRange(suvari) → focusFire(Optional(suvari))
- `en-029` "if the nearest enemy is a spearman, retreat"
  - expected: nearestEnemyType(mizrakci) → retreat
  - got: refused unrecognizedCondition
- `en-032` "attack when an enemy is within 3 cells"
  - expected: enemyWithin(cells: 3) → advance
  - got: enemyWithin(cells: 3) → focusFire(nil)
- `en-033` "retreat to the forest if health below 30"
  - expected: healthBelow(percent: 30) → retreat
  - got: healthBelow(percent: 30) → retreat | terrainIs(FermanCore.Terrain.forest) → retreat
- `en-039` "guard the commander"
  - expected: always → guardCommander
  - got: terrainIs(FermanCore.Terrain.open) → guardCommander
- `en-040` "focus on the cavalry"
  - expected: always → focusFire(Optional(suvari))
  - got: enemyWithin(cells: 10) → advance | terrainIs(FermanCore.Terrain.hill) → hold | isFlanked → regroup | commanderDead → takeCover | timeAfter(seconds: 120) → useAbility | targetInRange(suvari) → focusFire(Optional(suvari)) | nearestEnemyType(mizrakci) → flankLeft | allyCountBelow(count: 2) → retreat
- `en-041` "take cover"
  - expected: always → takeCover
  - got: isFlanked → takeCover
- `en-042` "scatter"
  - expected: always → scatter
  - got: refused missingConditionParameter:enemyWithin
- `en-043` "regroup"
  - expected: always → regroup
  - got: healthBelow(percent: 50) → regroup
- `en-044` "use your special ability"
  - expected: always → useAbility
  - got: timeAfter(seconds: 60) → useAbility
- `en-045` "flank left"
  - expected: always → flankLeft
  - got: isFlanked → flankLeft
- `en-047` "flank from the right"
  - expected: always → flankRight
  - got: isFlanked → flankRight
- `en-054` "if fewer than 3 allies nearby regroup, if enemy within 2 cells attack, otherwise hold"
  - expected: allyCountBelow(count: 3) → regroup | enemyWithin(cells: 2) → advance | always → hold
  - got: allyCountBelow(count: 3) → regroup | enemyWithin(cells: 2) → focusFire(nil)
- `en-056` "focus fire on archers and retreat if an enemy is within 2 cells"
  - expected: enemyWithin(cells: 2) → retreat | always → focusFire(Optional(okcu))
  - got: refused missingConditionParameter:enemyWithin
- `en-067` "retreat if an enemy shows up"
  - expected: refused unrecognizedCondition
  - got: refused missingConditionParameter:enemyWithin
- `en-068` "advance if health is above 60%"
  - expected: refused unsupportedComparison:healthBelow
  - got: refused unrecognizedCondition
- `en-069` "hold if the enemy is farther than 5 cells"
  - expected: refused unsupportedComparison:enemyWithin
  - got: enemyWithin(cells: 5) → hold
- `en-070` "if an enemy is within 3 cells"
  - expected: refused missingAction:enemyWithin
  - got: enemyWithin(cells: 3) → focusFire(nil)
- `en-071` "advance, otherwise retreat"
  - expected: refused conflictingDefaultOrders
  - got: always → retreat
