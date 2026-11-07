// =====================================================================
// Verification harness for the MongoDB scripts of Portfolio 4
//
// WHY THIS EXISTS
//   The scripts in this folder are written for mongosh and a real MongoDB
//   server. When no server is available (it was not in the environment
//   where this portfolio was prepared), this harness runs the SAME .js files
//   unchanged against a small in-memory emulation built on the open source
//   library "mingo" (MongoDB query and aggregation semantics in JavaScript)
//   and "ajv" (JSON Schema validation).
//
// WHAT IT PROVES
//   + the scripts are syntactically valid and run to completion
//   + the find/aggregate/update logic returns sensible results
//   + all imported documents satisfy the $jsonSchema validators
//   + the aggregation results MATCH the equivalent SQL run on PostgreSQL
//
// WHAT IT DOES NOT PROVE (run these on a real MongoDB yourself)
//   - index usage and explain() plans, and the exact text of error messages
//   - that every index definition is accepted by your MongoDB version
//   - behaviour under concurrency
//   The emulator's unique-index and validator errors imitate the documented
//   MongoDB error codes (11000 and 121); they are not produced by MongoDB.
//
// USAGE (from this folder):
//   npm install
//   node run-with-mingo.mjs            # needs psql + the ardeliah database
//                                      # for the cross-check (PG* env vars)
// Output goes to ../evidence/.
// =====================================================================
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import mingo from "mingo";
import updater from "mingo/updater";
import Ajv from "ajv";

const { Query, aggregate: mingoAggregate } = mingo;
const { updateOne: mingoUpdateOne } = updater;
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, "..");
const EVIDENCE = path.join(ROOT, "evidence");
fs.mkdirSync(EVIDENCE, { recursive: true });

// ---------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------
const clone = (x) => structuredClone(x);
const isDate = (x) => x instanceof Date;

function getPath(obj, parts) {                      // dotted path, flattening arrays
  if (Array.isArray(obj)) return obj.flatMap((o) => getPath(o, parts));
  if (parts.length === 0) return [obj];
  if (obj === null || typeof obj !== "object") return [];
  return getPath(obj[parts[0]], parts.slice(1));
}

function reviveEJSON(v) {                           // {"$date": "..."} -> Date
  if (Array.isArray(v)) return v.map(reviveEJSON);
  if (v && typeof v === "object") {
    const keys = Object.keys(v);
    if (keys.length === 1 && keys[0] === "$date") return new Date(v.$date);
    for (const k of keys) v[k] = reviveEJSON(v[k]);
  }
  return v;
}

function plainForSchema(doc) {                      // Dates -> {"$date": iso} for ajv
  return JSON.parse(JSON.stringify(doc, function (k) {
    const raw = this[k];
    return isDate(raw) ? { $date: raw.toISOString() } : raw;
  }));
}

function toJsonSchema(s) {                          // MongoDB $jsonSchema -> JSON Schema
  const out = {};
  for (const k of ["required", "minLength", "pattern", "minimum", "maximum", "minItems", "enum"]) {
    if (s[k] !== undefined) out[k] = s[k];
  }
  switch (s.bsonType) {
    case "string": out.type = "string"; break;
    case "number": case "int": case "long": case "double": case "decimal": out.type = "number"; break;
    case "object": out.type = "object"; break;
    case "array": out.type = "array"; break;
    case "bool": out.type = "boolean"; break;
    case "date":
      out.type = "object"; out.required = ["$date"]; out.properties = { $date: { type: "string" } };
      break;
    case undefined: break;
    default: throw new Error("harness: unsupported bsonType " + s.bsonType);
  }
  if (s.properties) {
    out.properties = {};
    for (const [k, v] of Object.entries(s.properties)) out.properties[k] = toJsonSchema(v);
  }
  if (s.items) out.items = toJsonSchema(s.items);
  return out;
}

function mongoError(message, code, codeName) {
  const e = new Error(message);
  e.code = code; e.codeName = codeName;
  return e;
}

// ---------------------------------------------------------------------
// In-memory emulation of a MongoDB server (just what the scripts use)
// ---------------------------------------------------------------------
const ajv = new Ajv({ strict: false, allErrors: true });

