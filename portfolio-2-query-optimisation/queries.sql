-- =====================================================================
-- Ardeliah Clinical System: query workload
-- Portfolio 2: Query Processing and Optimisation
--
-- 15 queries covering SELECT/WHERE, INNER and LEFT JOIN, multi-table
-- joins, non-correlated and correlated subqueries, aggregates with
-- GROUP BY / HAVING, ORDER BY with LIMIT, and a window function.
--
-- Run on the data produced by seed-bulk-data.sql:
--   psql -d ardeliah -f queries.sql
-- "Today" is treated as 2026-11-06 so results are reproducible.
-- =====================================================================
SET search_path TO ardeliah;

-- ---------------------------------------------------------------------
-- Q1  Simple SELECT with WHERE and ORDER BY
-- Reception searches for a patient by name.
-- ---------------------------------------------------------------------
SELECT patient_id, first_name, last_name, date_of_birth, phone
FROM patient
WHERE last_name = 'Okeke' AND first_name = 'Chinedu'
ORDER BY date_of_birth
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q2  INNER JOIN across three tables
-- A patient's most recent appointments with doctor and specialisation.
-- ---------------------------------------------------------------------
SELECT a.appointment_date, a.start_time, a.status,
       d.first_name || ' ' || d.last_name AS doctor,
       s.specialisation_name
FROM appointment a
JOIN doctor d          ON d.doctor_id = a.doctor_id
JOIN specialisation s  ON s.specialisation_id = d.specialisation_id
WHERE a.patient_id = 7421
ORDER BY a.appointment_date DESC, a.start_time
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q3  LEFT JOIN
-- Patients with NO completed appointment on record. The LEFT JOIN keeps
-- every patient; those with no match show NULL on the appointment side.
-- ---------------------------------------------------------------------
SELECT p.patient_id, p.first_name, p.last_name, p.date_of_birth
FROM patient p
LEFT JOIN appointment a
       ON a.patient_id = p.patient_id AND a.status = 'COMPLETED'
WHERE a.appointment_id IS NULL
ORDER BY p.patient_id
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q4  Multi-table JOIN (six tables)
-- Full prescription history for one patient, with drug details.
-- ---------------------------------------------------------------------
SELECT a.appointment_date,
       m.generic_name, m.strength, m.form,
       pi.dosage, pi.frequency, pi.duration_days,
       pr.status AS prescription_status
FROM appointment a
JOIN consultation c        ON c.appointment_id  = a.appointment_id
JOIN prescription pr       ON pr.consultation_id = c.consultation_id
JOIN prescription_item pi  ON pi.prescription_id = pr.prescription_id
JOIN medication m          ON m.medication_id   = pi.medication_id
WHERE a.patient_id = 7421
ORDER BY a.appointment_date DESC, m.generic_name;

-- ---------------------------------------------------------------------
-- Q5  GROUP BY with HAVING
-- ICD codes recorded as SEVERE at least 4,050 times. The threshold sits
-- inside the spread of the data, so HAVING removes some groups and keeps others.
-- ---------------------------------------------------------------------
SELECT i.icd_code, i.description,
       count(*) AS severe_diagnoses
FROM diagnosis dg
JOIN icd_code i ON i.icd_code = dg.icd_code
WHERE dg.severity = 'SEVERE'
GROUP BY i.icd_code, i.description
HAVING count(*) >= 4050
ORDER BY severe_diagnoses DESC;

-- ---------------------------------------------------------------------
-- Q6  Aggregation over time with FILTER
-- Appointment outcomes per month for the last six months before today.
-- ---------------------------------------------------------------------
SELECT date_trunc('month', appointment_date)::date AS month,
       count(*)                                      AS total,
       count(*) FILTER (WHERE status = 'COMPLETED')  AS completed,
       count(*) FILTER (WHERE status = 'CANCELLED')  AS cancelled,
       count(*) FILTER (WHERE status = 'NO_SHOW')    AS no_show,
       round(100.0 * count(*) FILTER (WHERE status = 'NO_SHOW') / count(*), 1) AS no_show_pct
FROM appointment
WHERE appointment_date >= date '2026-05-01' AND appointment_date < date '2026-11-01'
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q7  Non-correlated subquery (IN)
-- Patients diagnosed with malaria (B50.9) since 1 October 2026.
-- The inner query runs once and produces a list of patient ids.
-- ---------------------------------------------------------------------
SELECT patient_id, first_name, last_name
FROM patient
WHERE patient_id IN (
    SELECT a.patient_id
    FROM appointment a
    JOIN consultation c ON c.appointment_id = a.appointment_id
    JOIN diagnosis dg   ON dg.consultation_id = c.consultation_id
    WHERE dg.icd_code = 'B50.9'
      AND a.appointment_date >= date '2026-10-01'
)
ORDER BY patient_id
LIMIT 15;

-- ---------------------------------------------------------------------
-- Q8  Correlated subquery
-- Each patient's most recent completed appointment, for patients 4-13.
-- The inner query is evaluated in the context of every outer row.
-- ---------------------------------------------------------------------
SELECT a.patient_id, a.appointment_date, a.start_time, a.doctor_id
FROM appointment a
WHERE a.patient_id BETWEEN 4 AND 13
  AND a.status = 'COMPLETED'
  AND a.appointment_date = (
        SELECT max(a2.appointment_date)
        FROM appointment a2
        WHERE a2.patient_id = a.patient_id
          AND a2.status = 'COMPLETED')
