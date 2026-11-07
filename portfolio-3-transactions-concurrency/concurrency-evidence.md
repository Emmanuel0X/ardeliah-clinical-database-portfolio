# Concurrency Evidence: Ardeliah Clinical System

Everything in this file was observed by running the scripts on PostgreSQL 16.15. The complete, unedited two-session transcripts are in `evidence/concurrency-transcript.md`; single-session transaction output is in `evidence/transaction-scripts-output.txt`; the crash test is in `evidence/durability-output.txt`.

## 1. The core scenario: two receptionists, one slot

Reception staff at the clinic book appointments at the same time. The risks are:

- two people booking **the same doctor at the same time** (double booking),
- two people editing **the same consultation note** (lost update),
- a booking **rule that spans several rows** being broken even though no single row conflicts (write skew),
- two transactions waiting on each other forever (**deadlock**).

Each is demonstrated below with what PostgreSQL actually did.

## 2. Summary of results

| Problem | Isolation level / mechanism | Observed result | Demo |
|---|---|---|---|
| Dirty read | Requested `READ UNCOMMITTED` | **Not possible.** Session A still saw `SCHEDULED` while B had an uncommitted `CANCELLED` | 2 |
| Non-repeatable read | `READ COMMITTED` (default) | **Occurs.** A read `SCHEDULED`, then `CHECKED_IN` in the same transaction after B committed | 1 |
| Phantom read | `REPEATABLE READ` | **Not possible in PostgreSQL.** Count stayed at 2 although B committed a new row; a new transaction saw 3 | 3 |
| Lost update (database detects it) | `REPEATABLE READ` | A's update was refused with `ERROR: could not serialize access due to concurrent update` | 3 |
| Lost update (application read-modify-write) | `READ COMMITTED` | **Occurs.** Doctor A's note was silently overwritten by Nurse B | 6a |
| Lost update fixed | `SELECT ... FOR UPDATE` | B waited, then read A's committed text; both notes survived | 6b |
| Write skew | `REPEATABLE READ` | **Occurs.** Patient ended with 3 bookings, breaking the "max 2" rule | 4a |
| Write skew prevented | `SERIALIZABLE` | B was aborted: `could not serialize access due to read/write dependencies among transactions`; patient has 2 bookings | 4b |
| Double booking | Partial unique index `uq_doctor_slot_active` | B's insert **waited** for A, then failed with `duplicate key value violates unique constraint` after A committed | 5 |
| Deadlock | Row locks in opposite order | PostgreSQL detected the cycle: `ERROR: deadlock detected`; the other transaction proceeded | 7a |
| Deadlock avoided | Consistent lock order | B simply waited for A; no error | 7b |
| Work queue contention | `FOR UPDATE SKIP LOCKED` | Technicians A and B received different lab requests without waiting | 8 |

## 3. Explanation of each result

### Isolation levels (Demos 1 to 3)

PostgreSQL supports three real isolation levels. The SQL standard has four, but PostgreSQL treats `READ UNCOMMITTED` as `READ COMMITTED`. Demo 2 proves this: the session reports `transaction_isolation = read uncommitted`, yet it still cannot see B's uncommitted change.

**Why this is the case:** PostgreSQL uses MVCC (multi-version concurrency control). Every update creates a new version of a row, tagged with the id of the transaction that wrote it. Each query only sees the versions that were committed when its snapshot was taken. An uncommitted version is never visible to anyone else, so there is nothing to read "dirty". A side effect, shown in Demo 1 step 3, is that **readers never wait for writers**: A's read returned instantly while B had the row open for update.

- **READ COMMITTED** takes a new snapshot for every statement. That is why A's second read in Demo 1 saw B's committed change (non-repeatable read).
- **REPEATABLE READ** takes one snapshot at the first statement and keeps it. This is stronger than the standard requires, because the standard allows phantoms at this level and PostgreSQL does not (Demo 3).
- **SERIALIZABLE** adds tracking of read/write dependencies (Serializable Snapshot Isolation) so that the outcome is equivalent to running the transactions one after another.

### Lost update (Demos 3, 6a and 6b)

Under `REPEATABLE READ`, if a transaction tries to update a row that another transaction changed and committed after the snapshot was taken, PostgreSQL aborts it instead of overwriting (Demo 3). The application must catch the error (SQLSTATE `40001`) and retry the whole transaction.

Demo 6a shows the more common real-world form of the bug. The application reads a note, adds text in its own code, and writes the whole value back. At `READ COMMITTED` both writes succeed, and the second silently destroys the first: "Doctor A: BP 140/90" was lost. In a clinical system that is a patient-safety problem, not just a data problem.

Demo 6b fixes it with a pessimistic lock. `SELECT ... FOR UPDATE` makes B wait until A commits, and under `READ COMMITTED` B's blocked query then returns A's newly committed text, so B builds on top of it. The observer query in the transcript shows B in `wait_event_type = Lock`, `wait_event = transactionid`, `blocked_by_pid` = A's process. An alternative that avoids holding locks is optimistic locking with a version column, which was not demonstrated here.

