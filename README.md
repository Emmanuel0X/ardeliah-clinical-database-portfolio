# Ardeliah Clinical System: Advanced Database Systems Portfolio

**Module:** MIT 8103 Advanced Database Systems
**Programme:** MSc Information Technology, Miva Open University
**Student:** Emmanuel (add matric number)
**Assessment:** Individual practical portfolio (40 marks)

## Table of contents

1. [Case study](#1-case-study)
2. [Organisation and users](#2-organisation-and-users)
3. [Key operations supported](#3-key-operations-supported)
4. [Assumptions](#4-assumptions)
5. [The five portfolios](#5-the-five-portfolios)
6. [Repository structure and navigation](#6-repository-structure-and-navigation)
7. [How to reproduce everything](#7-how-to-reproduce-everything)
8. [Evidence guide and honesty statement](#8-evidence-guide-and-honesty-statement)
9. [Commit history](#9-commit-history)
10. [Submission checklist](#10-submission-checklist)

## 1. Case study

**Case study name:** Ardeliah Clinical System
**System nature:** A comprehensive digital health platform designed to streamline outpatient care, physician schedules, clinical diagnoses, electronic prescriptions and laboratory test workflows.

## 2. Organisation and users

Ardeliah is an outpatient care organisation. Its platform serves four groups:

| User | What they do in the system |
|---|---|
| **Patients** | Register, book and view appointments, see their own prescriptions and results |
| **Doctors / physicians** | Keep schedules, record consultations, diagnoses and notes, issue prescriptions, request lab tests |
| **Receptionists / administrative staff** | Book, reschedule and cancel appointments, register patients |
| **Laboratory technicians** | Receive lab requests, record results, update the patient's diagnostic history |

## 3. Key operations supported

- Booking and managing patient appointments
- Storing clinical consultations, diagnoses and medical notes
- Generating and tracking electronic prescriptions and lab test requests
- Recording laboratory results and updating patient diagnostic history

## 4. Assumptions

- **Database system:** PostgreSQL 16 (all scripts were run on 16.15). I chose it for partial indexes, rich transaction isolation levels and `EXPLAIN (ANALYZE, BUFFERS)`. Portfolio 4 uses MongoDB syntax (a document database).
- **Data:** synthetic. Portfolio 1 has a hand-written sample; Portfolio 2 generates 20,003 patients and 185,304 appointments deterministically. No real patient data is used.
- **Scope:** one outpatient organisation (not a hospital with inpatient wards, billing or pharmacy stock).
- **Environment limits:** no MongoDB server and no AWS account were available when this was prepared. Portfolio 4 was run by an emulator and Portfolio 5 is a design with local demonstrations. This is stated again in each folder.

## 5. The five portfolios

| # | Folder | What it covers | Headline |
|---|---|---|---|
| 1 | [portfolio-1-database-design](portfolio-1-database-design/) | Case study analysis, ER diagram, relational schema, keys and constraints, 1NF to 3NF, `CREATE TABLE` scripts | 19 tables in 3NF; a partial unique index stops double booking |
| 2 | [portfolio-2-query-optimisation](portfolio-2-query-optimisation/) | 15 queries, results, `EXPLAIN (ANALYZE)` plans, indexing strategy, before/after analysis | Key lookups 8x to 56x faster with seven justified indexes; write cost measured |
| 3 | [portfolio-3-transactions-concurrency](portfolio-3-transactions-concurrency/) | COMMIT/ROLLBACK, isolation levels, dirty/non-repeatable/phantom reads, locking, MVCC, deadlock, crash recovery | Real two-session transcripts; `SERIALIZABLE` stops write skew |
| 4 | [portfolio-4-nosql](portfolio-4-nosql/) | MongoDB model for patients, appointments, consultations, prescriptions, lab results; scripts and queries; suitability | 9 collections; checked against PostgreSQL 16 of 16 (emulator, not a real MongoDB) |
| 5 | [portfolio-5-distributed-cloud](portfolio-5-distributed-cloud/) | Replication, sharding, CAP, availability, AWS RDS design, backup, security, architecture diagram | Local streaming replica and partition demo are real; no AWS deployment |
| Final | [final-documentation](final-documentation/) | Summary, technical reflection, references, AI use declaration | |

## 6. Repository structure and navigation

```
ardeliah-clinical-database-portfolio/
├── README.md                          you are here
├── .gitignore
├── portfolio-1-database-design/
│   ├── README.md, er-diagram-description.md, er-diagram.png
│   ├── relational-schema.md, normalisation-explanation.md
│   └── create-tables.sql, sample-data.sql
├── portfolio-2-query-optimisation/
│   ├── README.md, queries.sql, query-results.md
│   ├── execution-plans.md, indexing-strategy.sql, performance-analysis.md
│   └── seed-bulk-data.sql, drop-indexes.sql, run-benchmark.sh, evidence/
├── portfolio-3-transactions-concurrency/
│   ├── README.md, transaction-scripts.sql, isolation-levels-demo.sql
│   ├── concurrency-evidence.md, output-screenshots-description.md
│   └── run-concurrency-demos.py, durability-test.sh, evidence/
├── portfolio-4-nosql/
│   ├── README.md, nosql-model.md, implementation-scripts.md, suitability-analysis.md
│   ├── create-collections.js, insert-sample-documents.js, queries.js, write-examples.js
│   └── export-from-postgres.sql, import-data.sh, data/, verification/, evidence/
├── portfolio-5-distributed-cloud/
│   ├── README.md, distributed-database-discussion.md, replication-sharding-strategy.md
│   ├── cloud-deployment-evidence.md, architecture-diagram.mmd/.png
│   └── replication-lab/
└── final-documentation/
    ├── README.md, portfolio-summary.md, technical-reflection.md
    └── references.md, ai-use-declaration.md
```

Start with this README, then read each portfolio's own README, which lists its files and how to run them.

## 7. How to reproduce everything

```bash
createdb ardeliah
psql -v ON_ERROR_STOP=1 -d ardeliah -f portfolio-1-database-design/create-tables.sql
psql -v ON_ERROR_STOP=1 -d ardeliah -f portfolio-1-database-design/sample-data.sql
psql -v ON_ERROR_STOP=1 -d ardeliah -f portfolio-2-query-optimisation/seed-bulk-data.sql
psql -d ardeliah -f portfolio-2-query-optimisation/queries.sql
psql -a -d ardeliah -f portfolio-3-transactions-concurrency/transaction-scripts.sql
python3 portfolio-3-transactions-concurrency/run-concurrency-demos.py ardeliah
# Portfolio 4 needs MongoDB: see portfolio-4-nosql/README.md
# Portfolio 5 local demos: portfolio-5-distributed-cloud/replication-lab/
```

## 8. Evidence guide and honesty statement

| Portfolio | Evidence in the repository | What you must add |
|---|---|---|
| 1 | Scripts; schema listing taken from the live catalogue | Screenshots of the tables created and the ER diagram |
| 2 | Real `psql` output, plans, timings in `evidence/` | Screenshots of the benchmark tables and one before/after plan |
| 3 | Real transcripts and the crash-test output in `evidence/` | Screenshots of the two-session runs |
| 4 | **Emulator** output and a PostgreSQL cross-check | Run on a real MongoDB and screenshot it |
| 5 | Real local replication and partition output; design only for AWS | AWS screenshots if you deploy (plan in `cloud-deployment-evidence.md`) |

The text outputs are real. **No screenshot images were created, and nothing was invented** to look like a deployment or a run that did not happen. Where something could not be run, the relevant folder says so.

## 9. Commit history

The history below is the real one (dates as committed). Work was committed in small steps per portfolio. Some commits share a minute because several finished files were committed one after another. Keep committing as you review and change things, and do not rewrite history to change dates.

| Date | Commits | Work |
|---|---|---|
| 2026-11-06 | 14 | Portfolio 1 schema, ER diagram, normalisation, README; Portfolio 2 data, queries, plans, indexes, analysis |
| 2026-11-07 | 10 or more | Portfolio 3 transactions and concurrency; ER diagram image; Portfolio 4; Portfolio 5; final documentation and this README |

Run `git log --reverse --format='%h %ad %s' --date=short` for the full list.

## 10. Submission checklist

- [ ] Repository is **private**, and the reviewer has access
- [ ] Link to the repository is in `final-documentation/portfolio-summary.md` and in the LMS submission
- [ ] Every script runs from an empty database (see section 7)
- [ ] Each portfolio folder has its README and every file the brief lists
- [ ] Portfolio 1: case study, ER diagram, relational schema, keys, constraints, normalisation, `CREATE TABLE`
- [ ] Portfolio 2: 10 to 15 queries, results, plans for 3 to 4 queries, indexing, before/after analysis
- [ ] Portfolio 3: COMMIT/ROLLBACK, isolation levels, concurrency scenario, locking, evidence
- [ ] Portfolio 4: NoSQL model, scripts, queries, suitability, comparison table (and a real MongoDB run if possible)
- [ ] Portfolio 5: replication, sharding, CAP, availability, cloud design, architecture diagram
- [ ] Final documentation: summary (2 to 3 pages), reflection in my own words, references, AI declaration signed
- [ ] My own screenshots taken and referenced
- [ ] I can explain every design decision, query and result in a viva
