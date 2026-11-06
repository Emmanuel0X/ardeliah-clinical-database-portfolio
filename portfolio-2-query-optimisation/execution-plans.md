# Execution Plans: before and after indexing

All plans are real output from `EXPLAIN (ANALYZE, BUFFERS)` on PostgreSQL 16.15. The `Buffers: shared hit` lines are removed here for readability; the complete plans are in `evidence/plans-before.txt` and `evidence/plans-after.txt`. Times in the plan blocks come from a single run, so they differ slightly from the medians in `performance-analysis.md`, which are taken over six runs.

## How to read a plan

- A plan is a tree; PostgreSQL reads it from the innermost, most indented nodes outward.
- `cost=a..b` is the planner's estimate (arbitrary units); `actual time` and `rows` are what really happened.
- **Seq Scan** reads the whole table. **Index Scan** and **Bitmap Index Scan** use an index to find matching rows. A bitmap scan collects all matching row locations first and then reads the table pages in order.
- `Rows Removed by Filter` shows wasted work: rows read and then thrown away.
- **Buffers shared hit** counts 8 kB pages read from memory, a good measure of how much work a query does that does not depend on how fast the machine is.


## K1: patient name search (Q1)

### Before (baseline, no extra indexes)

```
Limit  (cost=603.52..603.55 rows=10 width=33) (actual time=2.953..2.956 rows=10 loops=1)
  ->  Sort  (cost=603.52..603.58 rows=22 width=33) (actual time=2.952..2.953 rows=10 loops=1)
        Sort Key: date_of_birth
        Sort Method: top-N heapsort  Memory: 26kB
        ->  Seq Scan on patient  (cost=0.00..603.05 rows=22 width=33) (actual time=0.156..2.917 rows=24 loops=1)
              Filter: (((last_name)::text = 'Okeke'::text) AND ((first_name)::text = 'Chinedu'::text))
              Rows Removed by Filter: 19979
Execution Time: 2.990 ms
```

**Before.** PostgreSQL has no index on the name columns, so it uses a `Seq Scan on patient`: it reads every page of the table (303 buffer hits) and the filter throws away 19,979 rows to keep the 24 Chinedu Okekes. The `Sort` then picks the 10 youngest by date of birth.

### After (with `indexing-strategy.sql`)

```
Limit  (cost=75.53..75.56 rows=10 width=33) (actual time=0.127..0.128 rows=10 loops=1)
  ->  Sort  (cost=75.53..75.59 rows=22 width=33) (actual time=0.126..0.126 rows=10 loops=1)
        Sort Key: date_of_birth
        Sort Method: top-N heapsort  Memory: 26kB
        ->  Bitmap Heap Scan on patient  (cost=4.51..75.06 rows=22 width=33) (actual time=0.023..0.095 rows=24 loops=1)
              Recheck Cond: (((last_name)::text = 'Okeke'::text) AND ((first_name)::text = 'Chinedu'::text))
              Heap Blocks: exact=22
              ->  Bitmap Index Scan on idx_patient_name  (cost=0.00..4.51 rows=22 width=0) (actual time=0.012..0.012 rows=24 loops=1)
                    Index Cond: (((last_name)::text = 'Okeke'::text) AND ((first_name)::text = 'Chinedu'::text))
Execution Time: 0.161 ms
```

**After.** The planner switches to a `Bitmap Index Scan on idx_patient_name`. The index lists the 24 matching row locations directly and only 22 table pages are visited. Total buffer hits drop from 306 to 27.


## K2: patient appointment history (Q2)

### Before (baseline, no extra indexes)

