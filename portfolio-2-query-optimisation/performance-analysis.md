# Performance Analysis: Ardeliah Clinical System

## What was measured and how

- **Data:** 20,003 patients, 185,304 appointments, 145,954 consultations, 87,389 prescriptions (139,686 drug lines) and 58,362 lab requests, loaded by `seed-bulk-data.sql`.
- **Environment:** PostgreSQL 16.15 on a small Linux sandbox VM, default configuration, all data fitting in memory. Absolute milliseconds will differ on another machine, so the **ratios and buffer counts** are the meaningful results.
- **Method:** `run-benchmark.sh` runs `EXPLAIN (ANALYZE, BUFFERS)` seven times per query, discards the first run as cache warm-up, and reports the median of the other six. "Before" is the schema from Portfolio 1 with no extra indexes; "after" adds `indexing-strategy.sql` followed by `ANALYZE`.
- **Raw evidence:** `evidence/timings-*.txt`, `evidence/plans-*.txt`, `evidence/index-sizes.txt`, `evidence/write-cost-results.txt`.

## Results

| Query | Before (median) | After (median) | Speed-up | Buffer hits before | Buffer hits after |
|---|---|---|---|---|---|
| K1 Patient name search (Q1) | 1.427 ms | 0.172 ms | 8.3x | 306 | 27 |
| K2 Patient appointment history (Q2) | 10.218 ms | 0.221 ms | 46.2x | 2,252 | 22 |
| K3 Patient prescription history (Q4) | 20.973 ms | 0.377 ms | 55.6x | 2,922 | 69 |
| K4 Doctor week sheet (Q11), control | 0.429 ms | 0.333 ms | not significant | 112 | 112 |
| K5 Urgent lab work queue (Q12) | 4.735 ms | 0.356 ms | 13.3x | 550 | 200 |

Buffer hits (8 kB pages touched) fell by 91% (K1), 99% (K2), 97.6% (K3) and 63.6% (K5). K4 is the control: it already used an existing index, the plan and buffer count did not change, and the small time difference is within run-to-run noise (the before and after min-max ranges overlap). Seeing the control stay flat is what makes the other four results believable.

## Why each index helped

1. **`idx_patient_name` (K1).** Without it, finding 24 patients meant reading all 303 pages and discarding 19,979 rows. The B-tree gives the matching row locations directly.
2. **`idx_appointment_patient_date` (K2, K3).** `appointment` is the largest table and `patient_id` is the most common way into it (portal "my appointments", reception lookup, prescription history). It turned a 185,295-row scan into a 9-row index lookup, and it also removed the large scan from K3.
3. **`idx_prescription_consultation` (K3).** PostgreSQL does not index a foreign key column automatically. Without this, joining `prescription` to `consultation` forced a hash join over all 87,389 prescriptions. With it, K3 becomes a chain of index lookups, and 69 buffer hits is all it needs.
4. **`idx_lab_request_pending` (K5).** This is a partial index on the rows that are still pending, which are about 0.6% of the table (356 of 58,362). It is only 16 kB, versus about 1.3 MB for a full index on the same table (`idx_lab_request_consultation` shows the order of magnitude), and it also delivers rows already sorted by `requested_at`.

## What the indexes cost

| Index | Size | Table size |
|---|---|---|
| `idx_appointment_patient_date` | 5,720 kB | `appointment` 18 MB |
| `idx_prescription_consultation` | 1,928 kB | |
| `idx_lab_request_consultation` | 1,296 kB | `lab_request` 4,368 kB |
| `idx_prescription_item_medication` | 968 kB | |
| `idx_history_patient_condition` | 336 kB | |
| `idx_patient_name` | 184 kB | |
| `idx_lab_request_pending` | 16 kB | |

**Storage:** the largest index adds about a third of the size of the table it supports.

**Writes:** `evidence/write-cost-test.sql` inserted all 185,304 appointment rows into a scratch table three times each way. Without the index it took 36 to 43 ms; with `idx_appointment_patient_date` it took 248 to 253 ms, about six times longer. That is roughly 1.3 microseconds per row, so for a clinic booking a few appointments a minute it is irrelevant. It does matter for bulk loads such as a data migration, where the sensible approach is to load first and create the indexes afterwards. The scratch table had no other indexes, so the baseline is slightly optimistic compared with the real table.

## Limitations and honest caveats

- **Small dataset.** 185k appointments is modest. All the data is cached in memory, so the "before" timings are, if anything, flattering to the unindexed version; with cold disk reads the gap would be larger.
- **Synthetic, uniform data.** Patients have about 9 appointments each and names come from short lists, so selectivity is more uniform than in real life.
- **Planner choices can surprise.** In K2 the planner still used a bitmap scan plus a sort instead of reading the index in order, because for 9 rows that is cheaper. The index's ordering would only be used for patients with very long histories.
- **Supporting indexes were not benchmarked individually** (`idx_lab_request_consultation`, `idx_prescription_item_medication`, `idx_history_patient_condition`). They are justified by foreign-key joins and cascade deletes, not by a measured gain.
- **Queries that did not need indexing.** Reporting queries aggregate most of a table by design, so a sequential scan is the right plan for them (checked with `EXPLAIN ANALYZE`, one run each, after indexing): Q5 15.8 ms, Q6 15.9 ms, Q9 40.6 ms, Q10 25.3 ms, Q15 28.7 ms, plus the anti-join in Q3 at 42.1 ms. The six-table aggregate in Q14 is the slowest query in the workload at 242 ms. It scans four large tables, so an index will not fix it; if it were run often, a materialised view refreshed nightly would be the right tool. The point-lookup queries (Q1, Q2, Q4, Q7, Q8, Q11, Q12) all finish in under 2 ms and use index scans.

## Possible next steps

- Partition `appointment` by month if it grows into the tens of millions of rows, so that "this week" queries only touch recent partitions.
- Add a materialised view for the monthly outcome report (Q6) if it is run often.
- Revisit the indexes using `pg_stat_user_indexes` after a few weeks of real traffic, and drop any that are never used.