### Write skew (Demos 4a and 4b)

The rule "a patient may have at most two active appointments on one day" is checked by the application, not by a constraint. Both receptionists count 1 booking, both decide it is safe, and each inserts a booking with a **different doctor**. Because they write different rows, there is no row conflict for `REPEATABLE READ` to detect, and both commit: 3 bookings.

Under `SERIALIZABLE`, PostgreSQL notices that each transaction read data the other one wrote and aborts one of them. On retry, the loser would see 2 bookings and refuse the third.

**Design takeaway:** if a rule cannot be expressed as a constraint, either use `SERIALIZABLE` for that transaction and be ready to retry, or take an explicit lock (for example `SELECT ... FOR UPDATE` on the patient row) before counting.

### Double booking (Demo 5)

Both sessions first check "is the slot free?" and both see 0. That check-then-insert pattern is not safe on its own. What actually protects the data is the partial unique index from Portfolio 1. A's insert goes through; B's identical insert **blocks**, because it needs the same index entry as A's uncommitted row. When A commits, B is released and fails with a duplicate key error. Had A rolled back, B's insert would have succeeded.

This is the best example of putting the rule in the database: it is correct regardless of how many application servers or users are involved.

### Deadlock (Demos 7a and 7b)

A locks appointment 900001 and B locks 900002. A then asks for 900002 and B asks for 900001, so each waits for the other. PostgreSQL's deadlock detector runs after `deadlock_timeout` (1 second by default), picks a victim and aborts it with `ERROR: deadlock detected` (SQLSTATE `40P01`). In this run session B was the victim and A's blocked update then completed.

The standard prevention (Demo 7b) is to lock rows in a consistent order, for example always by ascending id. Then a cycle cannot form: the second session just queues behind the first.

### Skip locked (Demo 8)

Lab technicians take the next unassigned request. With plain `FOR UPDATE`, the second technician would wait for the first. With `SKIP LOCKED`, B is handed request 900002 immediately while A holds 900001. This is the standard pattern for a work queue, and it is appropriate here precisely because it does not matter which technician gets which request.

## 4. Atomicity, consistency and durability (single-session scripts)

| Script | What it showed | Evidence |
|---|---|---|
| T1 | A booking and its audit entry commit together | Both rows visible after `COMMIT` |
| T2 | A clash on the second insert undid the first appointment **and** the audit row. After the error every statement is refused until `ROLLBACK`; `COMMIT` is silently turned into `ROLLBACK` | `t2_appointments = 0`, `t2_audit_rows = 0` |
| T3 | `ROLLBACK` reverted a cancellation that was visible inside the transaction | Status `CANCELLED` inside, `SCHEDULED` after |
| T4 | `SAVEPOINT` let one failed insert (unknown test id) be undone without losing the consultation | Consultation and valid lab request both kept |
| T5 | A prescription header with a bad line (`duration_days = 0`) left no header behind | Prescriptions for consultation 1: 1 before, 1 after |

**Durability** (`durability-test.sh`): a committed appointment and an uncommitted one were created, then the server was stopped with `pg_ctl stop -m immediate`, which skips the checkpoint and clean shutdown just like a power cut. On restart the log shows `database system was not properly shut down; automatic recovery in progress` followed by `redo starts` and `redo done`. Afterwards only the committed row existed. This works because PostgreSQL writes each commit to the write-ahead log (WAL) and flushes it to disk before reporting success, and replays the WAL after a crash.

## 5. Control mechanisms used

- **MVCC** for reads (readers do not block writers).
- **Row-level locking**: implicit on `UPDATE`, explicit with `FOR UPDATE` and `FOR UPDATE SKIP LOCKED`.
- **Unique index** as a concurrency guard (double booking).
- **Serializable Snapshot Isolation** to stop write skew.
- **Deadlock detection** by the server, plus consistent lock ordering by the application.

PostgreSQL does not use classic timestamp ordering. Its closest relative is MVCC, where transaction ids play the part of timestamps for deciding which row version is visible.

## 6. What an application must do

- Treat SQLSTATE `40001` (serialization failure) and `40P01` (deadlock) as **retryable**: roll back and run the whole transaction again.
- Keep transactions short, and never wait for user input while one is open.
- Prefer constraints and unique indexes to "check then insert" logic.

## 7. Limitations

- A real dirty read could not be demonstrated, because PostgreSQL does not allow one. A system such as SQL Server or MySQL InnoDB at `READ UNCOMMITTED` would show it; that was not run here.
- The demos use two sessions plus an observer, on one machine with tiny data. Real contention involves many sessions and longer transactions.
- The 2.5 second "no reply" threshold in `run-concurrency-demos.py` decides when a statement is called blocked. It is a heuristic, backed up by the observer query showing the actual lock wait.
