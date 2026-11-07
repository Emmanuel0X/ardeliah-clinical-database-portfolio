# Implementation: MongoDB scripts for the Ardeliah Clinical System

## IMPORTANT: how this was run

The scripts are written for **mongosh and a real MongoDB server**. No MongoDB server could be installed in the environment where this portfolio was prepared (the download host was blocked), so the scripts were **executed by an in-memory emulator** instead (`verification/run-with-mingo.mjs`, built on the open source libraries mingo and ajv). Every output pasted on this page comes from that emulator, not from MongoDB. It is real execution of the real script files, and the results were cross-checked against PostgreSQL (see section 6), but you should **run the scripts on your own MongoDB and take your own screenshots** for the submission. Section 7 lists what the emulator cannot show.

## 1. Files and run order

| Order | File | Purpose |
|---|---|---|
| 0 | `export-from-postgres.sql` | Turns the PostgreSQL data (303-patient sample) into `data/*.ndjson`. Already run; the output is committed |
| 1 | `create-collections.js` | Creates 9 collections with `$jsonSchema` validators and 8 indexes |
| 2 | `import-data.sh` | `mongoimport` of the exported documents (validators and indexes are active while loading) |
| 3 | `insert-sample-documents.js` | Hand-written example documents showing embedded and referenced data |
| 4 | `queries.js` | 13 read queries (`find` and aggregation pipelines) |
| 5 | `write-examples.js` | Atomic updates, double-booking test and validator tests |

```bash
# Local MongoDB 6.0+ with the MongoDB Database Tools, or an Atlas connection string
export MONGO_URI="mongodb://localhost:27017"
mongosh "$MONGO_URI" --file create-collections.js
./import-data.sh
mongosh "$MONGO_URI" --file insert-sample-documents.js
mongosh "$MONGO_URI" --file queries.js
mongosh "$MONGO_URI" --file write-examples.js
```

Re-running `create-collections.js` drops the collections and starts again. To reset only the hand-written examples, re-run `insert-sample-documents.js`.

Imported counts (the same number of documents the emulator loaded, and equal to the PostgreSQL row counts for the sample): patients 303, appointments 2,760, consultations 2,161, doctors 40, staff 14, users 7, icd_codes 12, medications 12, lab_tests 8.

## 2. Embedded versus referenced data, by example

`insert-sample-documents.js` writes two patients, two appointments and one consultation by hand. Read its header comment for the full list. In short:

- **Embedded:** a patient's `contact` and `medical_history[]`, a consultation's `diagnoses[]`, `prescriptions[].items[]` and `lab_requests[].result`.
- **Referenced:** `appointments.patient_id`, `appointments.doctor_id`, `consultations.appointment_id`.
- **Copied on purpose:** drug name and strength inside each prescription line, ICD description inside each diagnosis, patient and doctor names inside each appointment.

## 3. Queries

All 13 queries are in `queries.js` with comments. Q3 answers the same question as Portfolio 2 SQL Q4 (a six-table join) and Q11 the same as SQL Q6; section 6 lists the PostgreSQL checks.

| Query | Question | Technique |
|---|---|---|
| Q1 | Find a patient by name | `find`, projection, sort, limit |
| Q2 | A patient's appointments, newest first | `find` on one collection, no join |
| Q3 | A patient's clinical history | `find` with dotted paths into embedded arrays |
| Q4 | One whole visit | `findOne` returns the complete document |
| Q5 | A doctor's week sheet | `find` shaped to use the unique partial index |
| Q6 | Diagnoses per ICD code | `$unwind`, `$group`, conditional `$sum` |
| Q7 | Most prescribed medications | Two-level `$unwind` |
| Q8 | Abnormal lab results per test | `$unwind`, `$match` on `$exists`, `$round` |
| Q9 | Malaria patients since 1 October | Value inside an array, `distinct` |
| Q10 | Open lab requests | `$elemMatch`, `$unwind`, `$project` |
| Q11 | Appointment outcomes per month | `$dateToString`, conditional sums |
| Q12 | Completed appointments per specialisation | `$lookup` (the document "join") |
| Q13 | Average diagnoses per consultation | `$avg` of `$size` |

### Selected outputs (emulated run)

**Q4: one complete visit with one read** (compare the six tables this takes in SQL):

