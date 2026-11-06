-- =====================================================================
-- Ardeliah Clinical System: bulk synthetic data for performance testing
-- Portfolio 2: Query Processing and Optimisation
--
-- Prerequisites (in this order):
--   psql -d ardeliah -f ../portfolio-1-database-design/create-tables.sql
--   psql -d ardeliah -f ../portfolio-1-database-design/sample-data.sql
--   psql -d ardeliah -f seed-bulk-data.sql
--
-- All data is synthetic. Names are drawn from short lists and there is
-- no real patient information anywhere.
--
-- The generator is DETERMINISTIC: instead of random() it uses a hash of
-- a seed string (function det below), so anyone re-running the script
-- gets exactly the same rows and therefore comparable query results.
--
-- Volumes produced (exact counts are printed at the end of the script):
--   20,003 patients, 40 doctors, about 185,000 appointments, and the
--   consultations, diagnoses, prescriptions, lab requests and lab results
--   that follow from the completed appointments (about 146,000
--   consultations, 175,000 diagnoses, 87,000 prescriptions, 58,000 lab
--   requests).
-- =====================================================================
SET search_path TO ardeliah;
\timing on

-- Deterministic pseudo-random integer in [0, n) derived from a text seed.
CREATE OR REPLACE FUNCTION det(seed text, n int) RETURNS int
LANGUAGE sql IMMUTABLE AS
$$ SELECT (abs(hashtext(seed)::bigint) % n)::int $$;

-- ---------------------------------------------------------------------
-- 1. Patients (ids 4 .. 20003; ids 1-3 come from sample-data.sql)
-- ---------------------------------------------------------------------
INSERT INTO patient (first_name, last_name, date_of_birth, gender, phone, email, address, blood_group)
SELECT
  (ARRAY['Chinedu','Aisha','Emeka','Fatima','Oluwaseun','Ngozi','Ibrahim','Blessing','Yusuf','Amaka',
         'Segun','Zainab','Ifeanyi','Hauwa','Tolu','Chioma','Musa','Folake','Uche','Rashida',
         'Kelechi','Bukola','Abdullahi','Nneka','Damilola','Maryam','Obinna','Temitope','Sadiq','Joy'])[1+det('fn'||g,30)],
  (ARRAY['Okeke','Abubakar','Adeyemi','Balogun','Nwosu','Mohammed','Ogunleye','Eze','Danjuma','Afolabi',
         'Ibekwe','Garba','Olawale','Chukwu','Suleiman','Adekunle','Obi','Lawal','Onyeama','Bello',
         'Okonkwo','Usman','Fashola','Nnamdi','Yakubu','Ajayi','Ugwu','Hassan','Salako','Kalu'])[1+det('ln'||g,30)],
  date '1950-01-01' + det('dob'||g, 20000),
  (ARRAY['M','F'])[1+det('gen'||g,2)],
  '080' || lpad(det('ph'||g,100000000)::text, 8, '0'),
  'patient' || g || '@example.com',
  (ARRAY['Garki','Wuse','Maitama','Asokoro','Kubwa','Gwarinpa','Lugbe','Jabi','Utako','Nyanya'])[1+det('ad'||g,10)] || ', Abuja',
  (ARRAY['A+','A-','B+','B-','AB+','AB-','O+','O-'])[1+det('bg'||g,8)]
FROM generate_series(1, 20000) g;

INSERT INTO patient_medical_history (patient_id, condition_name, noted_on, notes)
SELECT 4 + det('hp'||g, 20000),
       (ARRAY['Hypertension','Type 2 diabetes','Asthma','Sickle cell trait','Peptic ulcer disease',
              'Penicillin allergy','Chronic low back pain','Recurrent malaria'])[1+det('hc'||g,8)],
       date '2018-01-01' + det('hd'||g, 3000),
       NULL
FROM generate_series(1, 8000) g;

