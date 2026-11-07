# References

Sources I relied on or that support the design. Check that each link and edition is correct before you cite them, and add any other material you personally read. Documentation pages are cited by chapter title because version numbers and paths change.

## Textbooks and papers

1. Codd, E. F. (1970). A relational model of data for large shared data banks. *Communications of the ACM*, 13(6), 377-387.
2. Silberschatz, A., Korth, H. F. and Sudarshan, S. (2019). *Database System Concepts*, 7th edn. McGraw-Hill.
3. Elmasri, R. and Navathe, S. B. (2016). *Fundamentals of Database Systems*, 7th edn. Pearson.
4. Kleppmann, M. (2017). *Designing Data-Intensive Applications*. O'Reilly Media.
5. Cahill, M. J., Rohm, U. and Fekete, A. D. (2008). Serializable isolation for snapshot databases. *Proceedings of ACM SIGMOD*, 729-738.
6. Gilbert, S. and Lynch, N. (2002). Brewer's conjecture and the feasibility of consistent, available, partition-tolerant web services. *ACM SIGACT News*, 33(2), 51-59.

## Product documentation

7. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation*: chapters on Concurrency Control (transaction isolation, explicit locking), Performance Tips (using EXPLAIN), Indexes (partial indexes), Table Partitioning, and High Availability, Load Balancing and Replication (streaming replication). https://www.postgresql.org/docs/16/
8. MongoDB, Inc. *MongoDB Manual*: Data Modeling, Schema Validation, Indexes (partial and multikey), Aggregation Pipeline, Replication, Sharding. https://www.mongodb.com/docs/manual/
9. Amazon Web Services. *Amazon RDS User Guide*: Multi-AZ deployments, Read replicas, Backing up and restoring, Encrypting Amazon RDS resources. https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/
10. Mermaid. *Mermaid documentation* (entity relationship and flowchart diagrams). https://mermaid.js.org/

## Law and regulation

11. Federal Republic of Nigeria. *Nigeria Data Protection Act 2023*. (Read the Act itself or take legal advice before relying on the summary in Portfolio 5.)

## Software used

PostgreSQL 16.15; Node.js 22 with mingo 7.2.7 and ajv 8.20.0 (MongoDB emulator and validator, Portfolio 4 verification only); Mermaid CLI (diagram rendering); Python 3 and `psql` (Portfolio 3 runner).
