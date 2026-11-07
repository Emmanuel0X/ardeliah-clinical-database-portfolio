# Portfolio Summary: Ardeliah Clinical System

**Module:** MIT 8103 Advanced Database Systems, MSc Information Technology, Miva Open University
**Student:** Emmanuel (add matric number)
**GitHub repository:** https://github.com/Emmanuel0X/ardeliah-clinical-database-portfolio (private; reviewer access to be confirmed before submission)
**Database system:** PostgreSQL 16.15 (assumption stated in the root README). Portfolio 4 uses MongoDB syntax.

## 1. The case study

Ardeliah is a digital platform for outpatient care. Patients book appointments; doctors record consultations, diagnoses and e-prescriptions; receptionists manage schedules; laboratory technicians record test results that update the patient's diagnostic history. Correctness matters more than raw speed here, because a double-booked slot, a lost lab result or a wrong prescription harms real people.

## 2. What I built

| Portfolio | What it delivers | Evidence |
|---|---|---|
| **1 Design** | 19-table relational schema in 3NF, Mermaid ER diagram, normalisation reasoning, executable DDL with CHECK, UNIQUE and FOREIGN KEY constraints, a partial unique index that prevents double booking | Scripts run from an empty database without errors |
| **2 Query optimisation** | 15 queries (joins, subqueries, GROUP BY/HAVING, window function), 20,003 patients and 185,304 appointments of synthetic data, before and after `EXPLAIN (ANALYZE, BUFFERS)` for five queries, seven indexes | Key lookups fell from 1.4 to 21 ms down to 0.17 to 0.38 ms; the cost is about six times slower bulk inserts on the largest-indexed table |
| **3 Transactions** | COMMIT, ROLLBACK, SAVEPOINT, eleven two-session scenarios (dirty read, non-repeatable read, phantom, lost update, write skew, double booking, deadlock, `SKIP LOCKED`), a crash-recovery test | Real transcripts from two live sessions |
| **4 NoSQL** | MongoDB document model (9 collections), validators, indexes, 13 queries, write examples, export from the PostgreSQL data | Run by an in-memory emulator and checked against PostgreSQL (16 of 16 comparisons match); **not run on MongoDB itself** |
| **5 Distributed and cloud** | Replication, sharding, CAP and AWS design; architecture diagram | A real local streaming replica with failover and a real hash-partitioning demo; **no AWS deployment** |

## 3. Main findings

1. **Normalisation and constraints do real work.** The partial unique index that prevents two live appointments for one doctor and time was tested under concurrency in Portfolio 3: the second session waits, then fails with a duplicate-key error. The database enforces the rule even if the application has a bug.
2. **Indexes must be justified by plans.** Each main index in Portfolio 2 removes a specific sequential scan seen in the baseline plan. Reporting queries that read most of a table were left as sequential scans on purpose, and the write cost of indexing was measured rather than ignored.
3. **Isolation level is a decision, not a default.** In PostgreSQL, `READ COMMITTED` allows non-repeatable reads and lost updates unless statements are written carefully; `REPEATABLE READ` still allowed write skew, and only `SERIALIZABLE` stopped it, at the price of retrying transactions that fail with SQLSTATE 40001.
4. **A document model suits "the visit" but not everything.** Embedding the consultation, diagnoses, prescriptions and lab results lets one read return a whole visit instead of a six-table join, but there are no foreign keys, copied data can go stale on purpose, and cross-entity reporting is clumsier. My recommendation is PostgreSQL as the system of record with documents as an optional read model.
5. **Replication is not a backup, and CAP forces a choice.** Clinical writes should favour consistency; reports can tolerate replica lag. A promoted replica diverged from the old primary in my local test, which shows why split brain must be prevented.

## 4. How the work was checked

- Every SQL script was run against a real PostgreSQL 16.15 server; results, plans and timings in the repository are the actual output.
- Mistakes found along the way were fixed and recorded (for example unrealistic seed data, two wrong index comments, a test that referenced a patient that did not exist).
- Portfolio 4 includes negative and positive controls for its checker.
- Limitations are stated in each portfolio: single machine, synthetic data, no MongoDB server, no AWS account.

## 5. Repository and version control

The repository has one folder per portfolio, a README in each, and a commit history that records the order in which the work was done (listed in the root README). Commits were made in small steps by portfolio.

## 6. Honest limits

- Timings come from one small machine and synthetic data; they show relative improvement, not production performance.
- MongoDB behaviour (index acceptance, `explain()`, error text) is unverified on a real server.
- Portfolio 5 is a design with local demonstrations, not a cloud deployment.
- AI assistance was used heavily; see `ai-use-declaration.md`.

*(Length: about two and a half pages when exported. Add your own opening sentence about what you learned if you want the voice to be yours.)*
