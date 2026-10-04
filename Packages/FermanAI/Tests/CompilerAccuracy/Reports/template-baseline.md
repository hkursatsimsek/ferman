# Compiler accuracy — TemplateCompiler

**Exact match: 149/150 (99.3%)**

Time per phrase: p50 0 ms · p95 1 ms · max 1 ms

| By language | Exact |
|---|---|
| tr | 75/76 (98.7%) |
| en | 74/74 (100.0%) |

| By kind of phrase | Exact |
|---|---|
| one order | 81/82 (98.8%) |
| bare action | 24/24 (100.0%) |
| several orders | 23/23 (100.0%) |
| refusal | 21/21 (100.0%) |

| By field | Right |
|---|---|
| number of orders | 128/129 (99.2%) |
| condition kind | 159/160 (99.4%) |
| condition number / unit / terrain | 103/104 (99.0%) |
| action kind | 159/160 (99.4%) |
| action target unit | 12/12 (100.0%) |
| refusal reason | 21/21 (100.0%) |

| Kind of miss | Count |
|---|---|
| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | 0 |
| Valid order refused | 1 |
| Text that is no order accepted as one | 0 |

## Misses (1)

- `tr-012` "tepeye çıkınca bekle"
  - expected: terrainIs(FermanCore.Terrain.hill) → hold
  - got: refused unrecognizedCondition
