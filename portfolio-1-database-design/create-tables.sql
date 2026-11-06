-- =====================================================================
-- Ardeliah Clinical System: relational schema (PostgreSQL 16)
-- Portfolio 1: Database Design and Modelling
--
-- Run with:   createdb ardeliah
--             psql -d ardeliah -f create-tables.sql
-- The script is re-runnable: it drops and recreates the schema.
--
-- Design decisions (also explained in normalisation-explanation.md):
--   * Every table is in 3NF. Repeating groups (diagnoses, prescription
--     lines, lab requests) live in their own tables.
--   * Surrogate integer keys (IDENTITY) for entities; natural keys
--     (ICD code) where a stable external standard exists.
--   * Business rules are enforced in the database with NOT NULL, UNIQUE,
--     CHECK and FOREIGN KEY constraints, not only in application code.
-- =====================================================================

DROP SCHEMA IF EXISTS ardeliah CASCADE;
CREATE SCHEMA ardeliah;
SET search_path TO ardeliah;

-- ---------------------------------------------------------------------
-- 1. Access control: roles and user accounts
-- ---------------------------------------------------------------------
CREATE TABLE role (
    role_id     SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name   VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE app_user (
    user_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username       VARCHAR(50)  NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,          -- never store plain text
    role_id        SMALLINT     NOT NULL REFERENCES role(role_id),
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. People: patients, doctors, staff
-- ---------------------------------------------------------------------
CREATE TABLE patient (
    patient_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        INT UNIQUE REFERENCES app_user(user_id),  -- optional portal login
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    date_of_birth  DATE         NOT NULL CHECK (date_of_birth <= CURRENT_DATE),
    gender         CHAR(1)      NOT NULL CHECK (gender IN ('M','F','O')),
    phone          VARCHAR(20),
    email          VARCHAR(100) UNIQUE,
    address        VARCHAR(200),
    blood_group    VARCHAR(3)   CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    registered_on  DATE         NOT NULL DEFAULT CURRENT_DATE
);

-- Medical history is a repeating group, so it gets its own table (1NF).
CREATE TABLE patient_medical_history (
    history_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      INT          NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    condition_name  VARCHAR(100) NOT NULL,
    noted_on        DATE         NOT NULL DEFAULT CURRENT_DATE,
    notes           TEXT
);

-- Specialisation is split out of doctor to remove a transitive
-- dependency (doctor_id -> specialisation_id -> specialisation_name): 3NF.
CREATE TABLE specialisation (
    specialisation_id  SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    specialisation_name VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE doctor (
    doctor_id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id            INT UNIQUE REFERENCES app_user(user_id),
    first_name         VARCHAR(50) NOT NULL,
    last_name          VARCHAR(50) NOT NULL,
    specialisation_id  SMALLINT    NOT NULL REFERENCES specialisation(specialisation_id),
    licence_no         VARCHAR(30) NOT NULL UNIQUE,
    phone              VARCHAR(20)
);

-- Weekly working hours. day_of_week follows ISO: 1 = Monday ... 7 = Sunday.
CREATE TABLE doctor_schedule (
    schedule_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id    INT      NOT NULL REFERENCES doctor(doctor_id) ON DELETE CASCADE,
    day_of_week  SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_time   TIME     NOT NULL,
    end_time     TIME     NOT NULL,
    CONSTRAINT chk_schedule_times CHECK (end_time > start_time),
    CONSTRAINT uq_schedule UNIQUE (doctor_id, day_of_week, start_time)
);

-- Receptionists and laboratory technicians share one table; staff_type
-- distinguishes them. Both only need the same attributes.
CREATE TABLE staff (
    staff_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     INT UNIQUE REFERENCES app_user(user_id),
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    staff_type  VARCHAR(20) NOT NULL CHECK (staff_type IN ('RECEPTIONIST','LAB_TECHNICIAN')),
    phone       VARCHAR(20)
);

-- ---------------------------------------------------------------------
-- 3. Appointments
-- ---------------------------------------------------------------------
CREATE TABLE appointment (
    appointment_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id        INT  NOT NULL REFERENCES patient(patient_id),
    doctor_id         INT  NOT NULL REFERENCES doctor(doctor_id),
    booked_by_staff_id INT REFERENCES staff(staff_id),   -- NULL = self-booked via portal
    appointment_date  DATE NOT NULL,
    start_time        TIME NOT NULL,
    status            VARCHAR(15) NOT NULL DEFAULT 'SCHEDULED'
                      CHECK (status IN ('SCHEDULED','CHECKED_IN','COMPLETED','CANCELLED','NO_SHOW')),
    reason            VARCHAR(200),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A doctor cannot have two live appointments in the same slot. The partial
-- index lets a cancelled slot be rebooked. This is the database-level guard
-- used in Portfolio 3 (double booking).
CREATE UNIQUE INDEX uq_doctor_slot_active
    ON appointment (doctor_id, appointment_date, start_time)
    WHERE status <> 'CANCELLED';

-- ---------------------------------------------------------------------
-- 4. Clinical data: consultation, diagnosis, ICD reference
-- ---------------------------------------------------------------------
CREATE TABLE consultation (
    consultation_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id   INT NOT NULL UNIQUE REFERENCES appointment(appointment_id), -- 1:1
    clinical_notes   TEXT,
    consulted_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE icd_code (
    icd_code     VARCHAR(10) PRIMARY KEY,           -- natural key, e.g. 'B50.9'
    description  VARCHAR(200) NOT NULL
);

-- A consultation can have many diagnoses; a diagnosis row links one
-- consultation to one ICD code.
CREATE TABLE diagnosis (
    diagnosis_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    consultation_id  INT NOT NULL REFERENCES consultation(consultation_id) ON DELETE CASCADE,
    icd_code         VARCHAR(10) NOT NULL REFERENCES icd_code(icd_code),
    severity         VARCHAR(10) NOT NULL DEFAULT 'MILD'
                     CHECK (severity IN ('MILD','MODERATE','SEVERE')),
    notes            TEXT,
    CONSTRAINT uq_diagnosis UNIQUE (consultation_id, icd_code)
);

-- ---------------------------------------------------------------------
-- 5. Electronic prescriptions
-- ---------------------------------------------------------------------
CREATE TABLE medication (
    medication_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    generic_name   VARCHAR(100) NOT NULL,
    form           VARCHAR(30)  NOT NULL,           -- tablet, syrup, injection ...
    strength       VARCHAR(30)  NOT NULL,           -- e.g. '500 mg'
    CONSTRAINT uq_medication UNIQUE (generic_name, form, strength)
);

CREATE TABLE prescription (
    prescription_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    consultation_id  INT NOT NULL REFERENCES consultation(consultation_id) ON DELETE CASCADE,
    issued_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    status           VARCHAR(12) NOT NULL DEFAULT 'ISSUED'
                     CHECK (status IN ('ISSUED','DISPENSED','CANCELLED','EXPIRED'))
);

-- Composite primary key (prescription_id, medication_id): one line per
-- medication on a prescription. Dosage, frequency and duration depend on
-- the WHOLE key, which satisfies 2NF. The medication name is not repeated
-- here because it depends only on medication_id.
CREATE TABLE prescription_item (
    prescription_id  INT NOT NULL REFERENCES prescription(prescription_id) ON DELETE CASCADE,
    medication_id    INT NOT NULL REFERENCES medication(medication_id),
    dosage           VARCHAR(50) NOT NULL,          -- e.g. '1 tablet'
    frequency        VARCHAR(50) NOT NULL,          -- e.g. 'twice daily'
    duration_days    SMALLINT    NOT NULL CHECK (duration_days > 0),
    PRIMARY KEY (prescription_id, medication_id)
);

-- ---------------------------------------------------------------------
-- 6. Laboratory workflow
-- ---------------------------------------------------------------------
CREATE TABLE lab_test_catalog (
    test_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_name      VARCHAR(100) NOT NULL UNIQUE,
    unit           VARCHAR(20),
    ref_range_low  NUMERIC(10,2),
    ref_range_high NUMERIC(10,2),
    CONSTRAINT chk_ref_range CHECK (ref_range_high IS NULL OR ref_range_low IS NULL
                                    OR ref_range_high >= ref_range_low)
);

CREATE TABLE lab_request (
    lab_request_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    consultation_id  INT NOT NULL REFERENCES consultation(consultation_id) ON DELETE CASCADE,
    test_id          INT NOT NULL REFERENCES lab_test_catalog(test_id),
    requested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    priority         VARCHAR(8)  NOT NULL DEFAULT 'ROUTINE' CHECK (priority IN ('ROUTINE','URGENT')),
    status           VARCHAR(12) NOT NULL DEFAULT 'REQUESTED'
                     CHECK (status IN ('REQUESTED','COLLECTED','COMPLETED','CANCELLED'))
);

-- One result per request (1:1). abnormal_flag is stored rather than
-- derived so the value recorded at the time is preserved even if the
-- reference range in the catalogue is later revised.
CREATE TABLE lab_result (
    lab_result_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lab_request_id  INT NOT NULL UNIQUE REFERENCES lab_request(lab_request_id) ON DELETE CASCADE,
    technician_id   INT NOT NULL REFERENCES staff(staff_id),
    result_value    NUMERIC(12,3),
    result_comment  TEXT,
    abnormal_flag   BOOLEAN NOT NULL DEFAULT FALSE,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 7. Audit trail (used by the transaction examples in Portfolio 3)
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    log_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name    VARCHAR(50) NOT NULL,
    action        VARCHAR(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    record_id     INT         NOT NULL,
    performed_by  INT REFERENCES app_user(user_id),
    performed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    details       TEXT
);
