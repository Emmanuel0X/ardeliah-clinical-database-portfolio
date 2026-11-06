# Query Results: Ardeliah Clinical System

Every result below is real output from `psql` on PostgreSQL 16.15, run against the data produced by `seed-bulk-data.sql` (20,003 patients, 185,304 appointments, 145,954 consultations, 58,362 lab requests). The data is synthetic and deterministic, so you will get identical rows if you rebuild it. "Today" is fixed at 2026-11-06 in the queries so the results are reproducible.

Because the data generator picks values with a hash rather than from real clinical patterns, some outputs look arbitrary (for example, which drug is most prescribed in which specialty). What matters for this portfolio is that the queries are correct and that the plans and timings are real.


## Q1: Simple SELECT with WHERE and ORDER BY

Reception searches for a patient by name.

```sql
SELECT patient_id, first_name, last_name, date_of_birth, phone
FROM patient
WHERE last_name = 'Okeke' AND first_name = 'Chinedu'
ORDER BY date_of_birth
LIMIT 10;
```

Output:

```
 patient_id | first_name | last_name | date_of_birth |    phone    
------------+------------+-----------+---------------+-------------
        640 | Chinedu    | Okeke     | 1950-03-10    | 08022465629
       2892 | Chinedu    | Okeke     | 1950-03-11    | 08030165534
       8933 | Chinedu    | Okeke     | 1953-11-18    | 08049503737
      18089 | Chinedu    | Okeke     | 1954-04-01    | 08003195115
      12592 | Chinedu    | Okeke     | 1956-11-12    | 08035415019
       2317 | Chinedu    | Okeke     | 1957-04-14    | 08061767498
      17058 | Chinedu    | Okeke     | 1964-04-26    | 08073603662
       8959 | Chinedu    | Okeke     | 1965-04-25    | 08009600114
       2266 | Chinedu    | Okeke     | 1968-12-23    | 08037442508
       2053 | Chinedu    | Okeke     | 1972-10-20    | 08055723113
(10 rows)
```


## Q2: INNER JOIN across three tables

A patient's most recent appointments with doctor and specialisation.

```sql
SELECT a.appointment_date, a.start_time, a.status,
       d.first_name || ' ' || d.last_name AS doctor,
       s.specialisation_name
FROM appointment a
JOIN doctor d          ON d.doctor_id = a.doctor_id
JOIN specialisation s  ON s.specialisation_id = d.specialisation_id
WHERE a.patient_id = 7421
ORDER BY a.appointment_date DESC, a.start_time
LIMIT 10;
```

Output:

```
 appointment_date | start_time |  status   |      doctor      |    specialisation_name     
------------------+------------+-----------+------------------+----------------------------
 2026-11-17       | 14:00:00   | CANCELLED | Grace Adamu      | Obstetrics and Gynaecology
 2026-09-29       | 15:30:00   | CANCELLED | Kunle Umoh       | General Practice
 2026-06-10       | 13:00:00   | COMPLETED | Daniel Akinola   | General Practice
 2026-04-07       | 12:00:00   | CANCELLED | Hadiza Eke       | Dermatology
 2025-12-25       | 09:30:00   | COMPLETED | Linda Umoh       | Ophthalmology
 2025-09-23       | 13:00:00   | COMPLETED | Victor Nwachukwu | Obstetrics and Gynaecology
 2025-07-07       | 09:30:00   | COMPLETED | Linda Umoh       | Internal Medicine
 2025-01-07       | 13:30:00   | NO_SHOW   | Daniel Okoro     | Cardiology
 2024-08-02       | 11:00:00   | COMPLETED | Tayo Adamu       | Dermatology
(9 rows)
```


## Q3: LEFT JOIN

Patients with NO completed appointment on record. The LEFT JOIN keeps every patient; those with no match show NULL on the appointment side.

```sql
SELECT p.patient_id, p.first_name, p.last_name, p.date_of_birth
FROM patient p
LEFT JOIN appointment a
       ON a.patient_id = p.patient_id AND a.status = 'COMPLETED'
WHERE a.appointment_id IS NULL
ORDER BY p.patient_id
LIMIT 10;
```

