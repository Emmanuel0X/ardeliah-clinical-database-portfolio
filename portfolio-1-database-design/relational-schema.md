# Relational Schema: Ardeliah Clinical System

This listing was generated from the live PostgreSQL 16 catalogue after running `create-tables.sql`, so it matches the database exactly. `PK` is a primary key, `UK` a unique key, and `FK` shows the referenced column. A composite primary key shows `PK` on more than one column of the same table (see `prescription_item`).

Defaults and the partial unique index are in `create-tables.sql`. The CHECK constraints are listed at the end of this file.


## role

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `role_id` | SMALLINT | NOT NULL | PK |  |
| `role_name` | VARCHAR(30) | NOT NULL | UK |  |

## app_user

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `user_id` | INTEGER | NOT NULL | PK |  |
| `username` | VARCHAR(50) | NOT NULL | UK |  |
| `password_hash` | VARCHAR(255) | NOT NULL |  |  |
| `role_id` | SMALLINT | NOT NULL | FK | `role.role_id` |
| `is_active` | BOOLEAN | NOT NULL |  |  |
| `created_at` | TIMESTAMPTZ | NOT NULL |  |  |

## patient

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `patient_id` | INTEGER | NOT NULL | PK |  |
| `user_id` | INTEGER | yes | UK, FK | `app_user.user_id` |
| `first_name` | VARCHAR(50) | NOT NULL |  |  |
| `last_name` | VARCHAR(50) | NOT NULL |  |  |
| `date_of_birth` | DATE | NOT NULL |  |  |
| `gender` | CHAR(1) | NOT NULL |  |  |
| `phone` | VARCHAR(20) | yes |  |  |
| `email` | VARCHAR(100) | yes | UK |  |
| `address` | VARCHAR(200) | yes |  |  |
| `blood_group` | VARCHAR(3) | yes |  |  |
| `registered_on` | DATE | NOT NULL |  |  |

## patient_medical_history

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `history_id` | INTEGER | NOT NULL | PK |  |
| `patient_id` | INTEGER | NOT NULL | FK | `patient.patient_id` |
| `condition_name` | VARCHAR(100) | NOT NULL |  |  |
| `noted_on` | DATE | NOT NULL |  |  |
| `notes` | TEXT | yes |  |  |

## specialisation

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `specialisation_id` | SMALLINT | NOT NULL | PK |  |
| `specialisation_name` | VARCHAR(80) | NOT NULL | UK |  |

## doctor

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `doctor_id` | INTEGER | NOT NULL | PK |  |
| `user_id` | INTEGER | yes | UK, FK | `app_user.user_id` |
| `first_name` | VARCHAR(50) | NOT NULL |  |  |
| `last_name` | VARCHAR(50) | NOT NULL |  |  |
| `specialisation_id` | SMALLINT | NOT NULL | FK | `specialisation.specialisation_id` |
| `licence_no` | VARCHAR(30) | NOT NULL | UK |  |
| `phone` | VARCHAR(20) | yes |  |  |

## doctor_schedule

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `schedule_id` | INTEGER | NOT NULL | PK |  |
| `doctor_id` | INTEGER | NOT NULL | UK, FK | `doctor.doctor_id` |
| `day_of_week` | SMALLINT | NOT NULL | UK |  |
| `start_time` | TIME | NOT NULL | UK |  |
| `end_time` | TIME | NOT NULL |  |  |

## staff

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `staff_id` | INTEGER | NOT NULL | PK |  |
| `user_id` | INTEGER | yes | UK, FK | `app_user.user_id` |
| `first_name` | VARCHAR(50) | NOT NULL |  |  |
| `last_name` | VARCHAR(50) | NOT NULL |  |  |
| `staff_type` | VARCHAR(20) | NOT NULL |  |  |
| `phone` | VARCHAR(20) | yes |  |  |

