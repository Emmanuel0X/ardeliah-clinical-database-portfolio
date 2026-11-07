# Technical Reflection

This is a draft written with AI help. **Rewrite it in your own words** and add your own experiences before submitting; the points below are the ones the work supports.

## What worked well

- **Building on real execution.** Because each script was run, the evidence (plans, timings, two-session transcripts, the crash test) is genuine, and wrong ideas were caught. For example, I had assumed a comment about how K2 avoids a sort; the plan showed otherwise and the comment was corrected.
- **Designing constraints first.** The partial unique index in Portfolio 1 later became the answer to the double-booking scenario in Portfolio 3, and had to be re-expressed as a `slot_active` flag in Portfolio 4. Seeing one business rule in three systems made the trade-offs concrete.
- **Deterministic synthetic data.** A repeatable generator means anyone can rebuild the same 185,304 appointments and compare timings.

## What was difficult

- **Realism of test data.** The first generator produced lab requests from long ago still "pending" and a cream dosed as "1 tablet". Poor data would have made the plans misleading.
- **Isolation levels.** The surprising result was that `REPEATABLE READ` in PostgreSQL does not allow phantoms but does allow write skew. Reading about it was not enough; the two-session test made it clear.
- **The environment.** No MongoDB server or AWS account was available, so Portfolios 4 and 5 relied on an emulator and local PostgreSQL demonstrations. I chose to state this clearly rather than produce screenshots that would look real but not be.

## Trade-offs I would defend in a viva

| Decision | Reason | Cost |
|---|---|---|
| PostgreSQL instead of MySQL | Partial indexes, rich isolation levels, `EXPLAIN (ANALYZE, BUFFERS)` | Syntax differs from MySQL examples in some textbooks |
| Seven indexes, not more | Each is tied to a plan; the write cost was measured | Some reports still scan |
| Retry on SQLSTATE 40001 and 40P01 | Needed for `SERIALIZABLE` and deadlocks | Application code must retry |
| Embed consultations in one document | One read per visit | Duplicated drug names (deliberate snapshot) |
| Single primary, shard only later | Simplicity; sharding is costly | Write capacity is limited to one server |

## What I would do differently with more time

- Run Portfolio 4 on a real MongoDB (Atlas free tier) and record `explain()` plans and timings.
- Deploy Portfolio 5 on AWS RDS with Multi-AZ and a read replica and capture console evidence.
- Test a multi-document MongoDB transaction and compare it with the PostgreSQL version.
- Add row-level security in PostgreSQL so doctors see only their own patients.

## What I learned

Correctness rules belong in the database where possible; performance work starts from plans, not guesses; and every claim in a technical report should be backed by something you actually ran, or labelled as design.
