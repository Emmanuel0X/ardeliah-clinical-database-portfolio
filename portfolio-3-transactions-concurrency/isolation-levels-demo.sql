-- =====================================================================
-- Ardeliah Clinical System: isolation levels, concurrency problems and
-- control mechanisms (two sessions)
-- Portfolio 3: Transactions and Concurrency
--
-- HOW TO USE THIS FILE
--   Manual: open two terminals, both running  psql -d ardeliah  .
--     Run the DEMO 0 block once (it creates test rows), then for each
--     demo follow the steps IN ORDER, pasting each "@A" block into
--     terminal A and each "@B" block into terminal B. A step marked
--     "waits" is expected to hang until the other session commits or
--     rolls back. Re-run DEMO 0 between demos to reset the test rows.
--   Automatic: python3 run-concurrency-demos.py  executes every demo
--     against two live psql sessions in this exact order and writes the
--     real output to evidence/concurrency-transcript.md.
--
-- The @A / @B / @SETUP / @CLEANUP lines are markers read by the script;
-- to a human they are just comments.
--
-- Test rows use ids 900001+ (set explicitly) and the text 'P3 demo' so
-- they never collide with the bulk data and can be removed completely.
-- Slots are on 2027-03-01/02, after all generated appointments.
--
-- PostgreSQL notes that shape these demos:
--   * PostgreSQL implements MVCC (multi-version concurrency control).
--     Readers never block writers and writers never block readers.
--   * Only three distinct isolation levels exist. READ UNCOMMITTED is
--     accepted but behaves exactly like READ COMMITTED, so a dirty read
--     is impossible (DEMO 2 shows this).
--   * REPEATABLE READ is snapshot isolation: it also prevents phantom
--     reads, which the SQL standard does not require at this level.
-- =====================================================================

-- === DEMO 0: create the test rows (also used to reset between demos) ===
-- @SETUP
SET search_path TO ardeliah;
DELETE FROM audit_log WHERE details LIKE 'P3 demo%';
DELETE FROM consultation WHERE appointment_id IN
       (SELECT appointment_id FROM appointment WHERE reason LIKE 'P3 demo%');
DELETE FROM appointment WHERE reason LIKE 'P3 demo%';

INSERT INTO appointment (appointment_id, patient_id, doctor_id, appointment_date, start_time, status, reason)
OVERRIDING SYSTEM VALUE VALUES
 (900001, 20001, 40, '2027-03-01', '09:00', 'SCHEDULED', 'P3 demo: appointment one'),
 (900002, 20002, 40, '2027-03-01', '10:00', 'SCHEDULED', 'P3 demo: appointment two'),
 (900003, 20003, 39, '2027-03-02', '09:00', 'SCHEDULED', 'P3 demo: patient already booked once that day');

INSERT INTO consultation (consultation_id, appointment_id, clinical_notes)
OVERRIDING SYSTEM VALUE VALUES (900001, 900001, 'Initial note.');

INSERT INTO lab_request (lab_request_id, consultation_id, test_id, priority, status)
OVERRIDING SYSTEM VALUE VALUES
 (900001, 900001, 1, 'URGENT', 'REQUESTED'),
 (900002, 900001, 2, 'URGENT', 'REQUESTED'),
 (900003, 900001, 3, 'URGENT', 'REQUESTED');


-- === DEMO 1: READ COMMITTED (the default): no dirty read, but a non-repeatable read ===
-- Session A reads an appointment twice inside one transaction. Between the
-- two reads, session B changes and commits that appointment.
-- @A
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT appointment_id, status FROM appointment WHERE appointment_id = 900001;
-- @B
-- Receptionist B checks the patient in. Not committed yet.
BEGIN;
UPDATE appointment SET status = 'CHECKED_IN' WHERE appointment_id = 900001;
-- @A
-- B's change is uncommitted, so A does not see it (no dirty read), and A's
-- read was not blocked by B's open update (MVCC: readers never wait).
SELECT appointment_id, status FROM appointment WHERE appointment_id = 900001;
-- @B
COMMIT;
-- @A
-- Same query, same transaction, different answer: a NON-REPEATABLE READ.
SELECT appointment_id, status FROM appointment WHERE appointment_id = 900001;
COMMIT;