```
Limit  (cost=4568.15..4568.17 rows=10 width=68) (actual time=9.362..9.366 rows=9 loops=1)
  ->  Sort  (cost=4568.15..4568.17 rows=10 width=68) (actual time=9.360..9.362 rows=9 loops=1)
        Sort Key: a.appointment_date DESC, a.start_time
        Sort Method: quicksort  Memory: 26kB
        ->  Nested Loop  (cost=0.00..4567.98 rows=10 width=68) (actual time=9.290..9.334 rows=9 loops=1)
              Join Filter: (s.specialisation_id = d.specialisation_id)
              Rows Removed by Join Filter: 27
              ->  Nested Loop  (cost=0.00..4565.73 rows=10 width=35) (actual time=9.269..9.308 rows=9 loops=1)
                    Join Filter: (d.doctor_id = a.doctor_id)
                    Rows Removed by Join Filter: 351
                    ->  Seq Scan on doctor d  (cost=0.00..1.40 rows=40 width=18) (actual time=0.003..0.007 rows=40 loops=1)
                    ->  Materialize  (cost=0.00..4558.35 rows=10 width=25) (actual time=0.018..0.232 rows=9 loops=40)
                          ->  Seq Scan on appointment a  (cost=0.00..4558.30 rows=10 width=25) (actual time=0.696..9.220 rows=9 loops=1)
                                Filter: (patient_id = 7421)
                                Rows Removed by Filter: 185295
              ->  Materialize  (cost=0.00..1.12 rows=8 width=17) (actual time=0.002..0.002 rows=4 loops=9)
                    ->  Seq Scan on specialisation s  (cost=0.00..1.08 rows=8 width=17) (actual time=0.011..0.011 rows=7 loops=1)
Execution Time: 9.407 ms
```

**Before.** `Seq Scan on appointment` reads all 2,242 pages and discards 185,295 rows to find the 9 belonging to patient 7421. The two small tables (`doctor`, `specialisation`) are joined with nested loops and `Materialize`, which is harmless at this size.

### After (with `indexing-strategy.sql`)

```
Limit  (cost=45.98..46.00 rows=10 width=68) (actual time=0.143..0.147 rows=9 loops=1)
  ->  Sort  (cost=45.98..46.00 rows=10 width=68) (actual time=0.142..0.145 rows=9 loops=1)
        Sort Key: a.appointment_date DESC, a.start_time
        Sort Method: quicksort  Memory: 26kB
        ->  Hash Join  (cost=7.58..45.81 rows=10 width=68) (actual time=0.075..0.123 rows=9 loops=1)
              Hash Cond: (d.specialisation_id = s.specialisation_id)
              ->  Hash Join  (cost=6.40..44.55 rows=10 width=35) (actual time=0.046..0.090 rows=9 loops=1)
                    Hash Cond: (a.doctor_id = d.doctor_id)
                    ->  Bitmap Heap Scan on appointment a  (cost=4.50..42.62 rows=10 width=25) (actual time=0.021..0.061 rows=9 loops=1)
                          Recheck Cond: (patient_id = 7421)
                          Heap Blocks: exact=9
                          ->  Bitmap Index Scan on idx_appointment_patient_date  (cost=0.00..4.50 rows=10 width=0) (actual time=0.011..0.011 rows=9 loops=1)
                                Index Cond: (patient_id = 7421)
                    ->  Hash  (cost=1.40..1.40 rows=40 width=18) (actual time=0.013..0.013 rows=40 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 11kB
                          ->  Seq Scan on doctor d  (cost=0.00..1.40 rows=40 width=18) (actual time=0.001..0.005 rows=40 loops=1)
              ->  Hash  (cost=1.08..1.08 rows=8 width=17) (actual time=0.017..0.018 rows=8 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    ->  Seq Scan on specialisation s  (cost=0.00..1.08 rows=8 width=17) (actual time=0.006..0.007 rows=8 loops=1)
Execution Time: 0.207 ms
```

**After.** A `Bitmap Index Scan on idx_appointment_patient_date` goes straight to the 9 appointments (9 heap blocks). The joins to `doctor` and `specialisation` become hash joins over tiny tables. A `Sort` node is still present, because with only 9 rows the planner finds a bitmap scan plus a small sort cheaper than reading the index in order.