ORDER BY a.patient_id;

-- ---------------------------------------------------------------------
-- Q9  Aggregate with COUNT and a calculated percentage
-- Share of abnormal results per laboratory test.
-- ---------------------------------------------------------------------
SELECT t.test_name,
       count(*)                                              AS results,
       count(*) FILTER (WHERE lr.abnormal_flag)              AS abnormal,
       round(100.0 * count(*) FILTER (WHERE lr.abnormal_flag) / count(*), 1) AS abnormal_pct
FROM lab_result lr
JOIN lab_request rq     ON rq.lab_request_id = lr.lab_request_id
JOIN lab_test_catalog t ON t.test_id = rq.test_id
GROUP BY t.test_name
ORDER BY abnormal_pct DESC;

-- ---------------------------------------------------------------------
-- Q10 ORDER BY with LIMIT
-- The ten busiest doctors in 2026 by completed appointments.
-- ---------------------------------------------------------------------
SELECT d.doctor_id, d.first_name || ' ' || d.last_name AS doctor,
       s.specialisation_name,
       count(*) AS completed_2026
FROM appointment a
JOIN doctor d         ON d.doctor_id = a.doctor_id
JOIN specialisation s ON s.specialisation_id = d.specialisation_id
WHERE a.status = 'COMPLETED' AND a.appointment_date >= date '2026-01-01'
GROUP BY d.doctor_id, doctor, s.specialisation_name
ORDER BY completed_2026 DESC, d.doctor_id
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q11 Date-range query for one doctor (a day sheet for a week)
-- ---------------------------------------------------------------------
SELECT a.appointment_date, a.start_time, a.status,
       p.first_name || ' ' || p.last_name AS patient, a.reason
FROM appointment a
JOIN patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 12
  AND a.appointment_date BETWEEN date '2026-10-12' AND date '2026-10-16'
  AND a.status <> 'CANCELLED'
ORDER BY a.appointment_date, a.start_time;

-- ---------------------------------------------------------------------
-- Q12 Selective filter on a status column
-- The laboratory work queue: urgent requests not yet completed.
-- ---------------------------------------------------------------------
SELECT rq.lab_request_id, t.test_name, rq.requested_at, rq.status
FROM lab_request rq
JOIN lab_test_catalog t ON t.test_id = rq.test_id
WHERE rq.status IN ('REQUESTED', 'COLLECTED')
  AND rq.priority = 'URGENT'
ORDER BY rq.requested_at
LIMIT 20;

-- ---------------------------------------------------------------------
-- Q13 Correlated NOT EXISTS (anti-join)
-- Patients with a hypertension history and no completed appointment
-- in the twelve months before today: candidates for a recall reminder.
-- ---------------------------------------------------------------------
SELECT count(*) AS patients_to_recall
FROM patient p
WHERE EXISTS (SELECT 1 FROM patient_medical_history h
              WHERE h.patient_id = p.patient_id
                AND h.condition_name = 'Hypertension')
  AND NOT EXISTS (SELECT 1 FROM appointment a
                  WHERE a.patient_id = p.patient_id
                    AND a.status = 'COMPLETED'
                    AND a.appointment_date >= date '2025-11-06'
                    AND a.appointment_date <  date '2026-11-06');

-- ---------------------------------------------------------------------
-- Q14 Window function with a CTE
-- The most prescribed medication within each specialisation.
-- ---------------------------------------------------------------------
WITH usage AS (
    SELECT s.specialisation_name, m.generic_name, count(*) AS times_prescribed
    FROM prescription_item pi
    JOIN prescription pr  ON pr.prescription_id = pi.prescription_id
    JOIN consultation c   ON c.consultation_id  = pr.consultation_id
    JOIN appointment a    ON a.appointment_id   = c.appointment_id
    JOIN doctor d         ON d.doctor_id        = a.doctor_id
    JOIN specialisation s ON s.specialisation_id = d.specialisation_id
    JOIN medication m     ON m.medication_id    = pi.medication_id
    GROUP BY s.specialisation_name, m.generic_name
), ranked AS (
    SELECT *, rank() OVER (PARTITION BY specialisation_name
                           ORDER BY times_prescribed DESC) AS rnk
    FROM usage
)
SELECT specialisation_name, generic_name, times_prescribed
FROM ranked
WHERE rnk = 1
ORDER BY specialisation_name;

-- ---------------------------------------------------------------------
-- Q15 SUM and AVG
-- Treatment duration per medication: how many drug-days were prescribed
-- in total and how long a typical course is.
-- ---------------------------------------------------------------------
SELECT m.generic_name, m.form,
       count(*)                      AS prescriptions,
       sum(pi.duration_days)         AS total_drug_days,
       round(avg(pi.duration_days), 1) AS avg_course_days
FROM prescription_item pi
JOIN medication m ON m.medication_id = pi.medication_id
GROUP BY m.generic_name, m.form
ORDER BY total_drug_days DESC;
