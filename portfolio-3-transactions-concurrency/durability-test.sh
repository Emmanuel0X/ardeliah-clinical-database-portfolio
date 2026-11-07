#!/usr/bin/env bash
# =====================================================================
# Ardeliah Clinical System: durability (the "D" in ACID) crash test
# Portfolio 3: Transactions and Concurrency
#
# WARNING: this stops and restarts the PostgreSQL server. Run it ONLY on
# a throwaway local cluster, never on a server anyone else is using.
#
# Usage:   PGDATA=/path/to/data ./durability-test.sh
#          (PGHOST / PGPORT / PGUSER select the connection, as for psql.
#           Set PG_CTL_PREFIX to run pg_ctl as another user, for example
#           PG_CTL_PREFIX="su postgres -c" in a container.)
#
# What it does:
#   1. Commits one appointment (row X).
#   2. Starts a second session that inserts another appointment (row Y)
#      but never commits.
#   3. Stops the server with "pg_ctl stop -m immediate": no checkpoint
#      and no clean shutdown, the same recovery path as a power cut or
#      kill -9. Everything that was only in memory is lost.
#   4. Restarts the server and shows the recovery messages from the log.
#   5. Checks which rows exist: X must be there (durability), Y must not
#      (atomicity: an uncommitted transaction leaves no trace).
# =====================================================================
set -uo pipefail

: "${PGDATA:?set PGDATA to the data directory of a throwaway cluster}"
DB="${PGDATABASE:-ardeliah}"
LOG="${PG_LOG:-$PGDATA/../durability-server.log}"
PG_CTL="${PG_CTL:-pg_ctl}"
PREFIX="${PG_CTL_PREFIX:-}"
PSQL="psql -X -q -d $DB"
OPTS="${PG_SERVER_OPTS:-}"       # e.g. "-p 5433 -k /path/to/socket"

run_ctl() {                      # run pg_ctl, optionally as another user
  if [ -n "$PREFIX" ]; then $PREFIX "$PG_CTL -D '$PGDATA' $*"; else $PG_CTL -D "$PGDATA" "$@"; fi
}

echo "== 0. clean up any rows from a previous run"
$PSQL -c "DELETE FROM ardeliah.appointment WHERE reason LIKE 'P3 durability%'"

echo "== 1. session 1: insert row X and COMMIT"
$PSQL -At -c "INSERT INTO ardeliah.appointment (patient_id, doctor_id, appointment_date, start_time, reason)
              VALUES (19980, 40, '2027-04-01', '09:00', 'P3 durability: X committed') RETURNING appointment_id, reason"

echo "== 2. session 2: insert row Y inside a transaction that is NEVER committed"
( echo "BEGIN;
        INSERT INTO ardeliah.appointment (patient_id, doctor_id, appointment_date, start_time, reason)
        VALUES (19981, 40, '2027-04-01', '10:00', 'P3 durability: Y uncommitted');
        SELECT 'Y inserted, transaction still open' AS session2;
        SELECT pg_sleep(120);" | $PSQL -At ) &
BG=$!
sleep 2

echo "== 3. simulate a crash: stop the server with -m immediate (no checkpoint)"
run_ctl stop -m immediate
wait $BG 2>/dev/null || true     # session 2 loses its connection

echo "== 4. restart; recovery messages from the server log"
LOG_LINES_BEFORE=$(wc -l < "$LOG" 2>/dev/null || echo 0)     # so we only show NEW log lines
run_ctl -o "'$OPTS'" -l "$LOG" start >/dev/null
for i in $(seq 1 20); do pg_isready -q && break; sleep 1; done
tail -n +"$((LOG_LINES_BEFORE + 1))" "$LOG" \
  | grep -E "not properly shut down|automatic recovery|redo (starts|done)|database system is ready"

echo "== 5. which rows survived?"
$PSQL -c "SELECT reason, 'present after crash' AS state
          FROM ardeliah.appointment WHERE reason LIKE 'P3 durability%' ORDER BY reason"
$PSQL -At -c "SELECT 'rows found: ' || count(*) || ' (expected 1: only X)' FROM ardeliah.appointment WHERE reason LIKE 'P3 durability%'"

echo "== 6. clean up"
$PSQL -c "DELETE FROM ardeliah.appointment WHERE reason LIKE 'P3 durability%'"
