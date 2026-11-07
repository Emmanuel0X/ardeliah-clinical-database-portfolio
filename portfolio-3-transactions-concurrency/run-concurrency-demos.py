#!/usr/bin/env python3
"""
Runs isolation-levels-demo.sql against TWO real psql sessions (A and B)
and writes what actually happened to evidence/concurrency-transcript.md.

Why a script and not just two terminals? Interleaving two sessions by
hand is easy to get wrong and impossible to screenshot repeatably. This
script sends each "@A" / "@B" block to the right session in the written
order, records the real output, and notices when a statement blocks on a
lock (no reply within a couple of seconds). While a session is blocked,
a third "observer" session asks pg_stat_activity what it is waiting for,
so the transcript shows the lock wait as evidence.

Usage:   python3 run-concurrency-demos.py [database]     (default: ardeliah)
Needs:   psql on the PATH and the usual PG* environment variables.
Stdlib only.
"""
import os
import queue
import re
import subprocess
import sys
import threading
import time
from datetime import datetime

DB = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PGDATABASE", "ardeliah")
HERE = os.path.dirname(os.path.abspath(__file__))
DEMO_FILE = os.path.join(HERE, "isolation-levels-demo.sql")
OUT_FILE = os.path.join(HERE, "evidence", "concurrency-transcript.md")

BLOCK_WAIT = 2.5      # seconds to wait for a statement before calling it "blocked"
RELEASE_WAIT = 1.5    # seconds to wait for a blocked session to be released


class Session:
    """One psql process. Statements are followed by an \\echo token so we
    know exactly where its output ends."""

    def __init__(self, name):
        self.name = name
        self.proc = subprocess.Popen(
            ["psql", "-X", "-d", DB],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1)
        self.lines = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()
        self.counter = 0
        self.token = None
        self.buffer = []
        self.pending_entry = None      # transcript entry waiting for output
        self.run_hidden("SET search_path TO ardeliah;")

    def _reader(self):
        for line in self.proc.stdout:
            self.lines.put(line.rstrip("\n"))
        self.lines.put(None)

    def send(self, sql):
        self.counter += 1
        self.token = "@@DONE%d@@" % self.counter
        self.buffer = []
        self.proc.stdin.write(sql.rstrip() + "\n\\echo " + self.token + "\n")
        self.proc.stdin.flush()

    def collect(self, timeout):
        """Read output until the token for the last statement appears.
        Returns True if finished, False if still waiting after timeout."""
        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                return False
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty:
                return False
            if line is None:
                return True
            if line == self.token:
                return True
            self.buffer.append(line)

    def output(self):
        text = "\n".join(self.buffer)
        text = re.sub(r"(?m)^psql:<stdin>:\d+: ", "", text)    # tidy error prefixes
        return text.strip("\n")

    def run_hidden(self, sql, timeout=30):
        self.send(sql)
        self.collect(timeout)
        return self.output()

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def parse(path):
    """Split the demo file into demos, each with intro text and blocks.
    A block is (kind, narration_lines, sql)."""
    demos, setup_sql, cleanup_sql = [], None, None
    cur_demo, cur_block = None, None

    def finish_block():
        nonlocal cur_block, setup_sql, cleanup_sql
        if cur_block is None:
            return
        kind, narr, sql_lines = cur_block
        sql = "\n".join(sql_lines).strip()
        if kind == "SETUP":
            if setup_sql is None:
                setup_sql = sql                      # first SETUP = fixtures
            if cur_demo is not None:
                cur_demo["blocks"].append(("SETUP", narr, sql))
        elif kind == "CLEANUP":
            cleanup_sql = sql
        elif cur_demo is not None:
            cur_demo["blocks"].append((kind, narr, sql))
        cur_block = None

    for raw in open(path):
        line = raw.rstrip("\n")
        m = re.match(r"-- === (.*?) ===\s*$", line)
        if m:
            finish_block()
            cur_demo = {"title": m.group(1), "intro": [], "blocks": []}
            demos.append(cur_demo)
            continue
        m = re.match(r"-- @(A|B|SETUP|CLEANUP)\s*$", line)
        if m:
            finish_block()
            cur_block = (m.group(1), [], [])
            continue
        if cur_block is None:
            if cur_demo is not None and line.startswith("--") and line.strip("- ").strip():
                cur_demo["intro"].append(line[2:].strip())
            continue
        if line.startswith("--"):
            text = line[2:].strip()
            if text:
                cur_block[1].append(text)
        elif line.strip():
            cur_block[2].append(line)
    finish_block()
    return demos, setup_sql, cleanup_sql


