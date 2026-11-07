# Cross-check: MongoDB-style results versus PostgreSQL

Each check runs the same business question twice: once as a MongoDB find/aggregate from `queries.js` (executed by the in-memory emulator in `verification/run-with-mingo.mjs` on the exported documents) and once as SQL on the original PostgreSQL tables, restricted to the same 303 exported patients. If the document model and the pipelines are right, the rows must be identical.

| Check | Rows compared | Result |
|---|---|---|
| patients | 1 | MATCH |
| appointments | 1 | MATCH |
| consultations | 1 | MATCH |
| embedded diagnoses (total) | 1 | MATCH |
| embedded prescription lines (total) | 1 | MATCH |
| embedded lab requests (total) | 1 | MATCH |
| Q2 appointments of patient 12 (newest 5) | 5 | MATCH |
| Q5 week sheet of doctor 12 | 1 | MATCH |
| Q6 diagnoses per ICD code | 12 | MATCH |
| Q7 top 5 medications by drug-days | 5 | MATCH |
| Q8 abnormal lab results per test | 8 | MATCH |
| Q9 malaria patients since 1 Oct 2026 | 1 | MATCH |
| Q10 open lab requests (oldest 5) | 5 | MATCH |
| Q11 appointment outcomes per month | 6 | MATCH |
| Q12 completed appointments per specialisation (Oct 2026) | 8 | MATCH |
| Q13 consultations and average diagnoses | 1 | MATCH |

**16 of 16 checks match.**


## patients: match

MongoDB side:

```
303
```

PostgreSQL side:

```
303
```

## appointments: match

MongoDB side:

```
2760
```

PostgreSQL side:

```
2760
```

## consultations: match

MongoDB side:

```
2161
```

PostgreSQL side:

```
2161
```

## embedded diagnoses (total): match

MongoDB side:

```
2589
```

PostgreSQL side:

```
2589
```

## embedded prescription lines (total): match

MongoDB side:

```
2051
```

PostgreSQL side:

```
2051
```

## embedded lab requests (total): match

MongoDB side:

```
848
```

PostgreSQL side:

```
848
```

## Q2 appointments of patient 12 (newest 5): match

MongoDB side:

```
2026-09-29T11:00:00.000Z|CANCELLED|Dr Hadiza Adamu
2026-09-16T13:30:00.000Z|COMPLETED|Dr Hadiza Umoh
2025-11-27T07:30:00.000Z|COMPLETED|Dr Peter Akinola
2025-09-17T14:00:00.000Z|COMPLETED|Dr Victor Akinola
2025-06-04T13:00:00.000Z|COMPLETED|Dr Linda Umoh
```

PostgreSQL side:

```
2026-09-29T11:00:00.000Z|CANCELLED|Dr Hadiza Adamu
2026-09-16T13:30:00.000Z|COMPLETED|Dr Hadiza Umoh
2025-11-27T07:30:00.000Z|COMPLETED|Dr Peter Akinola
2025-09-17T14:00:00.000Z|COMPLETED|Dr Victor Akinola
2025-06-04T13:00:00.000Z|COMPLETED|Dr Linda Umoh
```

## Q5 week sheet of doctor 12: match

MongoDB side:

```
2026-10-13T12:00:00.000Z|COMPLETED|Abdullahi Chukwu
```

PostgreSQL side:

```
2026-10-13T12:00:00.000Z|COMPLETED|Abdullahi Chukwu
```

## Q6 diagnoses per ICD code: match

MongoDB side:

```
A01.0|233|66
A09|226|62
K29.7|225|59
N39.0|225|53
I10|222|67
M54.5|221|63
E11.9|215|74
B50.9|210|51
J45.9|210|66
J06.9|203|64
D64.9|201|65
L20.9|198|50
```

PostgreSQL side:

```
A01.0|233|66
A09|226|62
K29.7|225|59
N39.0|225|53
I10|222|67
M54.5|221|63
E11.9|215|74
B50.9|210|51
J45.9|210|66
J06.9|203|64
D64.9|201|65
L20.9|198|50
```

## Q7 top 5 medications by drug-days: match

MongoDB side:

```
Oral rehydration salts|194|1736
Ibuprofen|181|1576
Omeprazole|172|1495
Salbutamol|172|1492
Artemether/Lumefantrine|174|1455
```

PostgreSQL side:

```
Oral rehydration salts|194|1736
Ibuprofen|181|1576
Omeprazole|172|1495
Salbutamol|172|1492
Artemether/Lumefantrine|174|1455
```

## Q8 abnormal lab results per test: match

MongoDB side:

```
Fasting blood glucose|108|39|36.1
Serum creatinine|117|39|33.3
Urinalysis: leucocytes|123|38|30.9
Total cholesterol|104|31|29.8
White blood cell count|96|28|29.2
Haemoglobin|112|32|28.6
Widal titre (O antigen)|86|21|24.4
Malaria parasite (MP) count|95|15|15.8
```

PostgreSQL side:

```
Fasting blood glucose|108|39|36.1
Serum creatinine|117|39|33.3
Urinalysis: leucocytes|123|38|30.9
Total cholesterol|104|31|29.8
White blood cell count|96|28|29.2
Haemoglobin|112|32|28.6
Widal titre (O antigen)|86|21|24.4
Malaria parasite (MP) count|95|15|15.8
```

## Q9 malaria patients since 1 Oct 2026: match

MongoDB side:

```
1,23,44,71,117,175,236,300
```

PostgreSQL side:

```
1,23,44,71,117,175,236,300
```

## Q10 open lab requests (oldest 5): match

MongoDB side:

```
53120|Total cholesterol|ROUTINE|COLLECTED
54751|Total cholesterol|ROUTINE|REQUESTED
32202|White blood cell count|ROUTINE|COLLECTED
56219|Total cholesterol|ROUTINE|COLLECTED
28897|Serum creatinine|ROUTINE|COLLECTED
```

PostgreSQL side:

```
53120|Total cholesterol|ROUTINE|COLLECTED
54751|Total cholesterol|ROUTINE|REQUESTED
32202|White blood cell count|ROUTINE|COLLECTED
56219|Total cholesterol|ROUTINE|COLLECTED
28897|Serum creatinine|ROUTINE|COLLECTED
```

## Q11 appointment outcomes per month: match

MongoDB side:

```
2026-05|94|75|8|11
2026-06|85|64|14|7
2026-07|75|53|10|12
2026-08|95|81|4|10
2026-09|75|61|7|7
2026-10|106|80|11|15
```

PostgreSQL side:

```
2026-05|94|75|8|11
2026-06|85|64|14|7
2026-07|75|53|10|12
2026-08|95|81|4|10
2026-09|75|61|7|7
2026-10|106|80|11|15
```

## Q12 completed appointments per specialisation (Oct 2026): match

MongoDB side:

```
General Practice|15
Internal Medicine|14
Dermatology|12
Obstetrics and Gynaecology|12
Cardiology|10
Orthopaedics|9
Ophthalmology|6
Paediatrics|2
```

PostgreSQL side:

```
General Practice|15
Internal Medicine|14
Dermatology|12
Obstetrics and Gynaecology|12
Cardiology|10
Orthopaedics|9
Ophthalmology|6
Paediatrics|2
```

## Q13 consultations and average diagnoses: match

MongoDB side:

```
2161|1.198
```

PostgreSQL side:

```
2161|1.198
```
