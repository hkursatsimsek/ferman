# Compiler accuracy — TemplateCompiler (held-out phrases)

**Exact match: 25/29 (86.2%)**

Time per phrase: p50 0 ms · p95 1 ms · max 1 ms

| By language | Exact |
|---|---|
| tr | 13/14 (92.9%) |
| en | 12/15 (80.0%) |

| By kind of phrase | Exact |
|---|---|
| one order | 17/18 (94.4%) |
| bare action | 3/5 (60.0%) |
| several orders | 5/6 (83.3%) |
| refusal | 0/0 (0.0%) |

| By field | Right |
|---|---|
| number of orders | 25/29 (86.2%) |
| condition kind | 31/37 (83.8%) |
| condition number / unit / terrain | 19/22 (86.4%) |
| action kind | 31/37 (83.8%) |
| action target unit | 1/2 (50.0%) |

| Kind of miss | Count |
|---|---|
| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | 0 |
| Valid order refused | 4 |
| Text that is no order accepted as one | 0 |

## Misses (4)

- `tr-h14` "ormanda siper al, düşman 3 kareden yakınsa yüklen, değilse ilerle"
  - expected: terrainIs(FermanCore.Terrain.forest) → takeCover | enemyWithin(cells: 3) → focusFire(nil) | always → advance
  - got: refused unrecognizedCondition
- `en-h31` "after 30 seconds sweep in from the right"
  - expected: timeAfter(seconds: 30) → flankRight
  - got: refused unrecognizedAction:timeAfter
- `en-h10` "keep moving forward"
  - expected: always → advance
  - got: refused noOrderRecognized
- `en-h15` "open fire on cavalry"
  - expected: always → focusFire(Optional(suvari))
  - got: refused noOrderRecognized
