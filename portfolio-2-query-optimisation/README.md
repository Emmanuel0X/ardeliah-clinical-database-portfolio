# Portfolio 2: Query Processing and Optimisation

**Case study:** Ardeliah Clinical System (outpatient clinic: appointments, consultations, prescriptions, lab workflow).
**DBMS:** PostgreSQL 16.15.
**Headline result:** on 185,304 appointments, adding four targeted indexes cut the key lookups from 1.4 to 21 ms down to 0.17 to 0.38 ms (8x to 56x faster), and reduced pages read by 64% to 99%. Details in `performance-analysis.md`.

## Files

| File | What it contains |
|---|---|
| `seed-bulk-data.sql` | Deterministic synthetic data generator (20,003 patients, 185,304 appointments, and everything that follows from them) |
| `queries.sql` | 15 queries: SELECT/WHERE, INNER and LEFT JOIN, six-table join, correlated and non-correlated subqueries, GROUP BY/HAVING, ORDER BY/LIMIT, NOT EXISTS, a window function, SUM/AVG |
| `query-results.md` | Real `psql` output for all 15 queries |
| `execution-plans.md` | Before and after `EXPLAIN (ANALYZE, BUFFERS)` plans for five key queries, with explanation |
| `indexing-strategy.sql` | The seven indexes, each with the reason it exists |
| `drop-indexes.sql` | Removes those indexes to reproduce the baseline |
| `run-benchmark.sh` | Repeatable timing script (median of six runs after a warm-up) |
| `performance-analysis.md` | Results table, cost of the indexes, and limitations |
| `evidence/` | Raw plans, timings, index sizes and the write-cost test |

## How to reproduce

```bash
# 1. Build the database (from the repository root)
createdb ardeliah
psql -d ardeliah -f portfolio-1-database-design/create-tables.sql
psql -d ardeliah -f portfolio-1-database-design/sample-data.sql
cd portfolio-2-query-optimisation
psql -d ardeliah -f seed-bulk-data.sql      # about 10 seconds

# 2. Run the workload
psql -d ardeliah -f queries.sql

# 3. Baseline benchmark, then add indexes, then benchmark again
./run-benchmark.sh before
psql -d ardeliah -f indexing-strategy.sql
./run-benchmark.sh after
```

To go back to the baseline, run `psql -d ardeliah -f drop-indexes.sql`.

## How it was tested

1. All scripts were run from an empty database with `ON_ERROR_STOP=1`; none produced errors.
2. Row counts after loading were checked against the figures quoted in the documents.
3. The first draft of the data generator produced unrealistic rows (lab requests from 2024 still "pending", a cream dosed as "1 tablet", a Q5 threshold that matched nothing), so it was corrected and the whole database rebuilt before any results were recorded.
4. Timings use the median of six runs after a warm-up run. K4 acts as a control: it uses an index that already existed, and its timing did not change.
5. While reading the after-plans, two comments I had written in `indexing-strategy.sql` turned out to be wrong (about sort elimination in K2 and about column selectivity in `idx_patient_name`). They were corrected to match what the plans show.

## Key design decisions

- **Index only what the plans justify.** Each of the four main indexes fixes a specific sequential scan seen in the baseline plans.
- **A partial index for the lab queue**, because pending requests are under 1% of the table: 16 kB instead of over a megabyte.
- **Reuse existing structures.** The Portfolio 1 unique index already serves the doctor schedule query, so no new index was added for it.
- **Report the costs honestly:** index sizes, write slowdown (about six times for a bulk insert), and the fact that reporting queries are left as sequential scans on purpose.

## Evidence to screenshot for the LMS

1. Output of `seed-bulk-data.sql` ending with the row-count table.
2. `./run-benchmark.sh before` and `./run-benchmark.sh after` summary tables.
3. The K2 plan before (`Seq Scan on appointment`) next to after (`Bitmap Index Scan on idx_appointment_patient_date`).
4. `\di+ ardeliah.idx_*` showing index sizes.