Output:

```
 patient_id | first_name | last_name | date_of_birth 
------------+------------+-----------+---------------
          2 | Tunde      | Bakare    | 1984-11-02
          3 | Halima     | Sani      | 1975-07-21
        522 | Fatima     | Mohammed  | 1972-02-04
       3411 | Folake     | Garba     | 1996-02-13
       3492 | Amaka      | Abubakar  | 1996-07-07
       4406 | Chinedu    | Nwosu     | 1994-11-17
       4873 | Fatima     | Afolabi   | 1964-08-25
       6330 | Rashida    | Adekunle  | 1973-08-23
       9290 | Aisha      | Suleiman  | 1995-06-18
      10427 | Obinna     | Ajayi     | 1968-11-09
(10 rows)
```


## Q4: Multi-table JOIN (six tables)

Full prescription history for one patient, with drug details.

```sql
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
```

Output:

```
 appointment_date |  generic_name  | strength |  form   |    dosage    |     frequency     | duration_days | prescription_status 
------------------+----------------+----------+---------+--------------+-------------------+---------------+---------------------
 2026-06-10       | Amlodipine     | 5 mg     | tablet  | 1 tablet     | once daily        |             3 | DISPENSED
 2026-06-10       | Paracetamol    | 500 mg   | tablet  | 1 tablet     | twice daily       |            10 | DISPENSED
 2025-09-23       | Paracetamol    | 500 mg   | tablet  | 2 tablets    | three times daily |             5 | DISPENSED
 2024-08-02       | Hydrocortisone | 1%       | cream   | apply thinly | twice daily       |             7 | DISPENSED
 2024-08-02       | Salbutamol     | 100 mcg  | inhaler | 2 puffs      | once daily        |            13 | DISPENSED
(5 rows)
```


## Q5: GROUP BY with HAVING

ICD codes recorded as SEVERE at least 4,050 times. The threshold sits inside the spread of the data, so HAVING removes some groups and keeps others.

```sql
SELECT i.icd_code, i.description,
       count(*) AS severe_diagnoses
FROM diagnosis dg
JOIN icd_code i ON i.icd_code = dg.icd_code
WHERE dg.severity = 'SEVERE'
GROUP BY i.icd_code, i.description
HAVING count(*) >= 4050
ORDER BY severe_diagnoses DESC;
```

Output:

```
 icd_code |                 description                 | severe_diagnoses 
----------+---------------------------------------------+------------------
 I10      | Essential (primary) hypertension            |             4127
 A09      | Infectious gastroenteritis and colitis      |             4116
 B50.9    | Plasmodium falciparum malaria, unspecified  |             4103
 K29.7    | Gastritis, unspecified                      |             4060
 N39.0    | Urinary tract infection, site not specified |             4059
(5 rows)
```


## Q6: Aggregation over time with FILTER

Appointment outcomes per month for the last six months before today.

```sql
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
```

Output:

```
   month    | total | completed | cancelled | no_show | no_show_pct 
------------+-------+-----------+-----------+---------+-------------
 2026-05-01 |  6062 |      4858 |       608 |     596 |         9.8
 2026-06-01 |  6279 |      5043 |       636 |     600 |         9.6
 2026-07-01 |  6680 |      5361 |       625 |     694 |        10.4
 2026-08-01 |  5954 |      4688 |       620 |     646 |        10.8
 2026-09-01 |  6345 |      5081 |       624 |     640 |        10.1
 2026-10-01 |  6377 |      5067 |       646 |     664 |        10.4
(6 rows)
```


## Q7: Non-correlated subquery (IN)

Patients diagnosed with malaria (B50.9) since 1 October 2026. The inner query runs once and produces a list of patient ids.

```sql
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
```

Output:

```
 patient_id | first_name | last_name 
------------+------------+-----------
          1 | Adaeze     | Okafor
         23 | Amaka      | Onyeama
         44 | Hauwa      | Hassan
         71 | Oluwaseun  | Hassan
        117 | Maryam     | Mohammed
        175 | Nneka      | Ogunleye
        236 | Ngozi      | Ugwu
        300 | Kelechi    | Chukwu
        325 | Yusuf      | Ugwu
        336 | Damilola   | Olawale
        396 | Joy        | Lawal
        414 | Nneka      | Bello
        447 | Amaka      | Hassan
        489 | Uche       | Afolabi
        509 | Musa       | Obi
(15 rows)
```


