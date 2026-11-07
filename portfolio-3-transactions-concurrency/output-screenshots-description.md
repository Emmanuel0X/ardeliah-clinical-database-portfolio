# Output Screenshots: what to capture and what it shows

The brief asks for screenshots or output evidence. Because these scripts were really run, each item below says exactly what the real output contains, so you can reproduce it and take your own screenshot. Take the screenshots yourself on your own machine after running the scripts; the text outputs saved in `evidence/` are the reference for what you should see.

Setup before starting: the database from Portfolios 1 and 2 must exist (`ardeliah`). Use two terminal windows for the two-session items.

| # | What to run | What the screenshot shows | Reference file |
|---|---|---|---|
| 1 | `psql -a -d ardeliah -f transaction-scripts.sql` and scroll to **T1** | `BEGIN`, the booking insert, `COMMIT`, then one row joining the new appointment to its audit entry | `evidence/transaction-scripts-output.txt` |
| 2 | Same run, **T2** | `ERROR: duplicate key value violates unique constraint "uq_doctor_slot_active"`, then `ERROR: current transaction is aborted, commands ignored until end of transaction block`, the `COMMIT` answered with `ROLLBACK`, and a result of `t2_appointments = 0`, `t2_audit_rows = 0` | same |
| 3 | Same run, **T3** | Status `CANCELLED` inside the transaction, `ROLLBACK`, then `SCHEDULED` again | same |
| 4 | Same run, **T4** | `SAVEPOINT`, a foreign key error on test id 9999, `ROLLBACK TO SAVEPOINT`, then a successful insert and a final row showing the consultation with the malaria test request | same |
| 5 | Same run, **T5** | `violates check constraint "prescription_item_duration_days_check"`, then `prescriptions_before = 1` and `prescriptions_after = 1` | same |
| 6 | `python3 run-concurrency-demos.py`, then open `evidence/concurrency-transcript.md`, **DEMO 1** | Session A reads `SCHEDULED` twice while B's update is uncommitted, then reads `CHECKED_IN` after B commits (non-repeatable read) | `evidence/concurrency-transcript.md` |
| 7 | **DEMO 2** | `transaction_isolation = read uncommitted`, yet A still sees `SCHEDULED` (no dirty read) | same |
| 8 | **DEMO 3** | Count `2`, then still `2` after B commits a new row, then `ERROR: could not serialize access due to concurrent update`, then `3` in a fresh transaction | same |
| 9 | **DEMO 4a** and **4b** side by side | 4a ends with `patient_bookings_that_day = 3`; 4b shows `ERROR: could not serialize access due to read/write dependencies among transactions` and ends with `2` | same |
| 10 | **DEMO 5** | B's insert gets "no reply yet"; the observer table shows `wait_event_type = Lock`, `wait_event = transactionid`, and `blocked_by_pid` equal to A's pid; after A commits, B receives the duplicate key error | same |
| 11 | **DEMO 6a** and **6b** | 6a ends with the note `Initial note. Nurse B: allergic to penicillin.` (Doctor A's text lost); 6b ends with both sentences present, with B shown waiting for a lock in the middle | same |
| 12 | **DEMO 7a** | `ERROR: deadlock detected` with `DETAIL: Process ... waits for ShareLock on transaction ...; blocked by process ...` | same |
| 13 | **DEMO 8** | A is given lab request 900001 and B is given 900002 without waiting | same |
| 14 | `./durability-test.sh` (see the README for the environment variables) | The log lines `database system was not properly shut down; automatic recovery in progress`, `redo starts`, `redo done`, and a final table with only the committed row | `evidence/durability-output.txt` |

Tips for good screenshots: use a terminal wide enough that tables do not wrap, show the command you ran at the top of each screenshot, and include your own name or username in the prompt or window title, since the assessor is looking for evidence that you ran this yourself.
