# Compiler accuracy — CompilerChain

**Exact match: 148/150 (98.7%)**

Time per phrase: p50 0 ms · p95 1 ms · max 1780 ms

| By language | Exact |
|---|---|
| tr | 75/76 (98.7%) |
| en | 73/74 (98.6%) |

| By kind of phrase | Exact |
|---|---|
| one order | 82/82 (100.0%) |
| bare action | 24/24 (100.0%) |
| several orders | 23/23 (100.0%) |
| refusal | 19/21 (90.5%) |

| By field | Right |
|---|---|
| number of orders | 129/129 (100.0%) |
| condition kind | 160/160 (100.0%) |
| condition number / unit / terrain | 104/104 (100.0%) |
| action kind | 160/160 (100.0%) |
| action target unit | 12/12 (100.0%) |
| refusal reason | 19/21 (90.5%) |

| Kind of miss | Count |
|---|---|
| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | 0 |
| Valid order refused | 0 |
| Text that is no order accepted as one | 0 |

## Misses (2)

- `tr-069` "düşman görünce saldır"
  - expected: refused unrecognizedCondition
  - got: refused missingConditionParameter:enemyWithin
- `en-067` "retreat if an enemy shows up"
  - expected: refused unrecognizedCondition
  - got: refused missingConditionParameter:enemyWithin
