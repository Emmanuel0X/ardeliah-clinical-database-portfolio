-- =====================================================================
-- Ardeliah Clinical System: indexing strategy
-- Portfolio 2: Query Processing and Optimisation
--
-- Run AFTER seed-bulk-data.sql:   psql -d ardeliah -f indexing-strategy.sql
-- To return to the baseline:      psql -d ardeliah -f drop-indexes.sql
--
-- Method: the baseline plans in evidence/plans-before.txt showed
-- sequential scans that read a whole table and discard nearly every row.
-- Each index below targets one of those scans. PostgreSQL does not index
-- foreign-key columns automatically, so FK columns used in joins need an
-- explicit index.
-- =====================================================================
SET search_path TO ardeliah;

-- ---------------------------------------------------------------------
-- Indexes that fix a measured problem (see performance-analysis.md)
-- ---------------------------------------------------------------------

-- K1 / Q1: reception looks patients up by name. A two-column B-tree on
-- (last_name, first_name) serves "last name only" and "last + first name"
-- searches. last_name leads because that is how reception usually starts
-- a search, and a B-tree can only be used from its leading column. (In the
-- synthetic data both columns have about 30 distinct values, so neither
-- is more selective than the other; real names would be far more varied.)
CREATE INDEX idx_patient_name
    ON patient (last_name, first_name);

-- K2 / Q2 and K3 / Q4: "show me this patient's appointments, newest first".
-- Equality on patient_id finds the rows directly instead of scanning the
-- whole appointment table. The date and time columns are included in
-- descending/ascending order so that, for a patient with a LONG history,
-- PostgreSQL can read the newest rows first and stop early. In this data
-- set a typical patient has only about 9 appointments, so the measured
-- plans still use a bitmap scan followed by a tiny sort. The planner
-- judged that cheaper, and the timings confirm the index was worth it.
CREATE INDEX idx_appointment_patient_date
    ON appointment (patient_id, appointment_date DESC, start_time);

-- K3 / Q4: finding the prescriptions that belong to a consultation.
-- (consultation.appointment_id is already indexed by its UNIQUE constraint.)
CREATE INDEX idx_prescription_consultation
    ON prescription (consultation_id);

-- K5 / Q12: the laboratory work queue only ever looks at requests that
-- are not finished. In this data set that is well under 1% of rows, so a
-- PARTIAL index is tiny compared with indexing the whole table, and it is
-- already ordered by requested_at for the ORDER BY.
CREATE INDEX idx_lab_request_pending
    ON lab_request (requested_at)
    WHERE status IN ('REQUESTED', 'COLLECTED');

-- ---------------------------------------------------------------------
-- Supporting foreign-key indexes (justified by access pattern, not
-- benchmarked individually): joins from a consultation to its lab
-- requests, from a drug to the prescriptions that use it, and the
-- EXISTS lookup on medical history in Q13. They also speed up the
-- ON DELETE CASCADE checks.
-- ---------------------------------------------------------------------
CREATE INDEX idx_lab_request_consultation
    ON lab_request (consultation_id);

CREATE INDEX idx_prescription_item_medication
    ON prescription_item (medication_id);

CREATE INDEX idx_history_patient_condition
    ON patient_medical_history (patient_id, condition_name);

-- ---------------------------------------------------------------------
-- Existing index worth noting (created in Portfolio 1):
-- uq_doctor_slot_active on appointment (doctor_id, appointment_date,
-- start_time) WHERE status <> 'CANCELLED'. Besides preventing double
-- booking it already serves the doctor day/week sheet (Q11 / K4), which
-- is why that query needed no new index.
-- ---------------------------------------------------------------------

-- Refresh statistics so the planner knows about the new indexes.
ANALYZE;