## K3: patient prescription history (Q4)

### Before (baseline, no extra indexes)

```
Sort  (cost=6474.24..6474.26 rows=8 width=64) (actual time=18.374..18.378 rows=5 loops=1)
  Sort Key: a.appointment_date DESC, m.generic_name
  Sort Method: quicksort  Memory: 25kB
  ->  Nested Loop  (cost=4642.08..6474.12 rows=8 width=64) (actual time=9.403..18.341 rows=5 loops=1)
        ->  Nested Loop  (cost=4641.95..6472.91 rows=8 width=41) (actual time=9.396..18.325 rows=5 loops=1)
              ->  Hash Join  (cost=4641.53..6470.17 rows=5 width=17) (actual time=9.374..18.267 rows=3 loops=1)
                    Hash Cond: (pr.consultation_id = c.consultation_id)
                    ->  Seq Scan on prescription pr  (cost=0.00..1500.89 rows=87389 width=17) (actual time=0.003..4.540 rows=87389 loops=1)
                    ->  Hash  (cost=4641.43..4641.43 rows=8 width=8) (actual time=8.703..8.705 rows=5 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 9kB
                          ->  Nested Loop  (cost=0.29..4641.43 rows=8 width=8) (actual time=0.748..8.686 rows=5 loops=1)
                                ->  Seq Scan on appointment a  (cost=0.00..4558.30 rows=10 width=8) (actual time=0.726..8.577 rows=9 loops=1)
                                      Filter: (patient_id = 7421)
                                      Rows Removed by Filter: 185295
                                ->  Index Scan using consultation_appointment_id_key on consultation c  (cost=0.29..8.31 rows=1 width=8) (actual time=0.009..0.009 rows=1 loops=9)
                                      Index Cond: (appointment_id = a.appointment_id)
              ->  Index Scan using prescription_item_pkey on prescription_item pi  (cost=0.42..0.53 rows=2 width=32) (actual time=0.014..0.017 rows=2 loops=3)
                    Index Cond: (prescription_id = pr.prescription_id)
        ->  Index Scan using medication_pkey on medication m  (cost=0.14..0.15 rows=1 width=31) (actual time=0.002..0.002 rows=1 loops=5)
              Index Cond: (medication_id = pi.medication_id)
Execution Time: 18.467 ms
```

**Before.** Two sequential scans: `Seq Scan on appointment` (discarding 185,295 rows) and `Seq Scan on prescription` (all 87,389 rows) feeding a `Hash Join`. Only 5 result rows come out of roughly 270,000 rows read.

### After (with `indexing-strategy.sql`)

```
Sort  (cost=133.93..133.95 rows=8 width=64) (actual time=0.235..0.237 rows=5 loops=1)
  Sort Key: a.appointment_date DESC, m.generic_name
  Sort Method: quicksort  Memory: 25kB
  ->  Nested Loop  (cost=5.51..133.81 rows=8 width=64) (actual time=0.197..0.206 rows=5 loops=1)
        Join Filter: (pi.medication_id = m.medication_id)
        Rows Removed by Join Filter: 55
        ->  Seq Scan on medication m  (cost=0.00..1.12 rows=12 width=31) (actual time=0.002..0.004 rows=12 loops=1)
        ->  Materialize  (cost=5.51..131.27 rows=8 width=41) (actual time=0.005..0.016 rows=5 loops=12)
              ->  Nested Loop  (cost=5.51..131.23 rows=8 width=41) (actual time=0.058..0.181 rows=5 loops=1)
                    ->  Nested Loop  (cost=5.09..128.49 rows=5 width=17) (actual time=0.044..0.143 rows=3 loops=1)
                          ->  Nested Loop  (cost=4.79..125.74 rows=8 width=8) (actual time=0.035..0.116 rows=5 loops=1)
                                ->  Bitmap Heap Scan on appointment a  (cost=4.50..42.62 rows=10 width=8) (actual time=0.020..0.055 rows=9 loops=1)
                                      Recheck Cond: (patient_id = 7421)
                                      Heap Blocks: exact=9
                                      ->  Bitmap Index Scan on idx_appointment_patient_date  (cost=0.00..4.50 rows=10 width=0) (actual time=0.010..0.011 rows=9 loops=1)
                                            Index Cond: (patient_id = 7421)
                                ->  Index Scan using consultation_appointment_id_key on consultation c  (cost=0.29..8.31 rows=1 width=8) (actual time=0.006..0.006 rows=1 loops=9)
                                      Index Cond: (appointment_id = a.appointment_id)
                          ->  Index Scan using idx_prescription_consultation on prescription pr  (cost=0.29..0.33 rows=1 width=17) (actual time=0.005..0.005 rows=1 loops=5)
                                Index Cond: (consultation_id = c.consultation_id)
                    ->  Index Scan using prescription_item_pkey on prescription_item pi  (cost=0.42..0.53 rows=2 width=32) (actual time=0.010..0.012 rows=2 loops=3)
                          Index Cond: (prescription_id = pr.prescription_id)
Execution Time: 0.326 ms
```

