-- =====================================================================
-- Ardeliah Clinical System: reference data and a small worked example
-- Run AFTER create-tables.sql:  psql -d ardeliah -f sample-data.sql
--
-- Part A loads reference/lookup data that Portfolio 2 also relies on.
-- Part B loads a handful of people and one full clinical workflow
-- (appointment -> consultation -> diagnosis -> prescription -> lab
-- request -> lab result) so every table can be shown with real rows.
-- IDs rely on a freshly created schema (identity columns start at 1).
-- =====================================================================
SET search_path TO ardeliah;

-- ---------------------- Part A: reference data -----------------------
INSERT INTO role (role_name) VALUES
 ('PATIENT'), ('DOCTOR'), ('RECEPTIONIST'), ('LAB_TECHNICIAN'), ('ADMIN');

INSERT INTO specialisation (specialisation_name) VALUES
 ('General Practice'), ('Paediatrics'), ('Obstetrics and Gynaecology'),
 ('Internal Medicine'), ('Cardiology'), ('Dermatology'),
 ('Ophthalmology'), ('Orthopaedics');

INSERT INTO icd_code (icd_code, description) VALUES
 ('B50.9', 'Plasmodium falciparum malaria, unspecified'),
 ('A01.0', 'Typhoid fever'),
 ('I10',   'Essential (primary) hypertension'),
 ('E11.9', 'Type 2 diabetes mellitus without complications'),
 ('J06.9', 'Acute upper respiratory infection, unspecified'),
 ('J45.9', 'Asthma, unspecified'),
 ('K29.7', 'Gastritis, unspecified'),
 ('N39.0', 'Urinary tract infection, site not specified'),
 ('D64.9', 'Anaemia, unspecified'),
 ('M54.5', 'Low back pain'),
 ('L20.9', 'Atopic dermatitis, unspecified'),
 ('A09',   'Infectious gastroenteritis and colitis');

INSERT INTO medication (generic_name, form, strength) VALUES
 ('Artemether/Lumefantrine', 'tablet',   '20/120 mg'),
 ('Paracetamol',             'tablet',   '500 mg'),
 ('Amoxicillin',             'capsule',  '500 mg'),
 ('Amlodipine',              'tablet',   '5 mg'),
 ('Metformin',               'tablet',   '500 mg'),
 ('Salbutamol',              'inhaler',  '100 mcg'),
 ('Omeprazole',              'capsule',  '20 mg'),
 ('Ciprofloxacin',           'tablet',   '500 mg'),
 ('Ferrous sulphate',        'tablet',   '200 mg'),
 ('Ibuprofen',               'tablet',   '400 mg'),
 ('Hydrocortisone',          'cream',    '1%'),
 ('Oral rehydration salts',  'sachet',   '20.5 g');

INSERT INTO lab_test_catalog (test_name, unit, ref_range_low, ref_range_high) VALUES
 ('Malaria parasite (MP) count',  'parasites/uL', 0,    0),
 ('Haemoglobin',                  'g/dL',         12.0, 17.5),
 ('Fasting blood glucose',        'mmol/L',       3.9,  5.6),
 ('Serum creatinine',             'umol/L',       60,   110),
 ('White blood cell count',       'x10^9/L',      4.0,  11.0),
 ('Widal titre (O antigen)',      'titre',        0,    80),
 ('Urinalysis: leucocytes',       '/HPF',         0,    5),
 ('Total cholesterol',            'mmol/L',       0,    5.2);

-- ---------------------- Part B: people and one workflow --------------
-- User accounts (hashes are placeholders, not real credentials).
INSERT INTO app_user (username, password_hash, role_id) VALUES
 ('adaeze.okafor',   'x$placeholder-hash-01', 1),   -- user 1: patient
 ('tunde.bakare',    'x$placeholder-hash-02', 1),   -- user 2: patient
 ('dr.ibrahim',      'x$placeholder-hash-03', 2),   -- user 3: doctor
 ('dr.eze',          'x$placeholder-hash-04', 2),   -- user 4: doctor
 ('reception.ngozi', 'x$placeholder-hash-05', 3),   -- user 5: receptionist
 ('lab.segun',       'x$placeholder-hash-06', 4),   -- user 6: lab technician
 ('admin.clinic',    'x$placeholder-hash-07', 5);   -- user 7: admin

