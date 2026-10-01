# Compiler accuracy — TemplateCompiler (held-out phrases)

**Exact match: 23/29 (79.3%)**

| By language | Exact |
|---|---|
| tr | 13/14 (92.9%) |
| en | 10/15 (66.7%) |

| By kind of phrase | Exact |
|---|---|
| one order | 16/18 (88.9%) |
| bare action | 3/5 (60.0%) |
| several orders | 4/6 (66.7%) |
| refusal | 0/0 (0.0%) |

| By field | Right |
|---|---|
| number of orders | 23/29 (79.3%) |
| condition kind | 28/37 (75.7%) |
| condition number / unit / terrain | 17/22 (77.3%) |
| action kind | 28/37 (75.7%) |
| action target unit | 1/2 (50.0%) |

| Kind of miss | Count |
|---|---|
| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | 0 |
| Valid order refused | 6 |
| Text that is no order accepted as one | 0 |

## Misses (6)

- `tr-h14` "ormanda siper al, düşman 3 kareden yakınsa yüklen, değilse ilerle"
  - expected: terrainIs(FermanCore.Terrain.forest) → takeCover | enemyWithin(cells: 3) → focusFire(nil) | always → advance
  - got: refused unrecognizedCondition
- `en-h03` "protect the general if morale is under 30%"
  - expected: moraleBelow(percent: 30) → guardCommander
  - got: refused missingAction:moraleBelow
- `en-h06` "after 15 seconds swing around to the left"
  - expected: timeAfter(seconds: 15) → flankLeft
  - got: refused missingAction:timeAfter
- `en-h10` "keep moving forward"
  - expected: always → advance
  - got: refused noOrderRecognized
- `en-h12` "if an enemy gets within 2 cells raise the shield wall, otherwise keep advancing"
  - expected: enemyWithin(cells: 2) → useAbility | always → advance
  - got: refused missingAction:always
- `en-h15` "open fire on cavalry"
  - expected: always → focusFire(Optional(suvari))
  - got: refused noOrderRecognized