```text
{
  "_id": 1,
  "appointment_id": 1,
  "patient_id": 1,
  "doctor_id": 1,
  "consulted_at": ISODate("2026-10-20T08:10:00.000Z"),
  "clinical_notes": "Febrile, temp 38.6C, no neck stiffness. Chills and bodyache. Malaria parasite test ordered.",
  "diagnoses": [
    {
      "icd_code": "B50.9",
      "description": "Plasmodium falciparum malaria, unspecified",
      "severity": "MODERATE",
      "notes": "Confirmed by MP test"
    }
  ],
  "prescriptions": [
    {
      "prescription_id": 1,
      "issued_at": ISODate("2026-10-20T08:40:00.000Z"),
      "status": "ISSUED",
      "items": [
        {
          "medication": {
            "generic_name": "Artemether/Lumefantrine",
            "form": "tablet",
            "strength": "20/120 mg"
          },
          "dosage": "4 tablets",
          "frequency": "twice daily",
          "duration_days": 3
        },
        {
          "medication": {
            "generic_name": "Paracetamol",
            "form": "tablet",
            "strength": "500 mg"
          },
          "dosage": "2 tablets",
          "frequency": "every 6 hours as needed",
          "duration_days": 3
        }
      ]
    }
  ],
  "lab_requests": [
    {
      "lab_request_id": 1,
      "test": {
        "name": "Malaria parasite (MP) count",
        "unit": "parasites/uL"
      },
      "priority": "URGENT",
      "status": "COMPLETED",
      "requested_at": ISODate("2026-10-20T08:15:00.000Z"),
      "result": {
        "value": 2400,
        "abnormal": true,
        "comment": "P. falciparum trophozoites seen",
        "recorded_at": ISODate("2026-10-20T08:35:00.000Z"),
        "technician_id": 2
      }
    }
  ]
}
```

**Q6: diagnoses per ICD code:**

```text
[
  {
    "_id": "A01.0",
    "description": "Typhoid fever",
    "total": 233,
    "severe": 66
  },
  {
    "_id": "A09",
    "description": "Infectious gastroenteritis and colitis",
    "total": 226,
    "severe": 62
  },
  {
    "_id": "K29.7",
    "description": "Gastritis, unspecified",
    "total": 225,
    "severe": 59
  },
  {
    "_id": "N39.0",
    "description": "Urinary tract infection, site not specified",
    "total": 225,
    "severe": 53
  },
  {
    "_id": "I10",
    "description": "Essential (primary) hypertension",
    "total": 222,
    "severe": 67
  ... (output continues; full text in evidence/emulated-run-output.txt)
```

**Q8: abnormal lab results per test:**

```text
[
  {
    "abnormal": 39,
    "abnormal_pct": 36.1,
    "results": 108,
    "_id": "Fasting blood glucose"
  },
  {
    "abnormal": 39,
    "abnormal_pct": 33.3,
    "results": 117,
    "_id": "Serum creatinine"
  },
  {
    "abnormal": 38,
    "abnormal_pct": 30.9,
    "results": 123,
    "_id": "Urinalysis: leucocytes"
  },
  {
    "abnormal": 31,
    "abnormal_pct": 29.8,
    "results": 104,
    "_id": "Total cholesterol"
  },
  {
    "abnormal": 33,
    "abnormal_pct": 29.2,
    "results": 113,
    "_id": "Haemoglobin"
  ... (output continues; full text in evidence/emulated-run-output.txt)
```

**Q11: appointment outcomes per month:**

```text
[
  {
    "_id": "2026-05",
    "total": 94,
    "completed": 75,
    "cancelled": 8,
    "no_show": 11
  },
  {
    "_id": "2026-06",
    "total": 85,
    "completed": 64,
    "cancelled": 14,
    "no_show": 7
  },
  {
    "_id": "2026-07",
    "total": 75,
    "completed": 53,
    "cancelled": 10,
    "no_show": 12
  },
  {
    "_id": "2026-08",
    "total": 95,
    "completed": 81,
    "cancelled": 4,
    "no_show": 10
  },
  {
    "_id": "2026-09",
    "total": 75,
    "completed": 61,
    "cancelled": 7,
    "no_show": 7
  },
  {
    "_id": "2026-10",
    "total": 106,
    "completed": 80,
  ... (output continues; full text in evidence/emulated-run-output.txt)
```

**Q12: the `$lookup` join:**

```text
[
  {
    "_id": "General Practice",
    "completed": 15
  },
  {
    "_id": "Internal Medicine",
    "completed": 14
  },
  {
    "_id": "Dermatology",
    "completed": 12
  },
  {
    "_id": "Obstetrics and Gynaecology",
    "completed": 12
  },
  {
    "_id": "Cardiology",
    "completed": 10
  },
  {
    "_id": "Orthopaedics",
    "completed": 9
  },
  {
    "_id": "Ophthalmology",
    "completed": 6
  },
  {
  ... (output continues; full text in evidence/emulated-run-output.txt)
```

