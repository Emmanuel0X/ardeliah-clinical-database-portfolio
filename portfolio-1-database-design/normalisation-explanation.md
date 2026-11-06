# Normalisation: Ardeliah Clinical System

The goal was a schema in Third Normal Form (3NF), so that each fact is stored once and updates cannot leave the data contradicting itself. The easiest way to show this is to start from the kind of paper or spreadsheet record a clinic might keep, and normalise it step by step.

## Starting point: the unnormalised "visit sheet"

Imagine one row per visit in a spreadsheet:

| visit_id | patient_name | patient_phone | doctor_name | doctor_specialisation | visit_date | diagnoses | medications | lab_tests |
|---|---|---|---|---|---|---|---|---|
| 1 | Adaeze Okafor | 0803... | Aminu Ibrahim | General Practice | 2026-10-20 | B50.9 Malaria | Artemether/Lumefantrine 4 tabs BD x3; Paracetamol 2 tabs q6h x3 | Malaria parasite count |

Problems: several values are packed into single cells (diagnoses, medications, lab tests), the patient's phone number is repeated on every visit, and the doctor's specialisation is repeated on every visit by that doctor. Changing a phone number means editing many rows, and missing one creates a contradiction.

## First Normal Form (1NF): atomic values, no repeating groups

**Rule:** every column holds a single value, and there are no repeating groups.

**What changed:** the packed cells `diagnoses`, `medications` and `lab_tests` are repeating groups, so each moves into its own table with one row per item.

| Repeating group in the visit sheet | Table that replaces it |
|---|---|
| Several diagnoses per visit | `diagnosis` (one row per consultation and ICD code) |
| Several medications per visit | `prescription_item` (one row per drug on a prescription) |
| Several lab tests per visit | `lab_request` (one row per test ordered) |
| Several past conditions per patient | `patient_medical_history` |

Every table also has a primary key, and there are no multi-valued columns left. For example, `prescription_item` stores `dosage = '4 tablets'`, `frequency = 'twice daily'` and `duration_days = 3` as three separate columns rather than a sentence in one cell.

## Second Normal Form (2NF): no partial dependency on part of a composite key

**Rule:** the table is in 1NF, and every non-key column depends on the **whole** primary key, not just part of it. This only matters for tables with a composite key.

The only composite key in the schema is `prescription_item (prescription_id, medication_id)`.

- `dosage`, `frequency` and `duration_days` depend on **both** columns: they describe how this particular drug is prescribed on this particular prescription. They would be meaningless with only one of the two. So this part is fine.
- A tempting mistake would be to add `medication_name` and `strength` to `prescription_item`. Those depend only on `medication_id`, which is a partial dependency and a 2NF violation. It would also store "Paracetamol 500 mg" thousands of times. The design avoids this by keeping those facts in `medication` and referring to them by `medication_id`.

All other tables use a single-column surrogate key (for example `patient_id`), so a partial dependency is not possible there and they satisfy 2NF automatically.

## Third Normal Form (3NF): no transitive dependency

**Rule:** the table is in 2NF, and no non-key column depends on another non-key column. In other words, every non-key column depends "on the key, the whole key, and nothing but the key".

Three places where this rule shaped the design:

1. **Doctor and specialisation.** If `doctor` carried `specialisation_name` directly, we would have `doctor_id -> specialisation_id -> specialisation_name`, a transitive dependency. Renaming a specialisation would require updating every doctor row. The fix is the separate `specialisation` table; `doctor` keeps only `specialisation_id`.
2. **Diagnosis and ICD description.** `diagnosis` stores `icd_code` only. The text "Plasmodium falciparum malaria, unspecified" depends on the code, not on the diagnosis row, so it lives in `icd_code`.
3. **Lab request and test details.** `lab_request` stores `test_id`. The test name, unit and reference range depend on the test, so they sit in `lab_test_catalog`.

The same reasoning applies to `app_user.role_id` and `role`, and to `patient`, `doctor` and `staff`, which hold personal details that depend only on their own key.

## A deliberate decision worth explaining

`lab_result.abnormal_flag` could in principle be derived by comparing `result_value` with the reference range in `lab_test_catalog`, which would make it a derived column (a normalisation purist would drop it). I kept it on purpose. Reference ranges get revised over time, and a result recorded in 2026 should keep the flag that was true when the technician entered it. This is a conscious, documented exception for historical accuracy, not an oversight.

## Summary

| Normal form | Violation in the raw visit sheet | How the schema fixes it |
|---|---|---|
| 1NF | Packed cells for diagnoses, drugs and tests | Separate child tables with one row per item |
| 2NF | Drug name and strength would depend on only part of the `prescription_item` key | `medication` table, referenced by `medication_id` |
| 3NF | Specialisation name, ICD description and test details depend on non-key columns | `specialisation`, `icd_code` and `lab_test_catalog` tables |
