-- Removes the indexes created by indexing-strategy.sql so the baseline
-- ("before") benchmark can be reproduced. Constraint indexes from
-- Portfolio 1 are not touched.
SET search_path TO ardeliah;
DROP INDEX IF EXISTS idx_patient_name;
DROP INDEX IF EXISTS idx_appointment_patient_date;
DROP INDEX IF EXISTS idx_prescription_consultation;
DROP INDEX IF EXISTS idx_lab_request_pending;
DROP INDEX IF EXISTS idx_lab_request_consultation;
DROP INDEX IF EXISTS idx_prescription_item_medication;
DROP INDEX IF EXISTS idx_history_patient_condition;
ANALYZE;