-- ---------------------------------------------------------------------
-- 2. Doctors (ids 3 .. 40), their schedules, and extra staff
-- ---------------------------------------------------------------------
INSERT INTO doctor (first_name, last_name, specialisation_id, licence_no, phone)
SELECT (ARRAY['Kunle','Amina','Peter','Grace','Daniel','Sola','Hadiza','Victor','Linda','Tayo'])[1+det('dfn'||g,10)],
       (ARRAY['Okoro','Bello','Adamu','Nwachukwu','Oyelaran','Idris','Eke','Akinola','Gambo','Umoh'])[1+det('dln'||g,10)],
       1 + det('dsp'||g, 8),
       'MDCN-2' || lpad(g::text, 5, '0'),
       '081' || lpad(det('dph'||g,100000000)::text, 8, '0')
FROM generate_series(1, 38) g;

-- Doctors 3-40 work Monday to Friday 08:00-16:00.
INSERT INTO doctor_schedule (doctor_id, day_of_week, start_time, end_time)
SELECT d, dow, time '08:00', time '16:00'
FROM generate_series(3, 40) d, generate_series(1, 5) dow;

-- Receptionists get staff ids 3-8, lab technicians 9-14.
INSERT INTO staff (first_name, last_name, staff_type)
SELECT 'Reception' || g, 'Staff', 'RECEPTIONIST' FROM generate_series(1, 6) g;
INSERT INTO staff (first_name, last_name, staff_type)
SELECT 'Tech' || g, 'Lab', 'LAB_TECHNICIAN' FROM generate_series(1, 6) g;

-- ---------------------------------------------------------------------
-- 3. Appointments
--    40 doctors x 900 days x 16 half-hour slots, weekdays only, keeping
--    ~45% of slots. 'Today' is fixed at 2026-11-06 so results are reproducible.
--    ON CONFLICT skips the few slots already taken by sample-data.sql
--    (the partial unique index uq_doctor_slot_active would reject them).
-- ---------------------------------------------------------------------
INSERT INTO appointment (patient_id, doctor_id, booked_by_staff_id, appointment_date, start_time, status, reason)
SELECT
  4 + det('ap'||d||'-'||dy||'-'||s, 20000),
  d,
  CASE WHEN det('bk'||d||'-'||dy||'-'||s, 4) = 0 THEN NULL
       ELSE (ARRAY[1,3,4,5,6,7,8])[1+det('rc'||d||'-'||dy||'-'||s, 7)] END,
  date '2024-06-03' + dy,
  time '08:00' + s * interval '30 minutes',
  CASE
    WHEN date '2024-06-03' + dy >= date '2026-11-06'
         THEN CASE WHEN det('st'||d||'-'||dy||'-'||s,100) < 10 THEN 'CANCELLED' ELSE 'SCHEDULED' END
    WHEN det('st'||d||'-'||dy||'-'||s,100) < 80 THEN 'COMPLETED'
    WHEN det('st'||d||'-'||dy||'-'||s,100) < 90 THEN 'CANCELLED'
    ELSE 'NO_SHOW'
  END,
  (ARRAY['Fever and headache','Routine check-up','Cough and catarrh','Blood pressure review',
         'Abdominal pain','Back pain','Diabetes follow-up','Skin rash','Antenatal visit','Child immunisation'])[1+det('rs'||d||'-'||dy||'-'||s,10)]
FROM generate_series(1, 40) d, generate_series(0, 899) dy, generate_series(0, 15) s
WHERE extract(isodow FROM date '2024-06-03' + dy) <= 5
  AND det('keep'||d||'-'||dy||'-'||s, 100) < 45
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Consultations for completed appointments (sample appointment 1
--    already has one, so it is excluded)
-- ---------------------------------------------------------------------
INSERT INTO consultation (appointment_id, clinical_notes, consulted_at)
SELECT a.appointment_id,
       (ARRAY['Patient stable. Advice given.','Examination unremarkable. Review if symptoms persist.',
              'Symptoms improving on current treatment.','Investigations requested. Return with results.',
              'Counselled on diet and exercise.','Referred for further assessment.'])[1+det('cn'||a.appointment_id,6)],
       (a.appointment_date + a.start_time + interval '10 minutes') AT TIME ZONE 'Africa/Lagos'