## Q8: Correlated subquery

Each patient's most recent completed appointment, for patients 4-13. The inner query is evaluated in the context of every outer row.

```sql
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
```

Output:

```
 patient_id | appointment_date | start_time | doctor_id 
------------+------------------+------------+-----------
          4 | 2026-06-18       | 14:30:00   |        23
          5 | 2026-08-31       | 13:00:00   |        14
          6 | 2026-03-19       | 12:30:00   |        17
          7 | 2026-10-19       | 14:30:00   |         9
          8 | 2026-04-06       | 12:30:00   |         3
          9 | 2026-10-20       | 09:30:00   |        15
         10 | 2026-08-17       | 11:30:00   |        27
         11 | 2026-08-18       | 11:00:00   |        38
         12 | 2026-09-16       | 14:30:00   |        21
         13 | 2026-11-03       | 11:00:00   |        15
(10 rows)
```


## Q9: Aggregate with COUNT and a calculated percentage

Share of abnormal results per laboratory test.

```sql
SELECT t.test_name,
       count(*)                                              AS results,
       count(*) FILTER (WHERE lr.abnormal_flag)              AS abnormal,
       round(100.0 * count(*) FILTER (WHERE lr.abnormal_flag) / count(*), 1) AS abnormal_pct
FROM lab_result lr
JOIN lab_request rq     ON rq.lab_request_id = lr.lab_request_id
JOIN lab_test_catalog t ON t.test_id = rq.test_id
GROUP BY t.test_name
ORDER BY abnormal_pct DESC;
```

Output:

```
          test_name          | results | abnormal | abnormal_pct 
-----------------------------+---------+----------+--------------
 Urinalysis: leucocytes      |    7276 |     2434 |         33.5
 Haemoglobin                 |    7281 |     2389 |         32.8
 Fasting blood glucose       |    7224 |     2346 |         32.5
 White blood cell count      |    7340 |     2354 |         32.1
 Serum creatinine            |    7159 |     2291 |         32.0
 Total cholesterol           |    7361 |     2343 |         31.8
 Widal titre (O antigen)     |    7256 |     2297 |         31.7
 Malaria parasite (MP) count |    7109 |     1314 |         18.5
(8 rows)
```


## Q10: ORDER BY with LIMIT

The ten busiest doctors in 2026 by completed appointments.

```sql
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
```

Output:

```
 doctor_id |     doctor     | specialisation_name | completed_2026 
-----------+----------------+---------------------+----------------
        24 | Peter Akinola  | Orthopaedics        |           1322
        12 | Kunle Umoh     | General Practice    |           1318
        21 | Hadiza Umoh    | General Practice    |           1312
        18 | Linda Umoh     | Internal Medicine   |           1301
         9 | Tayo Nwachukwu | Internal Medicine   |           1299
        35 | Daniel Adamu   | Ophthalmology       |           1294
        14 | Sola Nwachukwu | General Practice    |           1292
        27 | Daniel Akinola | General Practice    |           1291
        38 | Kunle Umoh     | Orthopaedics        |           1290
        33 | Hadiza Adamu   | Cardiology          |           1284
(10 rows)
```


## Q11: Date-range query for one doctor (a day sheet for a week)

```sql
SELECT a.appointment_date, a.start_time, a.status,
       p.first_name || ' ' || p.last_name AS patient, a.reason
FROM appointment a
JOIN patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 12
  AND a.appointment_date BETWEEN date '2026-10-12' AND date '2026-10-16'
  AND a.status <> 'CANCELLED'
ORDER BY a.appointment_date, a.start_time;
```

Output:

