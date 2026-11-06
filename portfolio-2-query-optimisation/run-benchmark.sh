#!/usr/bin/env bash
# =====================================================================
# Ardeliah Clinical System: before/after benchmark for key queries
# Portfolio 2: Query Processing and Optimisation
#
# Usage:   ./run-benchmark.sh <label> [runs]
#          ./run-benchmark.sh before          # baseline, no extra indexes
#          psql -d ardeliah -f indexing-strategy.sql
#          ./run-benchmark.sh after           # with the indexes
#
# For each key query it runs EXPLAIN (ANALYZE, BUFFERS) <runs> times
# (default 7), throws away the first run as a cache warm-up, and reports
# the median "Execution Time" of the rest. The full plan from the final
# run is saved so it can be read and screenshotted.
#
# Output (in ./evidence): plans-<label>.txt and timings-<label>.txt
# Connection settings come from the usual PG* environment variables;
# the database defaults to "ardeliah".
# =====================================================================
set -euo pipefail

LABEL="${1:?usage: $0 <label> [runs]}"
RUNS="${2:-7}"
export PGDATABASE="${PGDATABASE:-ardeliah}"
OUT_DIR="$(dirname "$0")/evidence"
mkdir -p "$OUT_DIR"
PLANS="$OUT_DIR/plans-$LABEL.txt"
TIMINGS="$OUT_DIR/timings-$LABEL.txt"
: > "$PLANS"
: > "$TIMINGS"

# Key queries (same text as Q1, Q2, Q4, Q11 and Q12 in queries.sql).
declare -a NAMES SQLS

NAMES+=("K1 patient name search (Q1)")
SQLS+=("SELECT patient_id, first_name, last_name, date_of_birth, phone
FROM ardeliah.patient
WHERE last_name = 'Okeke' AND first_name = 'Chinedu'
ORDER BY date_of_birth LIMIT 10")

NAMES+=("K2 patient appointment history (Q2)")
SQLS+=("SELECT a.appointment_date, a.start_time, a.status,
       d.first_name || ' ' || d.last_name AS doctor, s.specialisation_name
FROM ardeliah.appointment a
JOIN ardeliah.doctor d ON d.doctor_id = a.doctor_id
JOIN ardeliah.specialisation s ON s.specialisation_id = d.specialisation_id
WHERE a.patient_id = 7421
ORDER BY a.appointment_date DESC, a.start_time LIMIT 10")

NAMES+=("K3 patient prescription history (Q4)")
SQLS+=("SELECT a.appointment_date, m.generic_name, m.strength, m.form,
       pi.dosage, pi.frequency, pi.duration_days, pr.status
FROM ardeliah.appointment a
JOIN ardeliah.consultation c ON c.appointment_id = a.appointment_id
JOIN ardeliah.prescription pr ON pr.consultation_id = c.consultation_id
JOIN ardeliah.prescription_item pi ON pi.prescription_id = pr.prescription_id
JOIN ardeliah.medication m ON m.medication_id = pi.medication_id
WHERE a.patient_id = 7421
ORDER BY a.appointment_date DESC, m.generic_name")

NAMES+=("K4 doctor week sheet (Q11)")
SQLS+=("SELECT a.appointment_date, a.start_time, a.status,
       p.first_name || ' ' || p.last_name AS patient, a.reason
FROM ardeliah.appointment a
JOIN ardeliah.patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 12
  AND a.appointment_date BETWEEN date '2026-10-12' AND date '2026-10-16'
  AND a.status <> 'CANCELLED'
ORDER BY a.appointment_date, a.start_time")

NAMES+=("K5 urgent lab work queue (Q12)")
SQLS+=("SELECT rq.lab_request_id, t.test_name, rq.requested_at, rq.status
FROM ardeliah.lab_request rq
JOIN ardeliah.lab_test_catalog t ON t.test_id = rq.test_id
WHERE rq.status IN ('REQUESTED', 'COLLECTED') AND rq.priority = 'URGENT'
ORDER BY rq.requested_at LIMIT 20")

median() {  # reads numbers on stdin, prints the median
  sort -n | awk '{a[NR]=$1} END {if (NR%2) print a[(NR+1)/2]; else printf "%.3f\n", (a[NR/2]+a[NR/2+1])/2}'
}

printf '%-42s %12s %12s %12s\n' "Query" "median (ms)" "min (ms)" "max (ms)" | tee -a "$TIMINGS"
for i in "${!NAMES[@]}"; do
  tmp="$(mktemp)"
  for r in $(seq 1 "$RUNS"); do
    plan="$(psql -X -q -At -c "EXPLAIN (ANALYZE, BUFFERS) ${SQLS[$i]}")"
    echo "$plan" | grep -E '^Execution Time:' | awk '{print $3}' >> "$tmp"
    last_plan="$plan"
  done
  { echo "=== ${NAMES[$i]} ==="; echo "$last_plan"; echo; } >> "$PLANS"
  tail -n +2 "$tmp" > "$tmp.rest"          # drop the warm-up run
  med="$(median < "$tmp.rest")"
  mn="$(sort -n "$tmp.rest" | head -1)"
  mx="$(sort -n "$tmp.rest" | tail -1)"
  printf '%-42s %12s %12s %12s\n' "${NAMES[$i]}" "$med" "$mn" "$mx" | tee -a "$TIMINGS"
  rm -f "$tmp" "$tmp.rest"
done
echo "Saved: $PLANS and $TIMINGS"
