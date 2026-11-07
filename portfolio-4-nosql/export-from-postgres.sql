-- =====================================================================
-- Ardeliah Clinical System: relational to document export
-- Portfolio 4: NoSQL and Advanced Data Models
--
-- Reads the PostgreSQL database built in Portfolios 1 and 2 and writes
-- newline-delimited JSON (one document per line) into ./data/, ready for
-- mongoimport. This is the "mapping" from the 19-table relational design
-- to the 9-collection document design described in nosql-model.md.
--
-- Run from inside portfolio-4-nosql/ :
--     mkdir -p data
--     psql -X -d ardeliah -f export-from-postgres.sql
--
-- Scope: a sample of patients 1..:maxpid and everything that belongs to
-- them (so the files stay small enough for a Git repository). Change the
-- number below to export more; the full database would be about 60 MB.
--
-- Dates are written as MongoDB Extended JSON {"$date": "..."} so that
-- mongoimport stores real BSON dates instead of strings.
-- Fields whose value is NULL are left out (json_strip_nulls), which is
-- the normal document-database way of saying "no value".
-- =====================================================================
\set maxpid 303
\pset tuples_only on
\pset format unaligned
SET search_path TO ardeliah;

CREATE FUNCTION pg_temp.d(ts timestamptz) RETURNS json LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN ts IS NULL THEN NULL
               ELSE json_build_object('$date', to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')) END $$;

CREATE FUNCTION pg_temp.dd(dt date) RETURNS json LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN dt IS NULL THEN NULL
               ELSE json_build_object('$date', to_char(dt, 'YYYY-MM-DD') || 'T00:00:00Z') END $$;

-- ---------------------------------------------------------------------
-- patients: demographics, contact details and medical history in ONE
-- document. History is always read with the patient, so it is embedded.
-- ---------------------------------------------------------------------
\o data/patients.ndjson
SELECT json_strip_nulls(json_build_object(
  '_id', p.patient_id,
  'first_name', p.first_name,
  'last_name', p.last_name,
  'date_of_birth', pg_temp.dd(p.date_of_birth),
  'gender', p.gender,
  'blood_group', p.blood_group,
  'contact', json_build_object('phone', p.phone, 'email', p.email, 'address', p.address),
  'registered_on', pg_temp.dd(p.registered_on),
  'medical_history', coalesce((
      SELECT json_agg(json_build_object('condition', h.condition_name,
                                        'noted_on', pg_temp.dd(h.noted_on),
                                        'notes', h.notes) ORDER BY h.history_id)
      FROM patient_medical_history h WHERE h.patient_id = p.patient_id), '[]'::json)
))::text
FROM patient p
WHERE p.patient_id <= :maxpid
ORDER BY p.patient_id;

-- ---------------------------------------------------------------------
-- doctors: profile, specialisation name and weekly schedule embedded.
-- ---------------------------------------------------------------------
\o data/doctors.ndjson
SELECT json_strip_nulls(json_build_object(
  '_id', d.doctor_id,
  'first_name', d.first_name,
  'last_name', d.last_name,
  'licence_no', d.licence_no,
  'phone', d.phone,
  'specialisation', s.specialisation_name,
  'schedule', coalesce((
      SELECT json_agg(json_build_object('day_of_week', ds.day_of_week,
                                        'start', to_char(ds.start_time, 'HH24:MI'),
                                        'end',   to_char(ds.end_time,   'HH24:MI'))
                      ORDER BY ds.day_of_week, ds.start_time)
      FROM doctor_schedule ds WHERE ds.doctor_id = d.doctor_id), '[]'::json)
))::text
FROM doctor d JOIN specialisation s USING (specialisation_id)
ORDER BY d.doctor_id;

-- ---------------------------------------------------------------------
-- appointments: referenced by patient_id and doctor_id, plus a copy of
-- the two names ("extended reference" pattern) so the appointment list
-- screen needs no lookups. Date and time are merged into one instant.
-- slot_active is false for cancelled appointments. MongoDB partial
-- indexes cannot say "status is not CANCELLED" (the relational index in
-- Portfolio 1 does), but they can test slot_active = true, which gives the
-- same double-booking protection. Cancelling must set both fields.
-- ---------------------------------------------------------------------
\o data/appointments.ndjson
SELECT json_strip_nulls(json_build_object(
  '_id', a.appointment_id,
  'patient_id', a.patient_id,
  'patient_name', p.first_name || ' ' || p.last_name,
  'doctor_id', a.doctor_id,
  'doctor_name', 'Dr ' || d.first_name || ' ' || d.last_name,
  'scheduled_at', pg_temp.d((a.appointment_date + a.start_time) AT TIME ZONE 'Africa/Lagos'),
  'status', a.status,
  'slot_active', (a.status <> 'CANCELLED'),
  'reason', a.reason,
  'booked_by_staff_id', a.booked_by_staff_id
))::text
FROM appointment a
JOIN patient p USING (patient_id)
JOIN doctor d  USING (doctor_id)
WHERE a.patient_id <= :maxpid
ORDER BY a.appointment_id;

-- ---------------------------------------------------------------------
-- consultations: the clinical "aggregate". Diagnoses, prescriptions (with
-- their drug lines) and lab requests (with their results) are embedded,
-- because they are created during, and read together with, the visit.
-- Names and strengths of drugs and tests are copied in as they were at
-- the time (a snapshot, which is what a medical record should keep).
-- patient_id and doctor_id are repeated so a patient's whole history can
-- be queried from this one collection.
-- ---------------------------------------------------------------------
\o data/consultations.ndjson
SELECT json_strip_nulls(json_build_object(
  '_id', c.consultation_id,
  'appointment_id', c.appointment_id,
  'patient_id', a.patient_id,
  'doctor_id', a.doctor_id,
  'consulted_at', pg_temp.d(c.consulted_at),
  'clinical_notes', c.clinical_notes,
  'diagnoses', coalesce((
      SELECT json_agg(json_build_object('icd_code', dg.icd_code,
                                        'description', i.description,
                                        'severity', dg.severity,
                                        'notes', dg.notes) ORDER BY dg.diagnosis_id)
      FROM diagnosis dg JOIN icd_code i ON i.icd_code = dg.icd_code
      WHERE dg.consultation_id = c.consultation_id), '[]'::json),
  'prescriptions', coalesce((
      SELECT json_agg(json_build_object(
               'prescription_id', pr.prescription_id,
               'issued_at', pg_temp.d(pr.issued_at),
               'status', pr.status,
               'items', (SELECT json_agg(json_build_object(
                                  'medication', json_build_object('generic_name', m.generic_name,
                                                                  'form', m.form,
                                                                  'strength', m.strength),
                                  'dosage', pi.dosage,
                                  'frequency', pi.frequency,
                                  'duration_days', pi.duration_days) ORDER BY pi.medication_id)
                         FROM prescription_item pi JOIN medication m USING (medication_id)
                         WHERE pi.prescription_id = pr.prescription_id)
             ) ORDER BY pr.prescription_id)
      FROM prescription pr WHERE pr.consultation_id = c.consultation_id), '[]'::json),
  'lab_requests', coalesce((
      SELECT json_agg(json_build_object(
               'lab_request_id', lr.lab_request_id,
               'test', json_build_object('name', t.test_name, 'unit', t.unit),
               'priority', lr.priority,
               'status', lr.status,
               'requested_at', pg_temp.d(lr.requested_at),
               'result', CASE WHEN res.lab_result_id IS NULL THEN NULL
                              ELSE json_build_object('value', res.result_value,
                                                     'abnormal', res.abnormal_flag,
                                                     'comment', res.result_comment,
                                                     'recorded_at', pg_temp.d(res.recorded_at),
                                                     'technician_id', res.technician_id) END
             ) ORDER BY lr.lab_request_id)
      FROM lab_request lr
      JOIN lab_test_catalog t ON t.test_id = lr.test_id
      LEFT JOIN lab_result res ON res.lab_request_id = lr.lab_request_id
      WHERE lr.consultation_id = c.consultation_id), '[]'::json)
))::text
FROM consultation c
JOIN appointment a USING (appointment_id)
WHERE a.patient_id <= :maxpid
ORDER BY c.consultation_id;

-- ---------------------------------------------------------------------
-- Small reference collections (referenced, not embedded: shared by many
-- documents and edited in one place) and the user directory.
-- ---------------------------------------------------------------------
\o data/icd_codes.ndjson
SELECT json_build_object('_id', icd_code, 'description', description)::text
FROM icd_code ORDER BY icd_code;

\o data/medications.ndjson
SELECT json_build_object('_id', medication_id, 'generic_name', generic_name,
                         'form', form, 'strength', strength)::text
FROM medication ORDER BY medication_id;

\o data/lab_tests.ndjson
SELECT json_strip_nulls(json_build_object('_id', test_id, 'name', test_name, 'unit', unit,
       'ref_range', json_build_object('low', ref_range_low, 'high', ref_range_high)))::text
FROM lab_test_catalog ORDER BY test_id;

\o data/staff.ndjson
SELECT json_strip_nulls(json_build_object('_id', staff_id, 'first_name', first_name,
       'last_name', last_name, 'staff_type', staff_type))::text
FROM staff ORDER BY staff_id;

\o data/users.ndjson
SELECT json_build_object('_id', u.user_id, 'username', u.username, 'role', r.role_name,
                         'is_active', u.is_active, 'password_hash', u.password_hash)::text
FROM app_user u JOIN role r USING (role_id) ORDER BY u.user_id;

\o
