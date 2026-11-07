# Distributed Database Discussion: Ardeliah Clinical System

> **Honesty note.** This portfolio is a design and discussion. Nothing was deployed on AWS (see `cloud-deployment-evidence.md`). What *was* run for real is a PostgreSQL streaming replica and a hash-partitioning demo on one machine (`replication-lab/`). AWS service behaviour described here comes from my understanding of the AWS documentation and should be checked against the current pages listed in `final-documentation/references.md`; figures such as failover times are typical values, not measurements.

## 1. Why distribute at all?

A single PostgreSQL server (Portfolios 1 to 3) is enough for one clinic's workload. Three needs push towards distribution:

| Need | Meaning for Ardeliah | Technique |
|---|---|---|
| **Availability** | Doctors cannot see prescriptions or allergies if the database is down during clinic hours | Replication with automatic failover |
| **Read scaling** | Reports, patient-history searches and dashboards compete with bookings | Read replicas |
| **Data growth and several sites** | If Ardeliah grows to many clinics, one server's storage and write capacity become limits | Sharding (partitioning across servers) |

## 2. Replication

Replication keeps copies of the data on other servers.

| Kind | How it works | Trade-off |
|---|---|---|
| **Synchronous** | The primary waits for the copy to confirm before saying "committed" | No committed data lost on failover; each write is slower |
| **Asynchronous** | The primary commits at once and ships changes afterwards | Fast; a failover can lose the last few moments of writes, and replicas can show slightly old data |

PostgreSQL streaming replication ships the write-ahead log (WAL), the same log that gave crash recovery in Portfolio 3. The real run in `replication-lab/replication-demo-output.txt` showed:

- A standby built with `pg_basebackup` came up in recovery (`pg_is_in_recovery = t`) and the primary listed it as `streaming, async`.
- A row written on the primary appeared on the replica within a second.
- The replica refused writes: `cannot execute INSERT in a read-only transaction`.
- Right after a burst of 20,000 inserts the primary reported a replay gap of roughly 1 to 2 MB of WAL, and one second later both nodes held 20,001 rows. That gap is **replication lag**, the source of stale reads. The exact byte value changed between runs, so treat it as illustrative.
- Promoting the replica (`pg_ctl promote`) made it accept writes. The old primary and the new one then **diverged** (20,001 rows against 20,002): after a real failover the old primary must not be allowed to carry on accepting writes (split brain).

## 3. Sharding

Sharding splits **rows** across servers by a shard key. Replication copies everything; sharding divides it.

### Options for Ardeliah

| Shard key | Advantages | Disadvantages |
|---|---|---|
| **Patient ID (hash)** | Even spread; one patient's appointments, consultations, prescriptions and results sit together, so the common screens touch one shard | A query that is not about one patient (all appointments for Dr X today) must ask every shard |
| **Region or clinic** | Data stays near its users and within a jurisdiction; simple to explain | Uneven sizes (a big city clinic); patients who move between regions need their records moved |
| **Date range** | Easy archiving of old data | The newest shard takes all the writes (a hot spot) |

**Recommendation:** shard by **patient ID**, because the clinical data is patient-centred (the same reasoning that made the consultation a self-contained document in Portfolio 4). Keep the small reference tables (ICD codes, medications, lab tests, doctors, specialisations) **replicated in full to every shard**. Doctors' schedules are the awkward case: they are queried by doctor, not by patient, so the booking check (no double booking) needs a single place that owns a doctor's calendar. In a sharded design I would keep appointment *slots* with the doctor's clinic and store a reference in the patient's shard.

### What I demonstrated

`replication-lab/partitioning-demo.sql` hash-partitions a copy of the 185,304-row appointment table into four partitions by `patient_id`, on one server. Real output is in `partitioning-demo-output.txt`:

- Rows spread evenly: 46,158 / 46,795 / 46,676 / 45,675.
- A lookup by `patient_id` scanned **one** partition (an index scan on `appt_s0`).
- A query by doctor and date, without the shard key, scanned **all four**.

This is a model of the idea. Real shards live on different servers, and then cross-shard joins, transactions and unique constraints become application or middleware problems. PostgreSQL does not shard across servers by itself; options include the Citus extension or application-level routing. I did not try these.

## 4. The CAP theorem applied to Ardeliah

CAP says that when a network **partition** happens between nodes, a system must choose between **consistency** (every read sees the latest write) and **availability** (every request gets an answer).

| Function | Choice during a partition | Reason |
|---|---|---|
| Booking appointments, prescriptions, lab results | **Consistency first (CP)** | A double-booked slot or a prescription that is not visible to the pharmacist is a patient-safety or operational error. Better to refuse briefly than to be wrong |
| Reading a patient's history, reports, dashboards | **Availability first (AP)** acceptable via a replica | Slightly old data is tolerable for reports; for clinical decisions the UI should show "as of" time |
| Allergy and current-medication check at prescribing time | Read from the **primary** | Stale data here is dangerous |

A single-primary PostgreSQL design (this one) is CP for writes: if the primary cannot be reached, writes stop until failover completes. MongoDB with default settings behaves similarly (writes go to the primary of a replica set) but offers tunable write and read concerns. The portfolio does not run anything on MongoDB, so that statement is from documentation, not from my testing.

## 5. Availability and failure scenarios

| Failure | Effect with this design | Recovery |
|---|---|---|
| Application server dies | Load balancer sends traffic to the other one | Automatic |
| Primary database instance fails | Writes pause during failover | Multi-AZ promotes the standby automatically; typically one to two minutes |
| A whole Availability Zone fails | Same as above (standby is in another zone) | Automatic |
| Read replica fails | Reports fall back to the primary or wait | Replace the replica |
| Someone deletes or corrupts data | Replication copies the damage to the standby | **Point-in-time restore** from backups (replication is not a backup) |
| Whole Region lost | Service down | Restore from cross-Region backup copies; this takes hours, an accepted trade-off for a clinic of this size |

## 6. Security and privacy considerations

Health data is among the most sensitive personal data. For a Nigerian clinic, the **Nigeria Data Protection Act 2023** applies to health data (special category) and its rules on data location, consent and breach notification should be checked with someone qualified; I have not taken legal advice. Technical controls in the design:

- Database in **private subnets**, no public address; access only from application servers through security groups.
- **Encryption at rest** (KMS keys) and **in transit** (TLS required).
- **Least-privilege roles**: the roles from Portfolio 1 (`app_user`, doctor, receptionist, lab) map to database roles, and application accounts do not own the schema.
- **Audit log** (the `audit_log` table of Portfolio 1) plus database and cloud audit logging.
- Secrets in a secrets manager, rotated; no passwords in the repository.
- Backups encrypted and access-controlled; restore tested regularly.
- Data residency: the nearest AWS Region to Nigeria is Cape Town (`af-south-1`); whether health data may be hosted there or must stay in Nigeria needs a legal check.

## 7. Cost and complexity

Multi-AZ roughly doubles the database cost, replicas add to it, and sharding adds large complexity. For the case study I recommend: **Multi-AZ, one read replica, automated backups, no sharding until a single primary is measurably the bottleneck.** Sharding by patient ID is documented as the growth path, not the starting point. Prices are not stated because I have not priced them with the AWS calculator.