FROM appointment a
WHERE a.status = 'COMPLETED'
  AND NOT EXISTS (SELECT 1 FROM consultation c WHERE c.appointment_id = a.appointment_id);

-- Numbered helper lists so we can pick reference rows by position.
CREATE TEMP TABLE icd_n  AS SELECT row_number() OVER (ORDER BY icd_code)      AS n, icd_code      FROM icd_code;
CREATE TEMP TABLE med_n  AS SELECT row_number() OVER (ORDER BY medication_id) AS n, medication_id FROM medication;
CREATE TEMP TABLE test_n AS SELECT row_number() OVER (ORDER BY test_id)       AS n, test_id       FROM lab_test_catalog;

-- ---------------------------------------------------------------------
-- 5. Diagnoses: every new consultation gets one, about 20% get a second
-- ---------------------------------------------------------------------
INSERT INTO diagnosis (consultation_id, icd_code, severity)
SELECT c.consultation_id, i.icd_code, (ARRAY['MILD','MODERATE','SEVERE'])[1+det('sv'||c.consultation_id,3)]
FROM consultation c
JOIN icd_n i ON i.n = 1 + det('d1'||c.consultation_id, 12)
WHERE c.consultation_id > 1;

INSERT INTO diagnosis (consultation_id, icd_code, severity)
SELECT c.consultation_id, i2.icd_code, 'MILD'
FROM consultation c
JOIN icd_n i1 ON i1.n = 1 + det('d1'||c.consultation_id, 12)
-- second code is always different: shift by 1 to 11 positions
JOIN icd_n i2 ON i2.n = 1 + ((i1.n - 1 + 1 + det('d2'||c.consultation_id, 11)) % 12)
WHERE c.consultation_id > 1 AND det('has2'||c.consultation_id, 100) < 20;

-- ---------------------------------------------------------------------
-- 6. Prescriptions: ~60% of consultations, one or two drugs each
-- ---------------------------------------------------------------------
INSERT INTO prescription (consultation_id, issued_at, status)
SELECT c.consultation_id, c.consulted_at + interval '30 minutes',
       CASE WHEN c.consulted_at < timestamptz '2026-10-01 00:00+01'
            THEN CASE WHEN det('ps'||c.consultation_id,100) < 80 THEN 'DISPENSED' ELSE 'EXPIRED' END
            ELSE CASE WHEN det('ps'||c.consultation_id,100) < 70 THEN 'DISPENSED' ELSE 'ISSUED' END
       END
FROM consultation c
WHERE c.consultation_id > 1 AND det('rx'||c.consultation_id, 100) < 60;

INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days)
SELECT p.prescription_id, m.medication_id,
       CASE mm.form WHEN 'tablet'  THEN (ARRAY['1 tablet','2 tablets'])[1+det('do'||p.prescription_id,2)]
                    WHEN 'capsule' THEN '1 capsule'
                    WHEN 'cream'   THEN 'apply thinly'
                    WHEN 'inhaler' THEN '2 puffs'
                    WHEN 'sachet'  THEN '1 sachet'
                    ELSE '1 dose' END,
       (ARRAY['once daily','twice daily','three times daily','every 8 hours'])[1+det('fq'||p.prescription_id,4)],
       3 + det('du'||p.prescription_id, 12)
FROM prescription p
JOIN med_n m ON m.n = 1 + det('m1'||p.prescription_id, 12)
JOIN medication mm ON mm.medication_id = m.medication_id
WHERE p.prescription_id > 1;

INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days)
SELECT p.prescription_id, m2.medication_id,
       CASE mm2.form WHEN 'tablet'  THEN '1 tablet'
                     WHEN 'capsule' THEN '1 capsule'
                     WHEN 'cream'   THEN 'apply thinly'
                     WHEN 'inhaler' THEN '2 puffs'
                     WHEN 'sachet'  THEN '1 sachet'
                     ELSE '1 dose' END,
       'twice daily', 3 + det('du2'||p.prescription_id, 12)
FROM prescription p
JOIN med_n m1 ON m1.n = 1 + det('m1'||p.prescription_id, 12)
JOIN med_n m2 ON m2.n = 1 + ((m1.n - 1 + 1 + det('m2'||p.prescription_id, 11)) % 12)
JOIN medication mm2 ON mm2.medication_id = m2.medication_id
WHERE p.prescription_id > 1 AND det('two'||p.prescription_id, 100) < 60;

-- ---------------------------------------------------------------------
-- 7. Lab requests (~40% of consultations) and results (completed ones)
-- ---------------------------------------------------------------------
INSERT INTO lab_request (consultation_id, test_id, requested_at, priority, status)
SELECT c.consultation_id, t.test_id, c.consulted_at + interval '5 minutes',
       CASE WHEN det('pr'||c.consultation_id,100) < 15 THEN 'URGENT' ELSE 'ROUTINE' END,
       CASE WHEN c.consulted_at < timestamptz '2026-10-15 00:00+01' THEN 'COMPLETED'  -- older work is finished
            WHEN det('ls'||c.consultation_id,100) < 75 THEN 'COMPLETED'
            WHEN det('ls'||c.consultation_id,100) < 88 THEN 'COLLECTED' ELSE 'REQUESTED' END
FROM consultation c
JOIN test_n t ON t.n = 1 + det('lt'||c.consultation_id, 8)
WHERE c.consultation_id > 1 AND det('lab'||c.consultation_id, 100) < 40;

INSERT INTO lab_result (lab_request_id, technician_id, result_value, abnormal_flag, recorded_at)
SELECT q.lab_request_id, q.tech, q.val,
       (q.val > coalesce(q.hi, q.val)) OR (q.val < coalesce(q.lo, q.val)),
       q.requested_at + interval '40 minutes'
FROM (
  SELECT r.lab_request_id, r.requested_at,
         (ARRAY[2,9,10,11,12,13,14])[1+det('tc'||r.lab_request_id,7)] AS tech,
         t.ref_range_low AS lo, t.ref_range_high AS hi,
         CASE WHEN t.ref_range_high = t.ref_range_low   -- qualitative tests such as MP count
              THEN (CASE WHEN det('mp'||r.lab_request_id,5) = 0 THEN 200 + det('mv'||r.lab_request_id,5000) ELSE 0 END)::numeric
              ELSE round((t.ref_range_low + (t.ref_range_high - t.ref_range_low)
                          * (0.4 + det('rv'||r.lab_request_id,90) / 100.0))::numeric, 2)
         END AS val
  FROM lab_request r
  JOIN lab_test_catalog t ON t.test_id = r.test_id
  WHERE r.status = 'COMPLETED' AND r.lab_request_id > 1
) q;

-- Refresh planner statistics so EXPLAIN reflects the real data volumes.
ANALYZE;

\timing off
SELECT 'patient' AS table_name, count(*) AS rows FROM patient
UNION ALL SELECT 'doctor', count(*) FROM doctor
UNION ALL SELECT 'appointment', count(*) FROM appointment
UNION ALL SELECT 'consultation', count(*) FROM consultation
UNION ALL SELECT 'diagnosis', count(*) FROM diagnosis
UNION ALL SELECT 'prescription', count(*) FROM prescription
UNION ALL SELECT 'prescription_item', count(*) FROM prescription_item
UNION ALL SELECT 'lab_request', count(*) FROM lab_request
UNION ALL SELECT 'lab_result', count(*) FROM lab_result
ORDER BY 1;