```
 appointment_date | start_time |  status   |      patient      |       reason       
------------------+------------+-----------+-------------------+--------------------
 2026-10-12       | 09:30:00   | COMPLETED | Yusuf Okeke       | Child immunisation
 2026-10-12       | 11:00:00   | NO_SHOW   | Tolu Hassan       | Skin rash
 2026-10-12       | 13:00:00   | NO_SHOW   | Fatima Ibekwe     | Fever and headache
 2026-10-12       | 13:30:00   | NO_SHOW   | Abdullahi Afolabi | Antenatal visit
 2026-10-12       | 14:00:00   | COMPLETED | Temitope Chukwu   | Back pain
 2026-10-12       | 15:00:00   | COMPLETED | Rashida Balogun   | Cough and catarrh
 2026-10-13       | 09:00:00   | COMPLETED | Aisha Salako      | Abdominal pain
 2026-10-13       | 12:30:00   | NO_SHOW   | Fatima Afolabi    | Routine check-up
 2026-10-13       | 13:00:00   | COMPLETED | Abdullahi Chukwu  | Back pain
 2026-10-13       | 14:00:00   | COMPLETED | Amaka Kalu        | Abdominal pain
 2026-10-14       | 08:00:00   | COMPLETED | Rashida Nwosu     | Antenatal visit
 2026-10-14       | 08:30:00   | COMPLETED | Ngozi Fashola     | Diabetes follow-up
 2026-10-14       | 09:30:00   | COMPLETED | Fatima Adekunle   | Antenatal visit
 2026-10-14       | 10:30:00   | COMPLETED | Uche Usman        | Abdominal pain
 2026-10-14       | 11:00:00   | COMPLETED | Tolu Mohammed     | Routine check-up
 2026-10-14       | 12:00:00   | COMPLETED | Amaka Obi         | Cough and catarrh
 2026-10-14       | 14:30:00   | COMPLETED | Segun Balogun     | Abdominal pain
 2026-10-15       | 08:00:00   | COMPLETED | Amaka Adekunle    | Diabetes follow-up
 2026-10-15       | 08:30:00   | COMPLETED | Musa Obi          | Abdominal pain
 2026-10-15       | 09:00:00   | NO_SHOW   | Aisha Usman       | Cough and catarrh
 2026-10-16       | 08:30:00   | COMPLETED | Obinna Olawale    | Skin rash
 2026-10-16       | 09:30:00   | COMPLETED | Yusuf Chukwu      | Cough and catarrh
 2026-10-16       | 10:00:00   | COMPLETED | Bukola Ibekwe     | Cough and catarrh
 2026-10-16       | 10:30:00   | COMPLETED | Bukola Obi        | Abdominal pain
 2026-10-16       | 11:00:00   | COMPLETED | Rashida Suleiman  | Routine check-up
 2026-10-16       | 12:00:00   | COMPLETED | Joy Kalu          | Fever and headache
 2026-10-16       | 13:00:00   | COMPLETED | Zainab Lawal      | Back pain
 2026-10-16       | 14:30:00   | COMPLETED | Ifeanyi Balogun   | Fever and headache
 2026-10-16       | 15:00:00   | COMPLETED | Obinna Afolabi    | Routine check-up
(29 rows)
```


## Q12: Selective filter on a status column

The laboratory work queue: urgent requests not yet completed.

```sql
SELECT rq.lab_request_id, t.test_name, rq.requested_at, rq.status
FROM lab_request rq
JOIN lab_test_catalog t ON t.test_id = rq.test_id
WHERE rq.status IN ('REQUESTED', 'COLLECTED')
  AND rq.priority = 'URGENT'
ORDER BY rq.requested_at
LIMIT 20;
```

Output:

