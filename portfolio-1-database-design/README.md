# Portfolio 1: Database Design and Modelling

**Case study:** Ardeliah Clinical System, an outpatient clinic platform covering appointments, consultations, diagnoses, electronic prescriptions and laboratory workflows.
**Users:** patients, doctors, receptionists/administrative staff, laboratory technicians.
**DBMS:** PostgreSQL 16 (all scripts in this portfolio were run on PostgreSQL 16.15).

## Files

| File | What it contains |
|---|---|
| `er-diagram-description.md` | Mermaid ER diagram, entity list, cardinality reasoning and assumptions |
| `relational-schema.md` | Every table, column, type, key and CHECK constraint, generated from the live database catalogue |
| `normalisation-explanation.md` | Step-by-step 1NF, 2NF and 3NF reasoning using examples from this schema |
| `create-tables.sql` | Executable DDL for all 19 tables, with comments explaining design choices |
| `sample-data.sql` | Reference data plus one complete clinical workflow, so every table has real rows |

## How to run it

```bash
createdb ardeliah
psql -d ardeliah -f create-tables.sql      # creates schema "ardeliah" with 19 tables
psql -d ardeliah -f sample-data.sql        # loads reference data and a worked example
```

`create-tables.sql` drops and recreates the `ardeliah` schema, so it can be re-run safely.

## How it was tested

1. Ran `create-tables.sql` on a fresh database with `ON_ERROR_STOP=1`. It completed without errors and created 19 tables.
2. Ran `sample-data.sql` the same way. All inserts succeeded, which also confirms the foreign keys and CHECK constraints accept valid data.
3. Confirmed row counts after loading (3 patients, 2 doctors, 3 appointments, 2 prescription items, 1 lab result).
4. Constraint behaviour is exercised further in Portfolio 3 (for example, the double-booking guard).

## Key design decisions

- **3NF throughout**, with one documented exception (`lab_result.abnormal_flag`, kept for historical accuracy). See `normalisation-explanation.md`.
- **Business rules live in the database.** Statuses, gender, blood group, severity and positive durations are CHECK constraints rather than only application checks.
- **Double booking is prevented by a partial unique index**, which still allows a cancelled slot to be rebooked.
- **Patients can exist without a login**, because walk-in patients are registered by reception.
- **Billing is out of scope** for this case study.

## Evidence

Screenshots to take for the LMS submission, with the command that produces each:

1. `psql -f create-tables.sql` finishing with 19 `CREATE TABLE` lines and no errors.
2. `\dt ardeliah.*` showing all 19 tables.
3. `\d ardeliah.appointment` showing keys, CHECK constraints and the partial unique index.
4. The rendered Mermaid ER diagram from `er-diagram-description.md`.
