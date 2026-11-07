-- =====================================================================
-- Sharding idea, single-node version: hash-partition appointments by patient_id.
-- Portfolio 5. Real shards would live on SEPARATE servers; partitions live in
-- one server. What this DOES show: the shard key lets the planner touch one
-- partition for a patient lookup, and a query without the key must visit all.
-- Run: psql -d ardeliah -f partitioning-demo.sql   (uses a scratch schema)
-- =====================================================================
DROP SCHEMA IF EXISTS shard_demo CASCADE;
CREATE SCHEMA shard_demo;
SET search_path = shard_demo, ardeliah;

CREATE TABLE appt_sharded (
  appointment_id bigint NOT NULL,
  patient_id     bigint NOT NULL,
  doctor_id      bigint NOT NULL,
  appointment_date date NOT NULL,
  status         text NOT NULL,
  PRIMARY KEY (patient_id, appointment_id)      -- the shard key must be in the key
) PARTITION BY HASH (patient_id);

CREATE TABLE appt_s0 PARTITION OF appt_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE appt_s1 PARTITION OF appt_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE appt_s2 PARTITION OF appt_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE appt_s3 PARTITION OF appt_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 3);

INSERT INTO appt_sharded
SELECT appointment_id, patient_id, doctor_id, appointment_date, status::text FROM ardeliah.appointment;
ANALYZE appt_sharded;

\echo '--- rows per shard (an even spread is the point of hashing)'
SELECT tableoid::regclass AS shard, count(*) FROM appt_sharded GROUP BY 1 ORDER BY 1;

\echo '--- lookup WITH the shard key: one partition scanned'
EXPLAIN (COSTS OFF) SELECT * FROM appt_sharded WHERE patient_id = 12;

\echo '--- query WITHOUT the shard key: every partition scanned (scatter-gather)'
EXPLAIN (COSTS OFF) SELECT * FROM appt_sharded WHERE doctor_id = 5 AND appointment_date >= '2026-10-01';

DROP SCHEMA shard_demo CASCADE;