-- === DEMO 2: READ UNCOMMITTED behaves like READ COMMITTED in PostgreSQL ===
-- A dirty read means seeing another transaction's UNCOMMITTED data. The
-- SQL standard allows it at READ UNCOMMITTED; PostgreSQL does not.
-- @A
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
SHOW transaction_isolation;
-- @B
BEGIN;
UPDATE appointment SET status = 'CANCELLED' WHERE appointment_id = 900001;
-- @A
-- Still SCHEDULED: no dirty read, even though A asked for READ UNCOMMITTED.
SELECT appointment_id, status FROM appointment WHERE appointment_id = 900001;
-- @B
ROLLBACK;
-- @A
COMMIT;


-- === DEMO 3: REPEATABLE READ: stable snapshot, no phantoms, update conflict error ===
-- A's transaction sees one snapshot of the database taken at its first
-- query, however much other sessions commit afterwards.
-- @A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS doctor_40_bookings_on_1_march
FROM appointment
WHERE doctor_id = 40 AND appointment_date = '2027-03-01' AND status <> 'CANCELLED';
SELECT appointment_id, status FROM appointment WHERE appointment_id = 900002;
-- @B
-- B (autocommit) adds a NEW appointment and changes an existing one.
INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, reason)
VALUES (19991, 40, '2027-03-01', '11:00', 'P3 demo: phantom row');
UPDATE appointment SET status = 'CHECKED_IN' WHERE appointment_id = 900002;
-- @A
-- Count is unchanged (no PHANTOM ROW) and the status is unchanged (the
-- read is REPEATABLE), although B has already committed both changes.
SELECT count(*) AS doctor_40_bookings_on_1_march
FROM appointment
WHERE doctor_id = 40 AND appointment_date = '2027-03-01' AND status <> 'CANCELLED';
SELECT appointment_id, status FROM appointment WHERE appointment_id = 900002;
-- A now tries to change the row that B already changed and committed. A's
-- snapshot is stale for that row, so PostgreSQL refuses rather than
-- silently overwriting (it prevents a LOST UPDATE). The application is
-- expected to catch SQLSTATE 40001 and retry the whole transaction.
UPDATE appointment SET status = 'CANCELLED' WHERE appointment_id = 900002;
ROLLBACK;
-- @A
-- A new transaction takes a new snapshot and sees everything B committed.
SELECT count(*) AS doctor_40_bookings_on_1_march
FROM appointment
WHERE doctor_id = 40 AND appointment_date = '2027-03-01' AND status <> 'CANCELLED';


-- === DEMO 4a: WRITE SKEW is NOT prevented by REPEATABLE READ ===
-- Business rule (enforced only in application logic, not by a constraint):
-- a patient may have at most 2 active appointments on one day. Patient
-- 20003 already has 1 on 2027-03-02. Two receptionists each check the
-- count, see 1, and add a booking with a DIFFERENT doctor. Because they
-- write different rows there is no row-level conflict to detect.
-- @A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS patient_bookings_that_day FROM appointment
WHERE patient_id = 20003 AND appointment_date = '2027-03-02' AND status <> 'CANCELLED';
-- @B
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS patient_bookings_that_day FROM appointment
WHERE patient_id = 20003 AND appointment_date = '2027-03-02' AND status <> 'CANCELLED';
-- @A
-- Count was 1, which is below the limit of 2, so A books.
INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, reason)
VALUES (20003, 38, '2027-03-02', '10:00', 'P3 demo: write skew A');
-- @B
INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, reason)
VALUES (20003, 37, '2027-03-02', '10:00', 'P3 demo: write skew B');
-- @A
COMMIT;
-- @B
COMMIT;
-- @A
-- Both committed: the patient now has 3 bookings and the rule is broken.
SELECT count(*) AS patient_bookings_that_day FROM appointment
WHERE patient_id = 20003 AND appointment_date = '2027-03-02' AND status <> 'CANCELLED';


