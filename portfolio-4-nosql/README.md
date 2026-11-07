# Portfolio 4: NoSQL and Advanced Data Models

A MongoDB document model for the Ardeliah Clinical System, built from the PostgreSQL data of Portfolios 1 to 3.

> **Read this first.** No MongoDB server could be installed where this was prepared. The scripts are written for **mongosh and MongoDB 6.0+**, but they were **run by an in-memory emulator** (mingo and ajv) and cross-checked against PostgreSQL. All outputs in this folder are labelled as emulated. Please run the scripts on a real MongoDB (local or Atlas free tier) and take your own screenshots before submitting.

## What is here

| File | Purpose |
|---|---|
| `nosql-model.md` | Choice of document model, embed-or-reference decisions, patterns, mapping from SQL, validation, indexes, a real consultation document, diagram |
| `nosql-model-diagram.png` | Rendered diagram of the model |
| `implementation-scripts.md` | How to run the scripts, the 13 queries, write examples, emulated outputs |
| `suitability-analysis.md` | Strengths, weaknesses and a comparison table against PostgreSQL |
| `create-collections.js` | 9 collections, `$jsonSchema` validators, 8 indexes |
| `export-from-postgres.sql` and `data/*.ndjson` | Export of the 303-patient sample |
| `import-data.sh` | `mongoimport` of the exported data |
| `insert-sample-documents.js` | Hand-written examples of embedded and referenced data |
| `queries.js` | 13 `find` and aggregation queries |
| `write-examples.js` | Atomic updates, double-booking and validator tests |
| `verification/` | The emulator harness (`run-with-mingo.mjs`); run `npm install` there first |
| `evidence/` | Emulated run output and the PostgreSQL cross-check |

## Collections requested by the brief

| Brief asks for | Where it lives |
|---|---|
| Patients | `patients` |
| Appointments | `appointments` |
| Consultations | `consultations` |
| Prescriptions | embedded in `consultations.prescriptions[]` |
| Lab results | embedded in `consultations.lab_requests[].result` |

## Quick start

```bash
export MONGO_URI="mongodb://localhost:27017"
mongosh "$MONGO_URI" --file create-collections.js
./import-data.sh
mongosh "$MONGO_URI" --file insert-sample-documents.js
mongosh "$MONGO_URI" --file queries.js
mongosh "$MONGO_URI" --file write-examples.js
```

To re-run the emulator checks without MongoDB: `cd verification && npm install && node run-with-mingo.mjs` (PostgreSQL must be running for the cross-check).

## Assumptions

- MongoDB 6.0 or later; the export is a 303-patient sample.
- Foreign keys and the date-of-birth check have no MongoDB equivalent (see `nosql-model.md`, section 7).

## What to verify yourself

Run `getIndexes()` and `explain("executionStats")` on a real server, check that error codes 11000 and 121 appear in W4 to W6, and be ready to explain the embed-versus-reference choices in your own words.
