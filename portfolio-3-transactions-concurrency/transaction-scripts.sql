-- =====================================================================
-- Ardeliah Clinical System: single-session transaction examples
-- Portfolio 3: Transactions and Concurrency
--
-- Run (after Portfolios 1 and 2 have built the database):
--   psql -a -d ardeliah -f transaction-scripts.sql
-- (-a echoes each statement so the output reads like a transcript.)
--
-- Deliberately do NOT use ON_ERROR_STOP here: several examples contain a
-- statement that is MEANT to fail, to show what the database does next.
-- All demo rows carry a reason starting 'P3 txn' and are removed at the
-- start and end of the script, so it can be re-run safely.
--
-- ACID properties demonstrated:
--   T1 COMMIT   -> Atomicity + Consistency + Durability (all-or-nothing booking)
--   T2 failure  -> Atomicity (an error undoes EVERYTHING in the transaction)
--   T3 ROLLBACK -> Atomicity (voluntary undo, and isolation from other sessions)
--   T4 SAVEPOINT-> Partial rollback inside a larger transaction
--   T5 e-prescription -> Atomicity across parent/child rows + CHECK constraint
-- Durability under a crash is demonstrated separately (see README).
-- =====================================================================
SET search_path TO ardeliah;

-- Clean up anything left from a previous run (children first).
DELETE FROM audit_log   WHERE details LIKE 'P3 txn%';
DELETE FROM consultation WHERE appointment_id IN
       (SELECT appointment_id FROM appointment WHERE reason LIKE 'P3 txn%');
DELETE FROM appointment WHERE reason LIKE 'P3 txn%';

\echo
\echo '######## T1: COMMIT - book an appointment and write its audit entry together'
-- Business rule: every booking made by reception must leave an audit
-- record. The two inserts must succeed or fail as ONE unit.
BEGIN;

WITH new_appt AS (
    INSERT INTO appointment (patient_id, doctor_id, booked_by_staff_id,
                             appointment_date, start_time, reason)
    VALUES (20001, 40, 1, '2027-03-05', '09:00', 'P3 txn: T1 committed booking')
    RETURNING appointment_id
)
INSERT INTO audit_log (table_name, action, record_id, performed_by, details)
SELECT 'appointment', 'INSERT', appointment_id, 5, 'P3 txn: T1 booked by receptionist'
FROM new_appt;

COMMIT;

-- Both rows are now permanent (durable) and visible to every session.
SELECT a.appointment_id, a.status, a.reason, l.details AS audit_entry
FROM appointment a
JOIN audit_log l ON l.table_name = 'appointment' AND l.record_id = a.appointment_id
WHERE a.reason = 'P3 txn: T1 committed booking';


\echo
\echo '######## T2: failure mid-transaction - everything is undone (atomicity)'
-- The second booking asks for the same doctor and slot as the first, so
-- it violates the partial unique index uq_doctor_slot_active. The
-- audit row and the FIRST appointment, which were fine on their own, must
-- also disappear.
BEGIN;

INSERT INTO appointment (patient_id, doctor_id, booked_by_staff_id,
                         appointment_date, start_time, reason)
VALUES (20002, 40, 1, '2027-03-05', '10:00', 'P3 txn: T2 first booking');

INSERT INTO audit_log (table_name, action, record_id, performed_by, details)
VALUES ('appointment', 'INSERT', 0, 5, 'P3 txn: T2 audit for first booking');

-- Same doctor, same date, same time as the booking above: this fails.
INSERT INTO appointment (patient_id, doctor_id, booked_by_staff_id,
                         appointment_date, start_time, reason)
VALUES (20003, 40, 1, '2027-03-05', '10:00', 'P3 txn: T2 clashing booking');

-- After an error PostgreSQL marks the transaction as aborted: further
-- statements are refused until ROLLBACK. COMMIT on an aborted
-- transaction is turned into a ROLLBACK (the reply says ROLLBACK).
SELECT 'this statement is ignored' AS note;
COMMIT;

