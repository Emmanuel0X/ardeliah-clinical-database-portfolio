# Portfolio 3: Transactions and Concurrency

**Case study:** Ardeliah Clinical System.
**DBMS:** PostgreSQL 16.15.
**Question this portfolio answers:** what happens when reception staff, doctors and lab technicians use the system at the same time, and how does the database keep the data correct?

## Files

| File | What it contains |
|---|---|
| `transaction-scripts.sql` | Five single-session examples: COMMIT, failure with automatic undo, ROLLBACK, SAVEPOINT, and an e-prescription that must succeed or fail as a whole |
| `isolation-levels-demo.sql` | Eleven two-session scenarios: isolation levels, lost update, write skew, double booking, locking, deadlock, `SKIP LOCKED`. Readable as a manual script |
| `run-concurrency-demos.py` | Runs the scenarios against two live `psql` sessions plus an observer and records the real output |
| `durability-test.sh` | Crash-recovery test for durability (stops the server abruptly, restarts, checks what survived) |
| `concurrency-evidence.md` | Explanation of every result, with a summary table |
| `output-screenshots-description.md` | What to run and what each screenshot shows |
| `evidence/` | Real outputs: `transaction-scripts-output.txt`, `concurrency-transcript.md`, `durability-output.txt` |

## How to run

```bash
# the database from Portfolios 1 and 2 must already exist
cd portfolio-3-transactions-concurrency

# 1. single-session transactions (the -a flag echoes each statement)
psql -a -d ardeliah -f transaction-scripts.sql

# 2. two-session concurrency demos, run automatically
python3 run-concurrency-demos.py ardeliah
#    output: evidence/concurrency-transcript.md

# 3. or run them by hand: open two terminals with `psql -d ardeliah`
#    and paste the @A and @B blocks from isolation-levels-demo.sql in order
```

**Durability test** (stops and restarts the server, so use a throwaway local cluster only):

```bash
PGDATA=/path/to/your/data ./durability-test.sh
```

Set `PG_CTL_PREFIX`, `PG_SERVER_OPTS` and `PG_LOG` if your setup needs them (the header of the script explains each). On Windows, follow the same five steps by hand: commit one row, leave another uncommitted in a second session, stop the service forcibly (kill the `postgres` processes), start it again, and query.

All demo rows use the text `P3 txn` or `P3 demo` and fixed high ids (900001 and up), and the scripts remove them when they finish. After running, `SELECT count(*) FROM ardeliah.appointment WHERE reason LIKE 'P3%'` should return 0.

## Results in brief

- **Atomicity** holds: a failed statement undoes the whole transaction, including the parts that were valid on their own.
- **Isolation:** PostgreSQL has no dirty reads at any level. Non-repeatable reads occur at `READ COMMITTED`, phantoms do not occur at `REPEATABLE READ`, and write skew occurs at `REPEATABLE READ` but is stopped by `SERIALIZABLE`.
- **Double booking** is stopped by the partial unique index from Portfolio 1; the second session waits and then gets a duplicate key error.
- **Lost update** on a consultation note really happens with a naive read-modify-write and is fixed with `SELECT ... FOR UPDATE`.
- **Deadlock** is detected and resolved by the server; consistent lock ordering avoids it.
- **Durability:** after a simulated crash the committed row survived and the uncommitted row did not.

## How it was tested

1. Every script was executed on PostgreSQL 16.15, and the outputs saved in `evidence/` are those real runs.
2. The first run of the single-session script exposed a mistake of mine: in T4, I had used patient id 20004, which does not exist, so the very first insert failed on a foreign key and the rest of the transaction was aborted. The savepoint demonstration only worked after I changed the id to an existing patient (19990) and re-ran it. This is a good example of why the output has to be read, not just the exit code (psql returns 0 even when statements fail).
3. After each automatic run the database was checked for leftover demo rows.
4. In the first durability run, the log excerpt mixed in lines from an earlier server restart, so the script was changed to show only the lines written after its own restart, and re-run.

## Key design decisions

- **Use PostgreSQL's real behaviour.** The brief lists READ UNCOMMITTED as the level that shows a dirty read, but PostgreSQL does not allow dirty reads. I report that as a finding and demonstrate it, rather than faking a dirty read.
- **Real concurrency, not simulated.** Two live sessions are driven in a fixed order, and an observer session records lock waits from `pg_stat_activity`.
- **Healthcare-flavoured scenarios:** double booking, concurrent edits to clinical notes, a patient booking limit, a lab work queue.
- **Rules in the database where possible** (the unique index), with `SERIALIZABLE` or explicit locks where a rule cannot be a constraint.

## Limitations

A true dirty read was not demonstrated (see above). Contention here is two sessions on one machine; production behaviour with many sessions will differ.