-- === DEMO 4b: SERIALIZABLE prevents the same write skew ===
-- Same two transactions, but at the strictest level. PostgreSQL tracks
-- read/write dependencies (Serializable Snapshot Isolation) and aborts one.
-- @SETUP
SET search_path TO ardeliah;
DELETE FROM appointment WHERE reason LIKE 'P3 demo: write skew%';
-- @A
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS patient_bookings_that_day FROM appointment
WHERE patient_id = 20003 AND appointment_date = '2027-03-02' AND status <> 'CANCELLED';
-- @B
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS patient_bookings_that_day FROM appointment
WHERE patient_id = 20003 AND appointment_date = '2027-03-02' AND status <> 'CANCELLED';
-- @A
INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, reason)
VALUES (20003, 38, '2027-03-02', '10:00', 'P3 demo: write skew A');
-- @B
INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, reason)
VALUES (20003, 37, '2027-03-02', '10:00', 'P3 demo: write skew B');
-- @A
COMMIT;
-- @B
-- B is refused (SQLSTATE 40001). The application should retry B, and on
-- retry it would see 2 bookings and decline to book a third.
COMMIT;
-- @A
SELECT count(*) AS patient_bookings_that_day FROM appointment
WHERE patient_id = 20003 AND appointment_date = '2027-03-02' AND status <> 'CANCELLED';


-- === DEMO 5: double booking the same slot: the unique index makes the second booking wait, then fail ===
-- Two receptionists try to book doctor 40 at 13:00 at the same moment.
-- Both first check the slot is free, which is not enough on its own
-- (check-then-insert races). The partial unique index from Portfolio 1 is
-- the real protection.
-- @A
BEGIN;
SELECT count(*) AS bookings_in_slot FROM appointment
WHERE doctor_id = 40 AND appointment_date = '2027-03-01' AND start_time = '13:00' AND status <> 'CANCELLED';
-- @B
BEGIN;
SELECT count(*) AS bookings_in_slot FROM appointment
WHERE doctor_id = 40 AND appointment_date = '2027-03-01' AND start_time = '13:00' AND status <> 'CANCELLED';
-- @A
INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, reason)
VALUES (19992, 40, '2027-03-01', '13:00', 'P3 demo: receptionist A');
-- @B
-- B's insert needs the same index entry as A's uncommitted insert, so it
-- WAITS (this statement does not return yet).
INSERT INTO appointment (patient_id, doctor_id, appointment_date, start_time, reason)
VALUES (19993, 40, '2027-03-01', '13:00', 'P3 demo: receptionist B');
-- @A
-- A commits. B is released, and is then told the slot is taken.
COMMIT;
-- @B
ROLLBACK;
-- @A
SELECT appointment_id, patient_id, start_time, reason FROM appointment
WHERE doctor_id = 40 AND appointment_date = '2027-03-01' AND start_time = '13:00';


-- === DEMO 6a: LOST UPDATE with read-modify-write in the application ===
-- A doctor and a nurse both add to the consultation notes. Each reads the
-- current text, adds a sentence in application code, and writes the whole
-- text back. The second writer silently overwrites the first.
-- @SETUP
SET search_path TO ardeliah;
UPDATE consultation SET clinical_notes = 'Initial note.' WHERE consultation_id = 900001;
-- @A
BEGIN;
SELECT clinical_notes FROM consultation WHERE consultation_id = 900001;
-- @B
BEGIN;
SELECT clinical_notes FROM consultation WHERE consultation_id = 900001;
-- @A
UPDATE consultation SET clinical_notes = 'Initial note. Doctor A: BP 140/90.'
WHERE consultation_id = 900001;
COMMIT;
-- @B
-- B writes back what IT read plus its own sentence, unaware of A's.
UPDATE consultation SET clinical_notes = 'Initial note. Nurse B: allergic to penicillin.'
WHERE consultation_id = 900001;
COMMIT;
-- @A
-- Doctor A's blood pressure note has been lost.
SELECT clinical_notes FROM consultation WHERE consultation_id = 900001;