**After.** Every large table is now reached through an index, as a chain of nested loops: `idx_appointment_patient_date` to `consultation_appointment_id_key` (created by the UNIQUE constraint) to `idx_prescription_consultation` to `prescription_item_pkey`. Buffer hits fall from 2,922 to 69. The `Seq Scan on medication` reads a 12-row table and is fine.


## K4: doctor week sheet (Q11)

### Before (baseline, no extra indexes)

```
Sort  (cost=305.43..305.50 rows=27 width=69) (actual time=0.382..0.385 rows=29 loops=1)
  Sort Key: a.appointment_date, a.start_time
  Sort Method: quicksort  Memory: 27kB
  ->  Nested Loop  (cost=5.05..304.79 rows=27 width=69) (actual time=0.084..0.295 rows=29 loops=1)
        ->  Bitmap Heap Scan on appointment a  (cost=4.76..104.42 rows=27 width=41) (actual time=0.064..0.098 rows=29 loops=1)
              Recheck Cond: ((doctor_id = 12) AND (appointment_date >= '2026-10-12'::date) AND (appointment_date <= '2026-10-16'::date) AND ((status)::text <> 'CANCELLED'::text))
              Heap Blocks: exact=14
              ->  Bitmap Index Scan on uq_doctor_slot_active  (cost=0.00..4.76 rows=27 width=0) (actual time=0.039..0.039 rows=29 loops=1)
                    Index Cond: ((doctor_id = 12) AND (appointment_date >= '2026-10-12'::date) AND (appointment_date <= '2026-10-16'::date))
        ->  Index Scan using patient_pkey on patient p  (cost=0.29..7.42 rows=1 width=17) (actual time=0.006..0.006 rows=1 loops=29)
              Index Cond: (patient_id = a.patient_id)
Execution Time: 0.444 ms
```

**Before.** This query already used an index. The Portfolio 1 partial unique index `uq_doctor_slot_active` (doctor_id, appointment_date, start_time, only for non-cancelled rows) matches the filter, because the query also says `status <> 'CANCELLED'`, which implies the index condition.

### After (with `indexing-strategy.sql`)

```
Sort  (cost=277.75..277.81 rows=24 width=69) (actual time=0.285..0.288 rows=29 loops=1)
  Sort Key: a.appointment_date, a.start_time
  Sort Method: quicksort  Memory: 27kB
  ->  Nested Loop  (cost=5.01..277.20 rows=24 width=69) (actual time=0.056..0.251 rows=29 loops=1)
        ->  Bitmap Heap Scan on appointment a  (cost=4.73..93.76 rows=24 width=41) (actual time=0.039..0.066 rows=29 loops=1)
              Recheck Cond: ((doctor_id = 12) AND (appointment_date >= '2026-10-12'::date) AND (appointment_date <= '2026-10-16'::date) AND ((status)::text <> 'CANCELLED'::text))
              Heap Blocks: exact=14
              ->  Bitmap Index Scan on uq_doctor_slot_active  (cost=0.00..4.72 rows=24 width=0) (actual time=0.028..0.028 rows=29 loops=1)
                    Index Cond: ((doctor_id = 12) AND (appointment_date >= '2026-10-12'::date) AND (appointment_date <= '2026-10-16'::date))
        ->  Index Scan using patient_pkey on patient p  (cost=0.29..7.64 rows=1 width=17) (actual time=0.006..0.006 rows=1 loops=29)
              Index Cond: (patient_id = a.patient_id)
Execution Time: 0.344 ms
```