```
 lab_request_id |          test_name          |      requested_at      |  status   
----------------+-----------------------------+------------------------+-----------
          40941 | Widal titre (O antigen)     | 2026-10-15 11:15:00+01 | COLLECTED
          20631 | Fasting blood glucose       | 2026-10-15 13:15:00+01 | REQUESTED
          53522 | Total cholesterol           | 2026-10-19 08:15:00+01 | COLLECTED
          21556 | Fasting blood glucose       | 2026-10-19 09:15:00+01 | REQUESTED
          33688 | White blood cell count      | 2026-10-19 09:45:00+01 | COLLECTED
           7038 | Malaria parasite (MP) count | 2026-10-19 14:45:00+01 | COLLECTED
          14560 | Fasting blood glucose       | 2026-10-19 15:15:00+01 | COLLECTED
          28830 | Serum creatinine            | 2026-10-20 15:45:00+01 | REQUESTED
          49898 | Urinalysis: leucocytes      | 2026-10-21 12:45:00+01 | REQUESTED
          41852 | Widal titre (O antigen)     | 2026-10-22 10:15:00+01 | COLLECTED
          44470 | Urinalysis: leucocytes      | 2026-10-23 09:15:00+01 | COLLECTED
          55361 | Total cholesterol           | 2026-10-23 11:45:00+01 | REQUESTED
          45249 | Urinalysis: leucocytes      | 2026-10-26 08:45:00+01 | COLLECTED
          28868 | Serum creatinine            | 2026-10-26 10:15:00+01 | REQUESTED
          31432 | White blood cell count      | 2026-10-26 12:45:00+01 | COLLECTED
          42436 | Widal titre (O antigen)     | 2026-10-26 14:15:00+01 | COLLECTED
          17324 | Fasting blood glucose       | 2026-10-26 15:15:00+01 | COLLECTED
          17347 | Fasting blood glucose       | 2026-10-26 15:45:00+01 | REQUESTED
          56687 | Total cholesterol           | 2026-10-27 11:15:00+01 | REQUESTED
          43065 | Widal titre (O antigen)     | 2026-10-28 09:45:00+01 | COLLECTED
(20 rows)
```


## Q13: Correlated NOT EXISTS (anti-join)

Patients with a hypertension history and no completed appointment in the twelve months before today: candidates for a recall reminder.

```sql
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
```

Output:

```
 patients_to_recall 
--------------------
                 46
(1 row)
```


## Q14: Window function with a CTE

The most prescribed medication within each specialisation.

```sql
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
```

Output:

```
    specialisation_name     |      generic_name       | times_prescribed 
----------------------------+-------------------------+------------------
 Cardiology                 | Omeprazole              |             1833
 Dermatology                | Ibuprofen               |             1792
 General Practice           | Oral rehydration salts  |             2105
 Internal Medicine          | Artemether/Lumefantrine |             1486
 Obstetrics and Gynaecology | Amlodipine              |             2100
 Ophthalmology              | Ibuprofen               |              923
 Orthopaedics               | Metformin               |             1536
 Paediatrics                | Ibuprofen               |              317
(8 rows)
```


## Q15: SUM and AVG

Treatment duration per medication: how many drug-days were prescribed in total and how long a typical course is.

```sql
SELECT m.generic_name, m.form,
       count(*)                      AS prescriptions,
       sum(pi.duration_days)         AS total_drug_days,
       round(avg(pi.duration_days), 1) AS avg_course_days
FROM prescription_item pi
JOIN medication m ON m.medication_id = pi.medication_id
GROUP BY m.generic_name, m.form
ORDER BY total_drug_days DESC;
```

Output:

```
      generic_name       |  form   | prescriptions | total_drug_days | avg_course_days 
-------------------------+---------+---------------+-----------------+-----------------
 Omeprazole              | capsule |         11789 |          100653 |             8.5
 Hydrocortisone          | cream   |         11836 |          100508 |             8.5
 Amlodipine              | tablet  |         11720 |          100181 |             8.5
 Ibuprofen               | tablet  |         11773 |           99630 |             8.5
 Metformin               | tablet  |         11735 |           99427 |             8.5
 Paracetamol             | tablet  |         11633 |           98812 |             8.5
 Artemether/Lumefantrine | tablet  |         11596 |           98774 |             8.5
 Oral rehydration salts  | sachet  |         11639 |           98695 |             8.5
 Amoxicillin             | capsule |         11541 |           97607 |             8.5
 Ferrous sulphate        | tablet  |         11511 |           97332 |             8.5
 Salbutamol              | inhaler |         11508 |           97329 |             8.5
 Ciprofloxacin           | tablet  |         11405 |           97196 |             8.5
(12 rows)
```