## appointment

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `appointment_id` | INTEGER | NOT NULL | PK |  |
| `patient_id` | INTEGER | NOT NULL | FK | `patient.patient_id` |
| `doctor_id` | INTEGER | NOT NULL | FK | `doctor.doctor_id` |
| `booked_by_staff_id` | INTEGER | yes | FK | `staff.staff_id` |
| `appointment_date` | DATE | NOT NULL |  |  |
| `start_time` | TIME | NOT NULL |  |  |
| `status` | VARCHAR(15) | NOT NULL |  |  |
| `reason` | VARCHAR(200) | yes |  |  |
| `created_at` | TIMESTAMPTZ | NOT NULL |  |  |

## consultation

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `consultation_id` | INTEGER | NOT NULL | PK |  |
| `appointment_id` | INTEGER | NOT NULL | UK, FK | `appointment.appointment_id` |
| `clinical_notes` | TEXT | yes |  |  |
| `consulted_at` | TIMESTAMPTZ | NOT NULL |  |  |

## icd_code

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `icd_code` | VARCHAR(10) | NOT NULL | PK |  |
| `description` | VARCHAR(200) | NOT NULL |  |  |

## diagnosis

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `diagnosis_id` | INTEGER | NOT NULL | PK |  |
| `consultation_id` | INTEGER | NOT NULL | UK, FK | `consultation.consultation_id` |
| `icd_code` | VARCHAR(10) | NOT NULL | UK, FK | `icd_code.icd_code` |
| `severity` | VARCHAR(10) | NOT NULL |  |  |
| `notes` | TEXT | yes |  |  |

## medication

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `medication_id` | INTEGER | NOT NULL | PK |  |
| `generic_name` | VARCHAR(100) | NOT NULL | UK |  |
| `form` | VARCHAR(30) | NOT NULL | UK |  |
| `strength` | VARCHAR(30) | NOT NULL | UK |  |

## prescription

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `prescription_id` | INTEGER | NOT NULL | PK |  |
| `consultation_id` | INTEGER | NOT NULL | FK | `consultation.consultation_id` |
| `issued_at` | TIMESTAMPTZ | NOT NULL |  |  |
| `status` | VARCHAR(12) | NOT NULL |  |  |

## prescription_item

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `prescription_id` | INTEGER | NOT NULL | PK, FK | `prescription.prescription_id` |
| `medication_id` | INTEGER | NOT NULL | PK, FK | `medication.medication_id` |
| `dosage` | VARCHAR(50) | NOT NULL |  |  |
| `frequency` | VARCHAR(50) | NOT NULL |  |  |
| `duration_days` | SMALLINT | NOT NULL |  |  |

## lab_test_catalog

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `test_id` | INTEGER | NOT NULL | PK |  |
| `test_name` | VARCHAR(100) | NOT NULL | UK |  |
| `unit` | VARCHAR(20) | yes |  |  |
| `ref_range_low` | NUMERIC(10,2) | yes |  |  |
| `ref_range_high` | NUMERIC(10,2) | yes |  |  |

## lab_request

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `lab_request_id` | INTEGER | NOT NULL | PK |  |
| `consultation_id` | INTEGER | NOT NULL | FK | `consultation.consultation_id` |
| `test_id` | INTEGER | NOT NULL | FK | `lab_test_catalog.test_id` |
| `requested_at` | TIMESTAMPTZ | NOT NULL |  |  |
| `priority` | VARCHAR(8) | NOT NULL |  |  |
| `status` | VARCHAR(12) | NOT NULL |  |  |

## lab_result

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `lab_result_id` | INTEGER | NOT NULL | PK |  |
| `lab_request_id` | INTEGER | NOT NULL | UK, FK | `lab_request.lab_request_id` |
| `technician_id` | INTEGER | NOT NULL | FK | `staff.staff_id` |
| `result_value` | NUMERIC(12,3) | yes |  |  |
| `result_comment` | TEXT | yes |  |  |
| `abnormal_flag` | BOOLEAN | NOT NULL |  |  |
| `recorded_at` | TIMESTAMPTZ | NOT NULL |  |  |

## audit_log