OBSERVER_SQL = """SELECT a.pid, a.state, a.wait_event_type, a.wait_event,
       pg_blocking_pids(a.pid) AS blocked_by_pid, left(a.query, 60) AS waiting_query
FROM pg_stat_activity a
WHERE a.datname = current_database() AND a.wait_event_type = 'Lock';"""


def main():
    demos, setup_sql, cleanup_sql = parse(DEMO_FILE)
    obs = Session("observer")
    version = obs.run_hidden("SELECT version();").splitlines()
    version = [l for l in version if "PostgreSQL" in l]
    out = ["# Concurrency Evidence: real two-session transcripts\n",
           "Generated by `run-concurrency-demos.py` on %s against %s.\n"
           % (datetime.now().strftime("%Y-%m-%d %H:%M"), version[0].strip() if version else "PostgreSQL"),
           "Each demo below was executed against two live `psql` sessions (A and B) in the order shown. "
           "The output is exactly what PostgreSQL returned; nothing was edited. Where a statement could not "
           "complete because it was waiting for a lock, the transcript says so and then shows the moment it "
           "was released. While a session was blocked, a third observer session queried `pg_stat_activity` "
           "and the result is included.\n"]

    for demo in demos:
        title = demo["title"]
        if title.startswith("CLEANUP"):
            continue
        if not any(k in ("A", "B") for k, _, _ in demo["blocks"]):
            continue                                    # DEMO 0 is only fixtures
        obs.run_hidden(setup_sql)                       # reset the test rows
        out.append("\n## %s\n" % title)
        if demo["intro"]:
            out.append(" ".join(demo["intro"]) + "\n")
        sess = {"A": Session("A"), "B": Session("B")}
        step = 0
        for kind, narr, sql in demo["blocks"]:
            if kind == "SETUP":
                obs.run_hidden(sql)
                continue
            step += 1
            s = sess[kind]
            entry = {"step": step, "who": kind, "narr": narr, "sql": sql, "out": None, "released": None, "observer": None}
            s.send(sql)
            if s.collect(BLOCK_WAIT):
                entry["out"] = s.output()
            else:
                entry["out"] = None                       # still blocked
                s.pending_entry = entry
                entry["observer"] = obs.run_hidden(OBSERVER_SQL)
            out.append(render(entry))
            # did sending this block release the other session?
            other = sess["B" if kind == "A" else "A"]
            if other.pending_entry is not None and other.collect(RELEASE_WAIT):
                pe = other.pending_entry
                pe["released"] = other.output()
                out.append("\n> **Session %s is released** (its earlier statement from step %d now completes) and returns:\n\n```text\n%s\n```\n"
                           % (pe["who"], pe["step"], pe["released"]))
                other.pending_entry = None
        for name, s in sess.items():                      # anything still waiting?
            if s.pending_entry is not None:
                if s.collect(4):
                    pe = s.pending_entry
                    out.append("\n> **Session %s is released** and returns:\n\n```text\n%s\n```\n" % (pe["who"], s.output()))
                else:
                    out.append("\n> Session %s was still waiting at the end of the demo.\n" % name)
        for s in sess.values():
            s.close()

    if cleanup_sql:
        obs.run_hidden(cleanup_sql)
    obs.close()
    os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
    with open(OUT_FILE, "w") as f:
        f.write("\n".join(out) + "\n")
    print("Wrote", OUT_FILE)


def render(e):
    parts = ["\n**Step %d, session %s**\n" % (e["step"], e["who"])]
    if e["narr"]:
        parts.append("> " + " ".join(e["narr"]) + "\n")
    parts.append("```sql\n%s\n```\n" % e["sql"])
    if e["out"] is None:
        parts.append("Result: *no reply yet, this statement is waiting for a lock held by the other session.*\n")
        if e["observer"]:
            parts.append("Observer session (`pg_stat_activity`) at that moment:\n\n```text\n%s\n```\n" % e["observer"])
    else:
        parts.append("```text\n%s\n```\n" % (e["out"] or "(no output)"))
    return "\n".join(parts)


if __name__ == "__main__":
    main()
