# Cloud Deployment Evidence

## Status: no AWS deployment was performed

The brief asks for AWS deployment evidence **where possible**. I could not create or use an AWS account from this environment, so **there is no real cloud deployment, no screenshot and no console output in this repository**, and none has been invented. This page therefore contains (1) what was genuinely run, (2) a plan the student can follow on the AWS Free Tier to produce real evidence, and (3) a blank evidence log.

## 1. Evidence that does exist (local, real)

| Item | File | What it shows |
|---|---|---|
| Streaming replica and promotion | `replication-lab/run-replication-demo.sh`, `replication-demo-output.txt` | A primary and a hot standby on one machine; read-only replica; lag; promotion |
| Hash partitioning | `replication-lab/partitioning-demo.sql`, `partitioning-demo-output.txt` | Shard-key routing and scatter-gather plans |
| Architecture diagram | `architecture-diagram.mmd`, `architecture-diagram.png` | The target AWS layout (a design drawing, not an export of something deployed) |

To re-run the local demos: start PostgreSQL as in Portfolio 1, then `./replication-lab/run-replication-demo.sh` (as root, adjust the paths at the top).

## 2. Plan to produce real AWS evidence (for the student)

Check current AWS Free Tier terms and prices first; Multi-AZ and replicas are normally **not** free, so delete everything afterwards.

1. Create an RDS for PostgreSQL instance (smallest class), single-AZ first, encrypted with KMS, in a private subnet group, public access off. Connect from an EC2 instance in the same VPC and run `create-tables.sql` and `sample-data.sql` from Portfolio 1.
2. Take a manual snapshot, and note the automated backup retention setting.
3. Modify the instance to **Multi-AZ** and note the console state. Optionally reboot with failover and record how long the connection is unavailable.
4. Create a **read replica**, run a SELECT against its endpoint and show that an INSERT fails.
5. Restore the snapshot to a new instance (point-in-time restore) and compare row counts.
6. Screenshot each step with the Region, instance identifier and time visible. Redact account IDs.
7. Delete the instances, replicas and snapshots to stop charges.

## 3. Evidence log (to be completed by the student)

| Step | Done | Date | Screenshot file | Notes |
|---|---|---|---|---|
| RDS instance created (encrypted, private) | no | | | |
| Schema loaded | no | | | |
| Snapshot and backup retention | no | | | |
| Multi-AZ enabled / failover test | no | | | |
| Read replica queried | no | | | |
| Point-in-time restore | no | | | |
| Resources deleted | no | | | |

If no AWS evidence is produced, the submission should say plainly that Portfolio 5 is a design with local demonstrations.
