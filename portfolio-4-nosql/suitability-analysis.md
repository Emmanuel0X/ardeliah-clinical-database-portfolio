# Suitability Analysis: Is a Document Database Right for Ardeliah?

This page weighs MongoDB against the PostgreSQL design built in Portfolios 1 to 3. It uses what was actually built and checked. Where something was **not** measured (MongoDB speed, index use), it says so rather than guess.

## 1. Where a document model fits well

| Need in the clinic | Why documents help |
|---|---|
| Show a whole visit (notes, diagnoses, prescription, lab results) | One read returns one document. In SQL it takes six tables (Portfolio 2, Q4) |
| Record a lab result | One atomic update of one document (W1) instead of an insert plus an update in a transaction |
| Records that differ between patients | A walk-in patient has no email or blood group, and nothing is stored as an empty placeholder |
| Prescriptions that must show the drug as it was when prescribed | The snapshot is stored inside the prescription line |
| Scale-out later | A visit is a self-contained unit, so documents can be spread across servers by patient (see Portfolio 5) |

## 2. Where it fits badly

| Need | Problem |
|---|---|
| Referential integrity | MongoDB does not check that `patient_id` points at a real patient. PostgreSQL foreign keys do. A clinical system needs this, so the application must carry the rule |
| Rules that span collections | There is no equivalent of a multi-table `CHECK` or trigger in the same sense |
| Ad hoc analysis across many entities | Reporting that joins many collections is clumsier than SQL (`$lookup` works, as Q12 shows, but is more verbose) |
| Updating copied data | A copied name or description must be changed in every place it was copied. This is the price of the extended-reference and snapshot patterns |
| Document growth | An embedded array must stay bounded. That is why appointments and consultations are not embedded in the patient |
| Multi-document transactions | Available in modern MongoDB (on replica sets), but slower and less natural than in PostgreSQL. This design avoids needing them for the common cases |

## 3. Comparison with the relational design

| Aspect | PostgreSQL (Portfolios 1 to 3) | MongoDB (this portfolio) |
|---|---|---|
| Structures | 19 tables | 9 collections |
| Rows or documents for the 303-patient sample's visits | 9,759 rows in 6 tables | 2,161 documents |
| Schema enforcement | Strict, in the database | Optional validators (`$jsonSchema`); no foreign keys |
| Reading one whole visit | Six-table join | `findOne` |
| Cross-entity reports | Natural (`JOIN`) | Possible (`$lookup`), more verbose |
| Duplicate-booking guard | Partial unique index on `status <> 'CANCELLED'` | Unique partial index on a `slot_active` flag, which the application must keep in step with `status` |
| Concurrency | Rich: isolation levels, row locks, SSI (Portfolio 3) | Atomic single-document updates; transactions available on replica sets, not demonstrated here |
| Evolving the schema | `ALTER TABLE` and migration | Add a field, old documents stay valid |
| Integrity of history | Foreign keys always show the current catalogue | Snapshots keep what was true at the time |
| Evidence in this portfolio | Real execution in PostgreSQL 16, timed | Scripts run by an emulator and cross-checked; **not** run or timed on MongoDB |

## 4. Recommendation

For a clinic of this kind I would keep **PostgreSQL as the system of record**, because integrity, auditability and reporting matter most and the volume is modest. A document store is a sound choice for a **read-optimised view of visits**, for example the patient record screen, or a service that needs to scale out later. In practice that means using both: write to PostgreSQL, publish consultation documents to MongoDB for display. If the platform had to be one database only, the deciding factor would be whether the team can enforce referential integrity in the application code reliably. This is my judgement from the case study, not a measured result.

## 5. Honest limits of this analysis

- No MongoDB server was available, so **no MongoDB timing or `explain()` output exists** in this portfolio and no speed claims are made.
- The document counts and query results are verified against PostgreSQL through the emulator (16 of 16 checks; see `evidence/cross-check-postgres-vs-mongodb.md`), which proves the model holds the same information, not that it is faster.
- The sample is 303 patients, too small to say anything about behaviour at scale.
