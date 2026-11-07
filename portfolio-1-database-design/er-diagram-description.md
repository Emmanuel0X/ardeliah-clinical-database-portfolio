# ER Diagram: Ardeliah Clinical System

The diagram below is written in Mermaid, so GitHub renders it automatically. To get an image for the LMS submission, paste the code block into <https://mermaid.live> and export as PNG.

```mermaid
erDiagram
    ROLE ||--o{ APP_USER : "assigned to"
    APP_USER |o--o| PATIENT : "portal login"
    APP_USER |o--o| DOCTOR : "login"
    APP_USER |o--o| STAFF : "login"
    SPECIALISATION ||--o{ DOCTOR : "classifies"
    DOCTOR ||--o{ DOCTOR_SCHEDULE : "works"
    PATIENT ||--o{ PATIENT_MEDICAL_HISTORY : "has"
    PATIENT ||--o{ APPOINTMENT : "books"
    DOCTOR ||--o{ APPOINTMENT : "attends"
    STAFF |o--o{ APPOINTMENT : "books on behalf"
    APPOINTMENT ||--o| CONSULTATION : "results in"
    CONSULTATION ||--o{ DIAGNOSIS : "records"
    ICD_CODE ||--o{ DIAGNOSIS : "classifies"
    CONSULTATION ||--o{ PRESCRIPTION : "issues"
    PRESCRIPTION ||--|{ PRESCRIPTION_ITEM : "contains"
    MEDICATION ||--o{ PRESCRIPTION_ITEM : "prescribed as"
    CONSULTATION ||--o{ LAB_REQUEST : "orders"
    LAB_TEST_CATALOG ||--o{ LAB_REQUEST : "defines"
    LAB_REQUEST ||--o| LAB_RESULT : "produces"
    STAFF ||--o{ LAB_RESULT : "records (technician)"
    APP_USER |o--o{ AUDIT_LOG : "performed"

    ROLE {
        smallint role_id PK
        varchar role_name UK
    }
    APP_USER {
        int user_id PK
        varchar username UK
        varchar password_hash
        smallint role_id FK
        boolean is_active
    }
    PATIENT {
        int patient_id PK
        int user_id FK
        varchar first_name
        varchar last_name
        date date_of_birth
        char gender
        varchar email UK
        varchar blood_group
    }
    PATIENT_MEDICAL_HISTORY {
        int history_id PK
        int patient_id FK
        varchar condition_name
        date noted_on
    }
    SPECIALISATION {
        smallint specialisation_id PK
        varchar specialisation_name UK
    }
    DOCTOR {
        int doctor_id PK
        int user_id FK
        smallint specialisation_id FK
        varchar licence_no UK
        varchar first_name
        varchar last_name
    }
    DOCTOR_SCHEDULE {
        int schedule_id PK
        int doctor_id FK
        smallint day_of_week
        time start_time
        time end_time
    }
    STAFF {
        int staff_id PK
        int user_id FK
        varchar staff_type
        varchar first_name
        varchar last_name
    }
    APPOINTMENT {
        int appointment_id PK
        int patient_id FK
        int doctor_id FK
        int booked_by_staff_id FK
        date appointment_date
        time start_time
        varchar status
    }
    CONSULTATION {
        int consultation_id PK
        int appointment_id FK
        text clinical_notes
        timestamptz consulted_at
    }
    ICD_CODE {
        varchar icd_code PK
        varchar description
    }
    DIAGNOSIS {
        int diagnosis_id PK
        int consultation_id FK
        varchar icd_code FK
        varchar severity
    }
    MEDICATION {
        int medication_id PK
        varchar generic_name
        varchar form
        varchar strength
    }
    PRESCRIPTION {
        int prescription_id PK
        int consultation_id FK
        timestamptz issued_at
        varchar status
    }
    PRESCRIPTION_ITEM {
        int prescription_id PK, FK
        int medication_id PK, FK
        varchar dosage
        varchar frequency
        smallint duration_days
    }
    LAB_TEST_CATALOG {
        int test_id PK
        varchar test_name UK
        varchar unit
        numeric ref_range_low
        numeric ref_range_high
    }
    LAB_REQUEST {
        int lab_request_id PK
        int consultation_id FK
        int test_id FK
        varchar priority
        varchar status
    }
    LAB_RESULT {
        int lab_result_id PK
        int lab_request_id FK
        int technician_id FK
        numeric result_value
        boolean abnormal_flag
    }
    AUDIT_LOG {
        bigint log_id PK
        int performed_by FK
        varchar table_name
        varchar action
    }
```

## Entities and what they hold

| Entity | Purpose |
|---|---|
| ROLE, APP_USER | Authentication and role-based access (patient, doctor, receptionist, lab technician, admin) |
| PATIENT, PATIENT_MEDICAL_HISTORY | Demographics, plus a one-to-many list of past conditions |
| SPECIALISATION, DOCTOR, DOCTOR_SCHEDULE | Doctor profiles and weekly working hours |
| STAFF | Receptionists and lab technicians (separated by `staff_type`) |
| APPOINTMENT | A patient booking a doctor for a date and time |
| CONSULTATION | What happened at a completed appointment, including clinical notes |
| ICD_CODE, DIAGNOSIS | Standard diagnosis codes and the diagnoses recorded per consultation |
| MEDICATION, PRESCRIPTION, PRESCRIPTION_ITEM | Electronic prescriptions with one line per drug |
| LAB_TEST_CATALOG, LAB_REQUEST, LAB_RESULT | Tests that can be ordered, requests made by doctors, results entered by technicians |
| AUDIT_LOG | Who changed what, used in the transaction exercises |

## Cardinality reasoning

- **Patient to Appointment is 1:N.** One patient can have many appointments over time, but each appointment is for exactly one patient.
- **Doctor to Appointment is 1:N**, with the extra rule that a doctor cannot hold two live appointments in the same slot. This is enforced by the partial unique index `uq_doctor_slot_active`.
- **Appointment to Consultation is 1:0..1.** An appointment only produces a consultation if the patient is actually seen, so cancelled and no-show appointments have none. The `UNIQUE` on `consultation.appointment_id` enforces the "at most one".
- **Consultation to Diagnosis, Prescription and Lab Request is 1:N** in each case. A doctor can record several diagnoses, issue several prescriptions and order several tests in one visit.
- **Prescription to Medication is M:N**, because a prescription can list several drugs and a drug appears on many prescriptions. It is resolved through the associative table `PRESCRIPTION_ITEM`, whose composite key is (`prescription_id`, `medication_id`).
- **Lab Request to Lab Result is 1:0..1.** A request has no result until the technician records one.
- **User accounts are optional for patients.** A walk-in patient can be registered by reception with no portal login, which is why `patient.user_id` is nullable.

## Assumptions

- The clinic is outpatient only, so there are no ward admissions or bed management.
- Billing and payments are outside the scope of this case study. The transaction exercises in Portfolio 3 use appointment booking with an audit entry instead.
- Each appointment is a fixed-length slot identified by its start time.

A pre-rendered image of the diagram above is in `er-diagram.png` (generated from this Mermaid source with the Mermaid CLI), for viewers that do not draw Mermaid.
