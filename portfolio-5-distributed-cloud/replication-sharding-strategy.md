# Replication and Sharding Strategy

## 1. Summary of the strategy

| Layer | Decision | Phase |
|---|---|---|
| Primary | One PostgreSQL writer holds all writes | Now |
| High availability | Synchronous standby in a second Availability Zone with automatic failover (RDS Multi-AZ) | Now |
| Read scaling | One asynchronous read replica for reports, search and dashboards | Now |
| Backups | Automated daily backups plus WAL for point-in-time recovery; cross-Region copy | Now |
| Sharding | Hash by `patient_id`; reference tables replicated to every shard | Only when one primary is measurably the bottleneck |

## 2. Routing rules for the application

| Request | Sent to | Why |
|---|---|---|
| Book, cancel, prescribe, record a result | Primary | Must see and create the latest data (Portfolio 3 concurrency rules apply) |
| Allergy and current-medication check while prescribing | Primary | Stale data is a safety risk |
| Patient history screen, appointment lists | Replica is acceptable if the screen shows "as of" time; primary right after the user's own write ("read your own writes") | Lag can hide a write made a second ago |
| Monthly reports and analytics | Read replica | Keeps heavy queries off the primary |

## 3. Failover procedure (what was demonstrated manually, what the cloud automates)

| Step | Local lab (real, `replication-demo-output.txt`) | On RDS Multi-AZ (design) |
|---|---|---|
| Detect failure | Not simulated; I promoted deliberately | Automatic health checks |
| Promote standby | `pg_ctl promote` | Automatic |
| Redirect clients | Not needed (same machine, different port) | DNS name of the database endpoint switches to the new primary; applications must reconnect and retry |
| Protect against split brain | Showed the old primary and the new node diverge | Handled by the service |

## 4. Shard design (growth path)

- **Shard key:** `patient_id` (hash). The shard key is part of every patient-owned table's primary key, as in `partitioning-demo.sql`.
- **Co-located on the patient's shard:** appointments, consultations, diagnoses, prescriptions, prescription items, lab requests, lab results, medical history.
- **Replicated to every shard:** specialisation, icd_code, medication, lab_test_catalog, role.
- **Directory:** a small lookup (patient ID hashing function, or a table) tells the application which shard to use.
- **Awkward case:** doctor schedules and double-booking prevention are keyed by doctor. Keep one authoritative calendar per doctor and reference it from patient shards.
- **Region-based alternative:** if law or latency requires data to stay in a clinic's region, shard by clinic instead and accept uneven sizes.
- **Resharding:** adding shards later means moving rows; hash ranges (many small partitions mapped to few servers) make that easier.

## 5. Replication in the MongoDB model (Portfolio 4)

MongoDB replicates through a **replica set** (one primary, secondaries, automatic election) and shards through a **sharded cluster** with a shard key. The same patient ID key would keep a patient's `consultations` and `appointments` together. This is from documentation; no MongoDB cluster was run.

## 6. What has been verified

| Claim | Evidence |
|---|---|
| Streaming replication works; replica is read-only; lag exists; promotion works | `replication-lab/replication-demo-output.txt` (real run, PostgreSQL 16, one machine) |
| Hash partitioning spreads rows evenly; shard key lookup touches one partition | `replication-lab/partitioning-demo-output.txt` (real run, single server) |
| RDS Multi-AZ, read replica, backup, KMS behaviour | **Not tested.** Design based on AWS documentation |