class Collection {
  constructor(server, dbName, name, options = {}) {
    this.server = server; this.dbName = dbName; this.name = name;
    this.docs = []; this.indexes = []; this.maps = new Map();
    this.validate = null;
    const schema = options.validator && options.validator.$jsonSchema;
    if (schema) this.validate = ajv.compile(toJsonSchema(schema));
  }
  _ns() { return `${this.dbName}.${this.name}`; }
  _entryKey(index, doc) {
    if (index.partial && !new Query(index.partial).test(doc)) return null;
    return JSON.stringify(Object.keys(index.keys).map((f) => getPath(doc, f.split(".")).map((v) => (isDate(v) ? v.toISOString() : v))));
  }
  _checkDoc(doc) {
    if (this.validate && !this.validate(plainForSchema(doc))) {
      throw mongoError("Document failed validation", 121, "DocumentValidationFailure");
    }
  }
  _rebuildMaps() {
    this.maps = new Map();
    for (const ix of this.indexes.filter((i) => i.unique)) {
      const m = new Map();
      for (const d of this.docs) {
        const k = this._entryKey(ix, d);
        if (k !== null) {
          if (m.has(k)) throw mongoError(`E11000 duplicate key error collection: ${this._ns()} index: ${ix.name} dup key: ${k}`, 11000, "DuplicateKey");
          m.set(k, d._id);
        }
      }
      this.maps.set(ix.name, m);
    }
  }
  _checkUnique(doc, ownId) {
    for (const ix of this.indexes.filter((i) => i.unique)) {
      const k = this._entryKey(ix, doc);
      if (k === null) continue;
      const holder = this.maps.get(ix.name).get(k);
      if (holder !== undefined && holder !== ownId) {
        throw mongoError(`E11000 duplicate key error collection: ${this._ns()} index: ${ix.name} dup key: ${k}`, 11000, "DuplicateKey");
      }
    }
  }
  drop() { this.docs = []; this.indexes = []; this.maps = new Map(); return true; }
  createIndex(keys, options = {}) {
    const name = options.name || Object.entries(keys).map(([k, v]) => `${k}_${v}`).join("_");
    this.indexes.push({ name, keys, unique: !!options.unique, partial: options.partialFilterExpression || null });
    if (options.unique) this._rebuildMaps();
    return name;
  }
  insertOne(doc) {
    doc = clone(doc);
    if (doc._id === undefined) doc._id = "oid" + Math.random().toString(16).slice(2);
    this._checkDoc(doc);
    if (this.docs.some((d) => d._id === doc._id)) {
      throw mongoError(`E11000 duplicate key error collection: ${this._ns()} index: _id_ dup key: { _id: ${JSON.stringify(doc._id)} }`, 11000, "DuplicateKey");
    }
    this._checkUnique(doc, undefined);
    this.docs.push(doc);
    for (const ix of this.indexes.filter((i) => i.unique)) {
      const k = this._entryKey(ix, doc);
      if (k !== null) this.maps.get(ix.name).set(k, doc._id);
    }
    return { acknowledged: true, insertedId: doc._id };
  }
  insertMany(docs) { docs.forEach((d) => this.insertOne(d)); return { acknowledged: true, insertedCount: docs.length }; }
  find(filter = {}, projection) {
    const c = new Query(filter).find(this.docs, projection);
    const wrapper = {
      sort(spec) { c.sort(spec); return wrapper; },
      limit(n) { c.limit(n); return wrapper; },
      skip(n) { c.skip(n); return wrapper; },
      toArray() { return clone(c.all()); },
      forEach(fn) { clone(c.all()).forEach(fn); },
      count() { return c.all().length; }
    };
    return wrapper;
  }
  findOne(filter = {}, projection) { return this.find(filter, projection).limit(1).toArray()[0] || null; }
  countDocuments(filter = {}) { return new Query(filter).find(this.docs).all().length; }
  distinct(field, filter = {}) {
    const seen = new Map();
    for (const d of new Query(filter).find(this.docs).all()) {
      for (const v of getPath(d, field.split("."))) seen.set(JSON.stringify(v), v);
    }
    return [...seen.values()];
  }
  aggregate(pipeline) {
    const resolver = (name) => this.server.db(this.dbName).collection(name).docs;
    const out = clone(mingoAggregate(this.docs, pipeline, { collectionResolver: resolver }));
    return { toArray: () => out, forEach: (fn) => out.forEach(fn) };
  }
  updateOne(filter, update, options = {}) {
    const q = new Query(filter);
    const idx = this.docs.findIndex((d) => q.test(d));
    if (idx < 0) return { acknowledged: true, matchedCount: 0, modifiedCount: 0 };
    const original = this.docs[idx];
    const copy = clone(original);
    const cfg = options.arrayFilters ? { arrayFilters: options.arrayFilters } : undefined;
    const idq = { _id: copy._id };
    // mingo rejects two $set paths into the same array element; MongoDB accepts
    // them and applies them atomically. In a single-threaded emulator, applying
    // the keys one at a time gives the same end state.
    for (const [op, body] of Object.entries(update)) {
      if (op === "$set") {
        for (const [k, v] of Object.entries(body)) mingoUpdateOne([copy], idq, { $set: { [k]: v } }, cfg);
      } else {
        mingoUpdateOne([copy], idq, { [op]: body }, cfg);
      }
    }
    const changed = JSON.stringify(plainForSchema(copy)) !== JSON.stringify(plainForSchema(original));
    if (changed) {
      this._checkDoc(copy);
      this.docs[idx] = copy;
      this._rebuildMaps();
    }
    return { acknowledged: true, matchedCount: 1, modifiedCount: changed ? 1 : 0 };
  }
  deleteMany(filter) {
    const q = new Query(filter);
    const before = this.docs.length;
    this.docs = this.docs.filter((d) => !q.test(d));
    this._rebuildMaps();
    return { acknowledged: true, deletedCount: before - this.docs.length };
  }
}