-- === DEMO 6b: pessimistic locking with SELECT ... FOR UPDATE fixes it ===
-- @SETUP
SET search_path TO ardeliah;
UPDATE consultation SET clinical_notes = 'Initial note.' WHERE consultation_id = 900001;
-- @A
BEGIN;
SELECT clinical_notes FROM consultation WHERE consultation_id = 900001 FOR UPDATE;
-- @B
BEGIN;
-- B asks for the same row lock and WAITS until A finishes.
SELECT clinical_notes FROM consultation WHERE consultation_id = 900001 FOR UPDATE;
-- @A
UPDATE consultation SET clinical_notes = 'Initial note. Doctor A: BP 140/90.'
WHERE consultation_id = 900001;
COMMIT;
-- @B
-- B's blocked SELECT has now returned A's committed text (see the output
-- above), so the application builds its new text on top of it.
UPDATE consultation
SET clinical_notes = 'Initial note. Doctor A: BP 140/90. Nurse B: allergic to penicillin.'
WHERE consultation_id = 900001;
COMMIT;
-- @A
-- Both notes survive.
SELECT clinical_notes FROM consultation WHERE consultation_id = 900001;


-- === DEMO 7a: DEADLOCK: two sessions lock the same two rows in opposite order ===
-- @SETUP
SET search_path TO ardeliah;
-- @A
BEGIN;
UPDATE appointment SET reason = 'P3 demo: A touched one' WHERE appointment_id = 900001;
-- @B
BEGIN;
UPDATE appointment SET reason = 'P3 demo: B touched two' WHERE appointment_id = 900002;
-- @A
-- A now wants B's row, so A waits for B.
UPDATE appointment SET reason = 'P3 demo: A touched two' WHERE appointment_id = 900002;
-- @B
-- B wants A's row while A waits for B: a cycle. After deadlock_timeout
-- (1 second) PostgreSQL detects it and aborts one transaction so the
-- other can proceed.
UPDATE appointment SET reason = 'P3 demo: B touched one' WHERE appointment_id = 900001;
-- @B
ROLLBACK;
-- @A
COMMIT;


-- === DEMO 7b: avoiding the deadlock with a consistent lock order ===
-- If every transaction touches rows in the same order (lowest id first),
-- a cycle cannot form: the second session simply waits its turn.
-- @SETUP
SET search_path TO ardeliah;
-- @A
BEGIN;
UPDATE appointment SET reason = 'P3 demo: A touched one' WHERE appointment_id = 900001;
-- @B
BEGIN;
-- B also starts with row 900001, so it waits (no deadlock, just a queue).
UPDATE appointment SET reason = 'P3 demo: B touched one' WHERE appointment_id = 900001;
-- @A
UPDATE appointment SET reason = 'P3 demo: A touched two' WHERE appointment_id = 900002;
COMMIT;
-- @B
UPDATE appointment SET reason = 'P3 demo: B touched two' WHERE appointment_id = 900002;
COMMIT;


-- === DEMO 8: FOR UPDATE SKIP LOCKED: two lab technicians take different work ===
-- Each technician takes the next unassigned request from the work list.
-- With plain FOR UPDATE the second technician would wait for the first;
-- SKIP LOCKED makes them move on to the next free request instead.
-- @SETUP
SET search_path TO ardeliah;
-- @A
BEGIN;
SELECT lab_request_id, test_id FROM lab_request
WHERE consultation_id = 900001 AND status = 'REQUESTED'
ORDER BY lab_request_id LIMIT 1
FOR UPDATE SKIP LOCKED;
-- @B
BEGIN;
-- Does not wait: request 900001 is locked by A, so B is given 900002.
SELECT lab_request_id, test_id FROM lab_request
WHERE consultation_id = 900001 AND status = 'REQUESTED'
ORDER BY lab_request_id LIMIT 1
FOR UPDATE SKIP LOCKED;
-- @A
UPDATE lab_request SET status = 'COLLECTED' WHERE lab_request_id = 900001;
COMMIT;
-- @B
UPDATE lab_request SET status = 'COLLECTED' WHERE lab_request_id = 900002;
COMMIT;
-- @A
SELECT lab_request_id, status FROM lab_request
WHERE consultation_id = 900001 ORDER BY lab_request_id;


-- === CLEANUP: remove all test rows ===
-- @CLEANUP
SET search_path TO ardeliah;
DELETE FROM audit_log WHERE details LIKE 'P3 demo%';
DELETE FROM consultation WHERE appointment_id IN
       (SELECT appointment_id FROM appointment WHERE reason LIKE 'P3 demo%');
DELETE FROM appointment WHERE reason LIKE 'P3 demo%';