**Q13: statistics over an embedded array:**

```text
[
  {
    "avg_diagnoses": 1.198,
    "consultations": 2162
  }
]
```

Note: the emulated run had the two hand-written example consultations loaded, so Q13 counts 2,162 consultations (2,161 imported plus example 900001); the PostgreSQL cross-check in section 6 compares imported data only.

The remaining outputs (Q1 to Q3, Q5, Q7, Q9, Q10) are in `evidence/emulated-run-output.txt`.

## 4. Write examples and rules enforced by the database

`write-examples.js` demonstrates six behaviours:

| Example | What it shows |
|---|---|
| W1 | Recording a lab result is **one atomic update of one document**. In SQL it is an `INSERT` into `lab_result` plus an `UPDATE` of `lab_request` inside a transaction. `arrayFilters` selects the element, and requiring status `REQUESTED` makes a second attempt a harmless no-op (`modifiedCount: 0`) |
| W2 | `$push` adds a diagnosis to the embedded array |
| W3 | Cancelling sets `status` and `slot_active` together, which frees the slot so that it can be rebooked |
| W4 | A second live booking of the same doctor and time is **rejected** (duplicate key, code 11000) |
| W5 | A prescription with `duration_days: 0` is **rejected** by the validator (code 121) |
| W6 | A patient with gender `X` is **rejected** by the validator (code 121) |

Emulated output:

```text
{
  "matchedCount": 1,
  "modifiedCount": 1
}
{
  "lab_request_id": 900002,
  "test": {
    "name": "White blood cell count",
    "unit": "x10^9/L"
  },
  "priority": "URGENT",
  "status": "COMPLETED",
  "requested_at": ISODate("2027-03-10T08:16:00.000Z")
}

--- W1 again: the request is no longer REQUESTED, so nothing changes
{
  "matchedCount": 1,
  "modifiedCount": 0
}
```

```text
Rejected as expected. code=11000 (DuplicateKey)
E11000 duplicate key error collection: ardeliah_nosql.appointments index: uq_doctor_slot_active dup key: [[2],["2027-03-10T09:00:00.000Z"]]
```

```text
Rejected as expected. code=121 (DocumentValidationFailure)
Document failed validation
```

The emulator's error messages imitate MongoDB's documented error codes; the exact wording on a real server will differ slightly.

## 5. What I checked about the checks

The harness could have been agreeing with itself, so three controls were run on a scratch copy:

1. **Negative control for the cross-check:** I changed the malaria query to look for typhoid (`A01.0`) instead of malaria (`B50.9`). The harness reported that single check as `DIFFERENT` (15 of 16 matched) and exited with an error, so it can detect a wrong query.
2. **Positive control for W5 and W6:** I corrected only the deliberate error (`duration_days: 1`, gender `M`) and both inserts were then accepted. That proves each document was being rejected for the intended reason, not for an unrelated schema slip.
3. **Comparison against an independent system:** the expected values come from PostgreSQL, not from the MongoDB scripts.

## 6. Cross-check against PostgreSQL

`evidence/cross-check-postgres-vs-mongodb.md` runs 16 comparisons between the pipelines and equivalent SQL on the same 303 patients: collection counts, the embedded diagnosis, prescription-line and lab-request totals, and queries Q2, Q5 to Q13. **All 16 match.**

## 7. What this does not prove (please run these on a real MongoDB)

- Whether each **index definition is accepted** by your server version, and whether queries use it. Run `db.collection.find(...).explain("executionStats")` and look for `IXSCAN` instead of `COLLSCAN`.
- The **exact text of error messages** and whether the unique partial index behaves as described under concurrent inserts.
- **Performance.** Nothing here was timed on MongoDB, so no speed claims are made for the document model.
- Behaviour on a **sharded or replicated** deployment (see Portfolio 5).

Suggested screenshots to take yourself: the output of `./import-data.sh` ending with the document counts; `db.consultations.findOne({ _id: 1 })`; Q6 and Q12 results; the W4 and W5 rejections; and `db.appointments.getIndexes()`.

## 8. Tools used

| Tool | Used for |
|---|---|
| PostgreSQL 16.15 | Source of the exported data and the cross-check results |
| Node.js 22, mingo 7.2.7, ajv 8.20.0 | The in-memory verification harness |
| mongosh and MongoDB 6.0+ | Intended runtime for the scripts (not available when this was prepared) |
