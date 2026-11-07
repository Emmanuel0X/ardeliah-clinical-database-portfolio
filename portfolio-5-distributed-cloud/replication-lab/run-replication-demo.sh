#!/usr/bin/env bash
# =====================================================================
# Streaming replication demo on ONE machine (primary on 5433, replica on 5434).
# Portfolio 5: Distributed Databases and Cloud Deployment
#
# What it proves: a write on the primary appears on a hot-standby replica,
# the replica refuses writes, replication lag can be measured, and the
# replica can be promoted to a new primary (a manual failover).
# What it does NOT prove: anything about AWS, a network between machines, or
# automatic failover (RDS Multi-AZ does that for you).
#
# Run as root (it uses "su postgres"); adjust PRIMARY_DATA/PORT as needed.
# =====================================================================
set -uo pipefail
BIN=/usr/lib/postgresql/16/bin
PRIMARY_DATA=${PRIMARY_DATA:-/var/lib/postgresql/ardeliah-data}
SOCK=${SOCK:-/var/lib/postgresql/ardeliah-sock}
REPLICA_DATA=/var/lib/postgresql/ardeliah-replica
PP=5433; RP=5434
as_pg() { su postgres -c "$1"; }
psqlp() { as_pg "$BIN/psql -h $SOCK -p $PP -d ardeliah -X -q -At -c \"$1\""; }
psqlr() { as_pg "$BIN/psql -h $SOCK -p $RP -d ardeliah -X -q -At -c \"$1\""; }
step() { echo; echo "=== $*"; }

step "0. Clean any earlier replica"
as_pg "$BIN/pg_ctl -D $REPLICA_DATA stop -m fast" >/dev/null 2>&1 || true
rm -rf "$REPLICA_DATA"

step "1. Primary settings relevant to replication"
psqlp "SELECT name||' = '||setting FROM pg_settings WHERE name IN ('wal_level','max_wal_senders','hot_standby') ORDER BY name"

step "2. Take a base backup and configure it as a standby (pg_basebackup -R)"
as_pg "$BIN/pg_basebackup -h $SOCK -p $PP -D $REPLICA_DATA -R -X stream -c fast" 2>&1 | tail -3
as_pg "echo \"port = $RP\" >> $REPLICA_DATA/postgresql.conf"
as_pg "$BIN/pg_ctl -D $REPLICA_DATA -o \"-k $SOCK\" -l /var/lib/postgresql/replica.log -w start" | tail -1

step "3. Is the replica in recovery (a standby)?"
echo -n "primary pg_is_in_recovery = "; psqlp "SELECT pg_is_in_recovery()"
echo -n "replica pg_is_in_recovery = "; psqlr "SELECT pg_is_in_recovery()"

step "4. Primary sees the replica streaming"
psqlp "SELECT state||', sync_state='||sync_state FROM pg_stat_replication"

step "5. Write on the primary, read on the replica"
psqlp "CREATE TABLE IF NOT EXISTS replication_probe(id int primary key, note text, written_at timestamptz default now())"
psqlp "TRUNCATE replication_probe"
psqlp "INSERT INTO replication_probe(id,note) VALUES (1,'written on primary')"
sleep 1
echo -n "replica sees rows: "; psqlr "SELECT count(*)||' (note: '||min(note)||')' FROM replication_probe"
echo -n "row counts primary/replica patient: "; echo -n "$(psqlp 'SELECT count(*) FROM ardeliah.patient') / "; psqlr "SELECT count(*) FROM ardeliah.patient"

step "6. The replica refuses writes (read-only standby)"
psqlr "INSERT INTO replication_probe(id,note) VALUES (2,'written on replica')" 2>&1 | head -2

step "7. Replication lag right after a burst of writes"
psqlp "INSERT INTO replication_probe(id,note) SELECT g,'burst' FROM generate_series(100,20099) g"
psqlp "SELECT 'primary wal lsn - replay lsn (bytes) = '||pg_wal_lsn_diff(sent_lsn,replay_lsn) FROM pg_stat_replication"
sleep 1
echo -n "after 1s, replica rows: "; psqlr "SELECT count(*) FROM replication_probe"
echo -n "primary rows: "; psqlp "SELECT count(*) FROM replication_probe"

step "8. Failover: stop the primary's role, promote the replica"
as_pg "$BIN/pg_ctl -D $REPLICA_DATA promote -w" | tail -1
sleep 1
echo -n "replica pg_is_in_recovery after promote = "; psqlr "SELECT pg_is_in_recovery()"
psqlr "INSERT INTO replication_probe(id,note) VALUES (3,'written on promoted replica')" && echo "write on promoted replica: accepted"
echo -n "promoted node rows: "; psqlr "SELECT count(*) FROM replication_probe"
echo -n "old primary rows (diverged, as expected after promotion): "; psqlp "SELECT count(*) FROM replication_probe"

step "9. Clean up: stop and delete the replica, drop the probe table"
as_pg "$BIN/pg_ctl -D $REPLICA_DATA stop -m fast" >/dev/null
rm -rf "$REPLICA_DATA"
psqlp "DROP TABLE replication_probe"
echo done