class Database {
  constructor(server, name) { this.server = server; this.name = name; this.colls = new Map(); }
  collection(name) {
    if (!this.colls.has(name)) this.colls.set(name, new Collection(this.server, this.name, name));
    return this.colls.get(name);
  }
}

class Server {
  constructor() { this.dbs = new Map(); }
  db(name) {
    if (!this.dbs.has(name)) this.dbs.set(name, new Database(this, name));
    return this.dbs.get(name);
  }
  // The `db` object a mongosh script sees: db.<collection> and db helper methods.
  shellDb(name) {
    const database = this.db(name);
    const self = this;
    const methods = {
      getSiblingDB: (n) => self.shellDb(n),
      getCollection: (n) => database.collection(n),
      getCollectionNames: () => [...database.colls.keys()],
      createCollection: (n, options) => {
        database.colls.set(n, new Collection(self, name, n, options));
        return { ok: 1 };
      }
    };
    return new Proxy({}, { get: (_t, prop) => (prop in methods ? methods[prop] : database.collection(String(prop))) });
  }
}

// ---------------------------------------------------------------------
// Running the unchanged mongosh scripts
// ---------------------------------------------------------------------
function printJson(value) {
  const text = JSON.stringify(value, function (k, v) {
    const raw = this[k];
    return isDate(raw) ? "@@ISO@@" + raw.toISOString() : v;
  }, 2);
  return (text ?? "undefined").replace(/"@@ISO@@([^"]+)"/g, 'ISODate("$1")');
}

function runScript(server, file, log) {
  const code = fs.readFileSync(path.join(ROOT, file), "utf8");
  const sandbox = {
    db: server.shellDb("test"),
    ISODate: (s) => (s === undefined ? new Date() : new Date(s)),
    print: (...a) => log(a.join(" ")),
    printjson: (v) => log(printJson(v))
  };
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: file });
  return sandbox;
}

function importData(server, log) {                  // emulates import-data.sh / mongoimport
  const order = ["users", "staff", "icd_codes", "medications", "lab_tests", "doctors", "patients", "appointments", "consultations"];
  const db = server.db("ardeliah_nosql");
  for (const name of order) {
    const lines = fs.readFileSync(path.join(ROOT, "data", name + ".ndjson"), "utf8").split("\n").filter(Boolean);
    log(`== importing ${name}`);
    lines.forEach((l) => db.collection(name).insertOne(reviveEJSON(JSON.parse(l))));
    log(`(emulated mongoimport) ${lines.length} document(s) imported successfully, 0 failed (validators and unique indexes enforced)`);
  }
  log("== document counts");
  for (const name of [...db.colls.keys()].sort()) log(name.padEnd(14) + db.collection(name).docs.length);
}