-- Nothing from T2 survived, not even the valid first booking.
SELECT (SELECT count(*) FROM appointment WHERE reason LIKE 'P3 txn: T2%') AS t2_appointments,
       (SELECT count(*) FROM audit_log   WHERE details LIKE 'P3 txn: T2%') AS t2_audit_rows;


\echo
\echo '######## T3: voluntary ROLLBACK - patient changes their mind'
BEGIN;

UPDATE appointment SET status = 'CANCELLED'
WHERE reason = 'P3 txn: T1 committed booking';

-- Inside this transaction the change is visible...
SELECT appointment_id, status FROM appointment
WHERE reason = 'P3 txn: T1 committed booking';

ROLLBACK;

-- ...but after ROLLBACK it never happened.
SELECT appointment_id, status FROM appointment
WHERE reason = 'P3 txn: T1 committed booking';


\echo
\echo '######## T4: SAVEPOINT - undo only part of a transaction'
-- A consultation is recorded and a lab request is attached. The first
-- lab request names a test that does not exist, so it fails; a savepoint
-- lets us undo just that step and carry on without losing the consultation.
BEGIN;

INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, status, reason)
VALUES (19990, 40, '2027-03-05', '11:00', 'COMPLETED', 'P3 txn: T4 savepoint');

INSERT INTO consultation (appointment_id, clinical_notes)
SELECT appointment_id, 'Fever for two days.'
FROM appointment WHERE reason = 'P3 txn: T4 savepoint';

SAVEPOINT before_lab_request;

INSERT INTO lab_request (consultation_id, test_id)
SELECT c.consultation_id, 9999                  -- no such test: FK violation
FROM consultation c JOIN appointment a ON a.appointment_id = c.appointment_id
WHERE a.reason = 'P3 txn: T4 savepoint';

ROLLBACK TO SAVEPOINT before_lab_request;       -- transaction is usable again

INSERT INTO lab_request (consultation_id, test_id, priority)
SELECT c.consultation_id, 1, 'URGENT'           -- test 1 = malaria parasite count
FROM consultation c JOIN appointment a ON a.appointment_id = c.appointment_id
WHERE a.reason = 'P3 txn: T4 savepoint';

COMMIT;

-- The consultation and the valid lab request were kept.
SELECT a.reason, c.clinical_notes, t.test_name, r.priority
FROM appointment a
JOIN consultation c ON c.appointment_id = a.appointment_id
JOIN lab_request r  ON r.consultation_id = c.consultation_id
JOIN lab_test_catalog t ON t.test_id = r.test_id
WHERE a.reason = 'P3 txn: T4 savepoint';


\echo
\echo '######## T5: e-prescription - header and lines succeed or fail together'
-- Issue a prescription for consultation 1 with two drug lines. The second
-- line has duration_days = 0, which violates a CHECK (duration_days > 0).
-- The prescription HEADER must not be left behind without its lines.
SELECT count(*) AS prescriptions_before FROM prescription WHERE consultation_id = 1;

BEGIN;

INSERT INTO prescription (consultation_id) VALUES (1);

INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days)
VALUES (currval(pg_get_serial_sequence('ardeliah.prescription', 'prescription_id')),
        3, '1 capsule', 'three times daily', 5);                -- fine

INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days)
VALUES (currval(pg_get_serial_sequence('ardeliah.prescription', 'prescription_id')),
        2, '1 tablet', 'twice daily', 0);                       -- violates CHECK

COMMIT;     -- becomes ROLLBACK because the transaction is aborted

SELECT count(*) AS prescriptions_after FROM prescription WHERE consultation_id = 1;


-- Final clean-up so the database is left as it was found.
DELETE FROM audit_log   WHERE details LIKE 'P3 txn%';
DELETE FROM consultation WHERE appointment_id IN
       (SELECT appointment_id FROM appointment WHERE reason LIKE 'P3 txn%');
DELETE FROM appointment WHERE reason LIKE 'P3 txn%';