| Column | Type | Null? | Key | References |
|---|---|---|---|---|
| `log_id` | BIGINT | NOT NULL | PK |  |
| `table_name` | VARCHAR(50) | NOT NULL |  |  |
| `action` | VARCHAR(10) | NOT NULL |  |  |
| `record_id` | INTEGER | NOT NULL |  |  |
| `performed_by` | INTEGER | yes | FK | `app_user.user_id` |
| `performed_at` | TIMESTAMPTZ | NOT NULL |  |  |
| `details` | TEXT | yes |  |  |

## CHECK constraints

| Table | Constraint | Rule |
|---|---|---|
| `appointment` | `appointment_status_check` | `CHECK (((status)::text = ANY ((ARRAY['SCHEDULED'::character varying, 'CHECKED_IN'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying, 'NO_SHOW'::character varying])::text[])))` |
| `audit_log` | `audit_log_action_check` | `CHECK (((action)::text = ANY ((ARRAY['INSERT'::character varying, 'UPDATE'::character varying, 'DELETE'::character varying])::text[])))` |
| `diagnosis` | `diagnosis_severity_check` | `CHECK (((severity)::text = ANY ((ARRAY['MILD'::character varying, 'MODERATE'::character varying, 'SEVERE'::character varying])::text[])))` |
| `doctor_schedule` | `chk_schedule_times` | `CHECK ((end_time > start_time))` |
| `doctor_schedule` | `doctor_schedule_day_of_week_check` | `CHECK (((day_of_week >= 1) AND (day_of_week <= 7)))` |
| `lab_request` | `lab_request_priority_check` | `CHECK (((priority)::text = ANY ((ARRAY['ROUTINE'::character varying, 'URGENT'::character varying])::text[])))` |
| `lab_request` | `lab_request_status_check` | `CHECK (((status)::text = ANY ((ARRAY['REQUESTED'::character varying, 'COLLECTED'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::text[])))` |
| `lab_test_catalog` | `chk_ref_range` | `CHECK (((ref_range_high IS NULL) OR (ref_range_low IS NULL) OR (ref_range_high >= ref_range_low)))` |
| `patient` | `patient_blood_group_check` | `CHECK (((blood_group)::text = ANY ((ARRAY['A+'::character varying, 'A-'::character varying, 'B+'::character varying, 'B-'::character varying, 'AB+'::character varying, 'AB-'::character varying, 'O+'::character varying, 'O-'::character varying])::text[])))` |
| `patient` | `patient_date_of_birth_check` | `CHECK ((date_of_birth <= CURRENT_DATE))` |
| `patient` | `patient_gender_check` | `CHECK ((gender = ANY (ARRAY['M'::bpchar, 'F'::bpchar, 'O'::bpchar])))` |
| `prescription` | `prescription_status_check` | `CHECK (((status)::text = ANY ((ARRAY['ISSUED'::character varying, 'DISPENSED'::character varying, 'CANCELLED'::character varying, 'EXPIRED'::character varying])::text[])))` |
| `prescription_item` | `prescription_item_duration_days_check` | `CHECK ((duration_days > 0))` |
| `staff` | `staff_staff_type_check` | `CHECK (((staff_type)::text = ANY ((ARRAY['RECEPTIONIST'::character varying, 'LAB_TECHNICIAN'::character varying])::text[])))` |

## Other constraints worth knowing

- `uq_doctor_slot_active` is a **partial unique index** on `appointment (doctor_id, appointment_date, start_time) WHERE status <> 'CANCELLED'`. It stops a doctor being double booked while letting a cancelled slot be reused.
- `consultation.appointment_id` is `UNIQUE`, which turns the appointment-to-consultation link into one-to-one.
- `lab_result.lab_request_id` is `UNIQUE`, so each lab request has at most one result.
- `diagnosis` has `UNIQUE (consultation_id, icd_code)` so the same code cannot be recorded twice for one visit.
- `ON DELETE CASCADE` is used only where a child row has no meaning without its parent (medical history, schedules, diagnoses, prescription items, lab requests and results). Appointments, doctors and patients are never cascaded away, because clinical records should not disappear by accident.