INSERT INTO patient (user_id, first_name, last_name, date_of_birth, gender, phone, email, address, blood_group) VALUES
 (1,    'Adaeze',  'Okafor',  '1991-03-14', 'F', '08031234567', 'adaeze.okafor@example.com',  'Garki, Abuja',   'O+'),
 (2,    'Tunde',   'Bakare',  '1984-11-02', 'M', '08059876543', 'tunde.bakare@example.com',   'Wuse II, Abuja', 'A+'),
 (NULL, 'Halima',  'Sani',    '1975-07-21', 'F', '08027654321', NULL,                         'Kubwa, Abuja',   'B+');  -- walk-in, no portal login

INSERT INTO patient_medical_history (patient_id, condition_name, noted_on, notes) VALUES
 (2, 'Hypertension',         '2022-05-10', 'On amlodipine since diagnosis'),
 (2, 'Penicillin allergy',   '2019-01-15', 'Rash after amoxicillin'),
 (3, 'Type 2 diabetes',      '2020-09-01', 'Managed with metformin');

INSERT INTO doctor (user_id, first_name, last_name, specialisation_id, licence_no, phone) VALUES
 (3, 'Aminu', 'Ibrahim', 1, 'MDCN-100234', '08011112222'),
 (4, 'Chiamaka', 'Eze',  4, 'MDCN-100871', '08033334444');

INSERT INTO doctor_schedule (doctor_id, day_of_week, start_time, end_time) VALUES
 (1, 1, '08:00', '16:00'), (1, 2, '08:00', '16:00'), (1, 3, '08:00', '16:00'),
 (2, 2, '09:00', '17:00'), (2, 4, '09:00', '17:00');

INSERT INTO staff (user_id, first_name, last_name, staff_type, phone) VALUES
 (5, 'Ngozi', 'Umeh',  'RECEPTIONIST',   '08055556666'),   -- staff 1
 (6, 'Segun', 'Adebayo', 'LAB_TECHNICIAN', '08077778888');  -- staff 2

-- Three appointments: one completed (full workflow), one scheduled, one cancelled.
INSERT INTO appointment (patient_id, doctor_id, booked_by_staff_id, appointment_date, start_time, status, reason) VALUES
 (1, 1, 1,    '2026-10-20', '09:00', 'COMPLETED', 'Fever and headache for three days'),
 (2, 2, NULL, '2026-11-10', '10:00', 'SCHEDULED', 'Blood pressure review'),
 (3, 1, 1,    '2026-10-22', '11:30', 'CANCELLED', 'Diabetes follow-up');

-- Consultation for the completed appointment, with diagnosis, prescription
-- and a lab request/result.
INSERT INTO consultation (appointment_id, clinical_notes, consulted_at) VALUES
 (1, 'Febrile, temp 38.6C, no neck stiffness. Chills and bodyache. Malaria parasite test ordered.', '2026-10-20 09:10+01');

INSERT INTO diagnosis (consultation_id, icd_code, severity, notes) VALUES
 (1, 'B50.9', 'MODERATE', 'Confirmed by MP test');

INSERT INTO prescription (consultation_id, issued_at, status) VALUES
 (1, '2026-10-20 09:40+01', 'ISSUED');

INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days) VALUES
 (1, 1, '4 tablets', 'twice daily', 3),
 (1, 2, '2 tablets', 'every 6 hours as needed', 3);

INSERT INTO lab_request (consultation_id, test_id, requested_at, priority, status) VALUES
 (1, 1, '2026-10-20 09:15+01', 'URGENT', 'COMPLETED');

INSERT INTO lab_result (lab_request_id, technician_id, result_value, result_comment, abnormal_flag, recorded_at) VALUES
 (1, 2, 2400, 'P. falciparum trophozoites seen', TRUE, '2026-10-20 09:35+01');

INSERT INTO audit_log (table_name, action, record_id, performed_by, details) VALUES
 ('appointment', 'INSERT', 1, 5, 'Booked by receptionist for patient 1');