// ---------------------------------------------------------------------
// Phase A: the documented order, full transcript
// ---------------------------------------------------------------------
function phaseA() {
  const lines = [];
  const log = (s) => { lines.push(s); };
  log("# Emulated run of the Portfolio 4 scripts (NOT a real MongoDB server)");
  log("# Engine: mingo (MongoDB query/aggregation semantics) + ajv (JSON Schema). See verification/run-with-mingo.mjs.");
  log("# Order: create-collections.js, import-data.sh, insert-sample-documents.js, queries.js, write-examples.js\n");
  const server = new Server();
  for (const step of ["create-collections.js", "IMPORT", "insert-sample-documents.js", "queries.js", "write-examples.js"]) {
    log(`\n############ ${step === "IMPORT" ? "import-data.sh (emulated)" : step}`);
    if (step === "IMPORT") importData(server, log);
    else runScript(server, step, log);
  }
  fs.writeFileSync(path.join(EVIDENCE, "emulated-run-output.txt"), lines.join("\n") + "\n");
  console.log("Wrote evidence/emulated-run-output.txt");
}

// ---------------------------------------------------------------------
// Phase B: compare MongoDB-style results with the same questions in PostgreSQL
// ---------------------------------------------------------------------
function psql(sql) {
  return execFileSync("psql", ["-X", "-At", "-F", "|", "-d", process.env.PGDATABASE || "ardeliah", "-c", sql],
    { encoding: "utf8" }).trim().split("\n").filter(Boolean);
}

