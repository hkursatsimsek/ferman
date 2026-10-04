# Compiler accuracy — FoundationModelsCompiler (held-out phrases)

**Exact match: 20/29 (69.0%)**

Time per phrase: p50 1482 ms · p95 1988 ms · max 2029 ms

| By language | Exact |
|---|---|
| tr | 8/14 (57.1%) |
| en | 12/15 (80.0%) |

| By kind of phrase | Exact |
|---|---|
| one order | 15/18 (83.3%) |
| bare action | 1/5 (20.0%) |
| several orders | 4/6 (66.7%) |
| refusal | 0/0 (0.0%) |

| By field | Right |
|---|---|
| number of orders | 26/29 (89.7%) |
| condition kind | 27/37 (73.0%) |
| condition number / unit / terrain | 20/22 (90.9%) |
| action kind | 32/37 (86.5%) |
| action target unit | 2/2 (100.0%) |

| Kind of miss | Count |
|---|---|
| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | 7 |
| Valid order refused | 2 |
| Text that is no order accepted as one | 0 |

## Misses (9)

- `tr-h01` "düşmanlar 3 kare yakınıma gelince geri çekilsinler"
  - expected: enemyWithin(cells: 3) → retreat
  - got: enemyDensityAbove(count: 3) → retreat
- `tr-h07` "komutan öldüğünde herkes dağılsın"
  - expected: commanderDead → scatter
  - got: refused noOrderRecognized
- `tr-h10` "ilerlemeye devam"
  - expected: always → advance
  - got: refused missingConditionParameter:enemyWithin
- `tr-h11` "olduğun yerde dur"
  - expected: always → hold
  - got: terrainIs(FermanCore.Terrain.open) → hold
- `tr-h13` "canım 40'ın altına düşerse geri çekil ve siper al"
  - expected: healthBelow(percent: 40) → retreat | always → takeCover
  - got: healthBelow(percent: 40) → retreat | healthBelow(percent: 40) → takeCover
- `tr-h14` "ormanda siper al, düşman 3 kareden yakınsa yüklen, değilse ilerle"
  - expected: terrainIs(FermanCore.Terrain.forest) → takeCover | enemyWithin(cells: 3) → focusFire(nil) | always → advance
  - got: enemyWithin(cells: 3) → useAbility | always → advance
- `en-h05` "if the closest enemy is an archer, target them"
  - expected: nearestEnemyType(okcu) → focusFire(nil)
  - got: nearestEnemyType(okcu) → focusFire(Optional(okcu))
- `en-h11` "stand your ground"
  - expected: always → hold
  - got: terrainIs(FermanCore.Terrain.open) → hold
- `en-h15` "open fire on cavalry"
  - expected: always → focusFire(Optional(suvari))
  - got: targetInRange(suvari) → focusFire(Optional(suvari))
