-- Measures the write-side cost of idx_appointment_patient_date:
-- insert all 185,304 appointment rows into a scratch table with and
-- without the index. Run with: psql -d ardeliah -f write-cost-test.sql
SET search_path TO ardeliah;
\timing on
CREATE TEMP TABLE w_plain AS SELECT * FROM appointment WITH NO DATA;
CREATE TEMP TABLE w_indexed AS SELECT * FROM appointment WITH NO DATA;
CREATE INDEX ON w_indexed (patient_id, appointment_date DESC, start_time);

\echo === run 1: insert without the index ===
INSERT INTO w_plain SELECT * FROM appointment;
\echo === run 1: insert with the index ===
INSERT INTO w_indexed SELECT * FROM appointment;
TRUNCATE w_plain, w_indexed;
\echo === run 2: insert without the index ===
INSERT INTO w_plain SELECT * FROM appointment;
\echo === run 2: insert with the index ===
INSERT INTO w_indexed SELECT * FROM appointment;
TRUNCATE w_plain, w_indexed;
\echo === run 3: insert without the index ===
INSERT INTO w_plain SELECT * FROM appointment;
\echo === run 3: insert with the index ===
INSERT INTO w_indexed SELECT * FROM appointment;