**After.** Identical plan and identical buffer count (112). No new index was needed, and the small timing difference is run-to-run noise (the min-max ranges of the two runs overlap). This is the control case: it shows the benchmark is not just reporting a faster second run.


## K5: urgent lab work queue (Q12)

### Before (baseline, no extra indexes)

```
Limit  (cost=1430.38..1430.43 rows=20 width=42) (actual time=4.829..4.833 rows=20 loops=1)
  ->  Sort  (cost=1430.38..1430.53 rows=58 width=42) (actual time=4.827..4.829 rows=20 loops=1)
        Sort Key: rq.requested_at
        Sort Method: top-N heapsort  Memory: 28kB
        ->  Nested Loop  (cost=0.00..1428.84 rows=58 width=42) (actual time=0.295..4.794 rows=41 loops=1)
              Join Filter: (t.test_id = rq.test_id)
              Rows Removed by Join Filter: 160
              ->  Seq Scan on lab_request rq  (cost=0.00..1421.43 rows=58 width=26) (actual time=0.285..4.747 rows=41 loops=1)
                    Filter: (((status)::text = ANY ('{REQUESTED,COLLECTED}'::text[])) AND ((priority)::text = 'URGENT'::text))
                    Rows Removed by Filter: 58321
              ->  Materialize  (cost=0.00..1.12 rows=8 width=24) (actual time=0.000..0.001 rows=5 loops=41)
                    ->  Seq Scan on lab_test_catalog t  (cost=0.00..1.08 rows=8 width=24) (actual time=0.002..0.003 rows=8 loops=1)
Execution Time: 4.861 ms
```

**Before.** `Seq Scan on lab_request` reads every page (546 buffer hits) and removes 58,321 rows to find 41 that are still pending and urgent. Pending requests are well under 1% of the table, which makes a full scan wasteful.

### After (with `indexing-strategy.sql`)

```
Limit  (cost=0.15..424.23 rows=20 width=42) (actual time=0.049..0.280 rows=20 loops=1)
  ->  Nested Loop  (cost=0.15..1060.36 rows=50 width=42) (actual time=0.048..0.277 rows=20 loops=1)
        Join Filter: (t.test_id = rq.test_id)
        Rows Removed by Join Filter: 83
        ->  Index Scan using idx_lab_request_pending on lab_request rq  (cost=0.15..1053.82 rows=50 width=26) (actual time=0.035..0.250 rows=20 loops=1)
              Filter: ((priority)::text = 'URGENT'::text)
              Rows Removed by Filter: 190
        ->  Materialize  (cost=0.00..1.12 rows=8 width=24) (actual time=0.000..0.001 rows=5 loops=20)
              ->  Seq Scan on lab_test_catalog t  (cost=0.00..1.08 rows=8 width=24) (actual time=0.003..0.004 rows=8 loops=1)
Execution Time: 0.307 ms
```

**After.** `Index Scan using idx_lab_request_pending`. The partial index contains only the pending requests, in requested_at order, so the `ORDER BY ... LIMIT 20` is satisfied by reading the index from the start and stopping after 20 matches. The `priority = 'URGENT'` condition is applied to those few rows (190 non-urgent ones skipped). The index is only 16 kB. Buffer hits fall from 550 to 200.
