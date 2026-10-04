# Compiler accuracy — CompilerChain (held-out phrases)

**Exact match: 27/29 (93.1%)**

Time per phrase: p50 0 ms · p95 1525 ms · max 1810 ms

| By language | Exact |
|---|---|
| tr | 13/14 (92.9%) |
| en | 14/15 (93.3%) |

| By kind of phrase | Exact |
|---|---|
| one order | 18/18 (100.0%) |
| bare action | 4/5 (80.0%) |
| several orders | 5/6 (83.3%) |
| refusal | 0/0 (0.0%) |

| By field | Right |
|---|---|
| number of orders | 28/29 (96.6%) |
| condition kind | 33/37 (89.2%) |
| condition number / unit / terrain | 20/22 (90.9%) |
| action kind | 34/37 (91.9%) |
| action target unit | 2/2 (100.0%) |

| Kind of miss | Count |
|---|---|
| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | 2 |
| Valid order refused | 0 |
| Text that is no order accepted as one | 0 |

## Misses (2)

- `tr-h14` "ormanda siper al, düşman 3 kareden yakınsa yüklen, değilse ilerle"
  - expected: terrainIs(FermanCore.Terrain.forest) → takeCover | enemyWithin(cells: 3) → focusFire(nil) | always → advance
  - got: enemyWithin(cells: 3) → useAbility | always → advance
- `en-h15` "open fire on cavalry"
  - expected: always → focusFire(Optional(suvari))
  - got: targetInRange(suvari) → focusFire(Optional(suvari))