function phaseB() {
  const server = new Server();
  const sink = () => {};
  runScript(server, "create-collections.js", sink);
  importData(server, sink);
  const sb = runScript(server, "queries.js", sink);
  const r = sb.results;
  const mdb = server.db("ardeliah_nosql");
  const N = 303;
  const iso = (ts) => `to_char((${ts}) AT TIME ZONE 'Africa/Lagos' AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS".000Z"')`;

  const checks = [];
  const add = (name, mongo, pg) => checks.push({ name, mongo, pg });

  // Reconciliation of collection contents
  const agg = (coll, pipe) => mdb.collection(coll).aggregate(pipe).toArray();
  const one = (rows) => rows.map((x) => x.n).join("|");
  add("patients", [String(mdb.collection("patients").docs.length)], psql(`SELECT count(*) FROM ardeliah.patient WHERE patient_id <= ${N}`));
  add("appointments", [String(mdb.collection("appointments").docs.length)], psql(`SELECT count(*) FROM ardeliah.appointment WHERE patient_id <= ${N}`));
  add("consultations", [String(mdb.collection("consultations").docs.length)],
    psql(`SELECT count(*) FROM ardeliah.consultation c JOIN ardeliah.appointment a USING (appointment_id) WHERE a.patient_id <= ${N}`));
  add("embedded diagnoses (total)", [one(agg("consultations", [{ $group: { _id: null, n: { $sum: { $size: "$diagnoses" } } } }]))],
    psql(`SELECT count(*) FROM ardeliah.diagnosis dg JOIN ardeliah.consultation c USING (consultation_id) JOIN ardeliah.appointment a USING (appointment_id) WHERE a.patient_id <= ${N}`));
  add("embedded prescription lines (total)", [one(agg("consultations", [{ $unwind: "$prescriptions" }, { $group: { _id: null, n: { $sum: { $size: "$prescriptions.items" } } } }]))],
    psql(`SELECT count(*) FROM ardeliah.prescription_item pi JOIN ardeliah.prescription p USING (prescription_id) JOIN ardeliah.consultation c USING (consultation_id) JOIN ardeliah.appointment a USING (appointment_id) WHERE a.patient_id <= ${N}`));
  add("embedded lab requests (total)", [one(agg("consultations", [{ $group: { _id: null, n: { $sum: { $size: "$lab_requests" } } } }]))],
    psql(`SELECT count(*) FROM ardeliah.lab_request lr JOIN ardeliah.consultation c USING (consultation_id) JOIN ardeliah.appointment a USING (appointment_id) WHERE a.patient_id <= ${N}`));

  // The queries from queries.js against their SQL equivalents
  add("Q2 appointments of patient 12 (newest 5)",
    r["Q2 appointments of patient 12, newest first"].map((x) => `${x.scheduled_at.toISOString()}|${x.status}|${x.doctor_name}`),
    psql(`SELECT ${iso("a.appointment_date + a.start_time")}, a.status, 'Dr ' || d.first_name || ' ' || d.last_name
          FROM ardeliah.appointment a JOIN ardeliah.doctor d USING (doctor_id)
          WHERE a.patient_id = 12 ORDER BY a.appointment_date DESC, a.start_time DESC LIMIT 5`));
  add("Q5 week sheet of doctor 12",
    r["Q5 week sheet of doctor 12 (12 to 16 Oct 2026)"].map((x) => `${x.scheduled_at.toISOString()}|${x.status}|${x.patient_name}`),
    psql(`SELECT ${iso("a.appointment_date + a.start_time")}, a.status, p.first_name || ' ' || p.last_name
          FROM ardeliah.appointment a JOIN ardeliah.patient p USING (patient_id)
          WHERE a.doctor_id = 12 AND a.status <> 'CANCELLED' AND a.patient_id <= ${N}
            AND a.appointment_date BETWEEN '2026-10-12' AND '2026-10-16' ORDER BY a.appointment_date, a.start_time`));
  add("Q6 diagnoses per ICD code",
    r["Q6 diagnoses per ICD code"].map((x) => `${x._id}|${x.total}|${x.severe}`),
    psql(`SELECT dg.icd_code, count(*), count(*) FILTER (WHERE dg.severity = 'SEVERE')
          FROM ardeliah.diagnosis dg JOIN ardeliah.consultation c USING (consultation_id) JOIN ardeliah.appointment a USING (appointment_id)
          WHERE a.patient_id <= ${N} GROUP BY dg.icd_code ORDER BY 2 DESC, 1`));
  add("Q7 top 5 medications by drug-days",
    r["Q7 prescription lines and drug-days per medication"].map((x) => `${x._id}|${x.prescriptions}|${x.total_drug_days}`),
    psql(`SELECT m.generic_name, count(*), sum(pi.duration_days)
          FROM ardeliah.prescription_item pi JOIN ardeliah.medication m USING (medication_id)
          JOIN ardeliah.prescription p USING (prescription_id) JOIN ardeliah.consultation c USING (consultation_id)
          JOIN ardeliah.appointment a USING (appointment_id)
          WHERE a.patient_id <= ${N} GROUP BY m.generic_name ORDER BY 3 DESC, 1 LIMIT 5`));
  add("Q8 abnormal lab results per test",
    r["Q8 abnormal lab results per test"].map((x) => `${x._id}|${x.results}|${x.abnormal}|${x.abnormal_pct}`),
    psql(`SELECT t.test_name, count(*), count(*) FILTER (WHERE lres.abnormal_flag), round(100.0 * count(*) FILTER (WHERE lres.abnormal_flag) / count(*), 1)
          FROM ardeliah.lab_result lres JOIN ardeliah.lab_request lr USING (lab_request_id)
          JOIN ardeliah.lab_test_catalog t USING (test_id) JOIN ardeliah.consultation c USING (consultation_id)
          JOIN ardeliah.appointment a USING (appointment_id)
          WHERE a.patient_id <= ${N} GROUP BY t.test_name ORDER BY 4 DESC, 1`));
  add("Q9 malaria patients since 1 Oct 2026",
    [r["Q9 malaria patients since 1 Oct 2026 (distinct patient ids)"].join(",")],
    [psql(`SELECT DISTINCT a.patient_id FROM ardeliah.diagnosis dg JOIN ardeliah.consultation c USING (consultation_id)
           JOIN ardeliah.appointment a USING (appointment_id)
           WHERE dg.icd_code = 'B50.9' AND c.consulted_at >= timestamptz '2026-10-01 00:00:00+00' AND a.patient_id <= ${N}
           ORDER BY 1`).join(",")]);
  add("Q10 open lab requests (oldest 5)",
    r["Q10 open lab requests, oldest first"].map((x) => `${x.lab_request_id}|${x.test}|${x.priority}|${x.status}`),
    psql(`SELECT lr.lab_request_id, t.test_name, lr.priority, lr.status
          FROM ardeliah.lab_request lr JOIN ardeliah.lab_test_catalog t USING (test_id)
          JOIN ardeliah.consultation c USING (consultation_id) JOIN ardeliah.appointment a USING (appointment_id)
          WHERE a.patient_id <= ${N} AND lr.status IN ('REQUESTED', 'COLLECTED')
          ORDER BY lr.requested_at, lr.lab_request_id LIMIT 5`));
  add("Q11 appointment outcomes per month",
    r["Q11 appointment outcomes per month, May to Oct 2026"].map((x) => `${x._id}|${x.total}|${x.completed}|${x.cancelled}|${x.no_show}`),
    psql(`SELECT to_char(appointment_date, 'YYYY-MM'), count(*), count(*) FILTER (WHERE status = 'COMPLETED'),
                 count(*) FILTER (WHERE status = 'CANCELLED'), count(*) FILTER (WHERE status = 'NO_SHOW')
          FROM ardeliah.appointment WHERE patient_id <= ${N} AND appointment_date >= '2026-05-01' AND appointment_date < '2026-11-01'
          GROUP BY 1 ORDER BY 1`));
  add("Q12 completed appointments per specialisation (Oct 2026)",
    r["Q12 completed appointments per specialisation, Oct 2026"].map((x) => `${x._id}|${x.completed}`),
    psql(`SELECT s.specialisation_name, count(*) FROM ardeliah.appointment a
          JOIN ardeliah.doctor d USING (doctor_id) JOIN ardeliah.specialisation s USING (specialisation_id)
          WHERE a.patient_id <= ${N} AND a.status = 'COMPLETED' AND a.appointment_date >= '2026-10-01' AND a.appointment_date < '2026-11-01'
          GROUP BY s.specialisation_name ORDER BY 2 DESC, 1`));
  add("Q13 consultations and average diagnoses",
    r["Q13 diagnoses per consultation"].map((x) => `${x.consultations}|${x.avg_diagnoses}`),
    psql(`SELECT count(*), round(avg(n), 3) FROM (
            SELECT c.consultation_id, count(dg.diagnosis_id) AS n FROM ardeliah.consultation c
            JOIN ardeliah.appointment a USING (appointment_id)
            LEFT JOIN ardeliah.diagnosis dg USING (consultation_id)
            WHERE a.patient_id <= ${N} GROUP BY c.consultation_id) x`));

  let pass = 0;
  const md = ["# Cross-check: MongoDB-style results versus PostgreSQL\n",
    "Each check runs the same business question twice: once as a MongoDB find/aggregate from `queries.js` (executed by the in-memory emulator in `verification/run-with-mingo.mjs` on the exported documents) and once as SQL on the original PostgreSQL tables, restricted to the same 303 exported patients. If the document model and the pipelines are right, the rows must be identical.\n",
    "| Check | Rows compared | Result |", "|---|---|---|"];
  const details = [];
  for (const c of checks) {
    const same = JSON.stringify(c.mongo) === JSON.stringify(c.pg);
    if (same) pass++;
    md.push(`| ${c.name} | ${c.pg.length} | ${same ? "MATCH" : "DIFFERENT"} |`);
    details.push(`\n## ${c.name}: ${same ? "match" : "DIFFERENT"}\n\nMongoDB side:\n\n\`\`\`\n${c.mongo.join("\n")}\n\`\`\`\n\nPostgreSQL side:\n\n\`\`\`\n${c.pg.join("\n")}\n\`\`\``);
  }
  md.push(`\n**${pass} of ${checks.length} checks match.**\n`, ...details);
  fs.writeFileSync(path.join(EVIDENCE, "cross-check-postgres-vs-mongodb.md"), md.join("\n") + "\n");
  console.log(`Cross-check: ${pass} of ${checks.length} match. Wrote evidence/cross-check-postgres-vs-mongodb.md`);
  if (pass !== checks.length) process.exitCode = 1;
}

phaseA();
try { phaseB(); } catch (e) {
  console.error("Cross-check skipped or failed:", e.message);
  process.exitCode = 1;
}
