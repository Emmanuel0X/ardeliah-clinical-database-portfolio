// =====================================================================
// Ardeliah Clinical System: MongoDB read queries (find and aggregate)
// Portfolio 4: NoSQL and Advanced Data Models
//
// Run after create-collections.js and import-data.sh:
//   mongosh "mongodb://localhost:27017" --file queries.js
//
// These queries only READ. Writes are in write-examples.js.
// Many of them answer the same business questions as the SQL queries in
// Portfolio 2, so the two models can be compared (see suitability-analysis.md).
// A copy of every result is kept in the variable `results`, which the
// verification harness (verification/run-with-mingo.mjs) reads.
// =====================================================================
db = db.getSiblingDB("ardeliah_nosql");

var results = {};
function show(title, value) {
  results[title] = value;
  print("\n=== " + title);
  printjson(value);
}

// ---------------------------------------------------------------------
// Q1  find with a filter, projection, sort and limit
// Reception looks up a patient by name (index: last_name, first_name).
// ---------------------------------------------------------------------
show("Q1 patient lookup by name",
  db.patients.find(
    { last_name: "Okeke", first_name: "Chinedu" },
    { first_name: 1, last_name: 1, date_of_birth: 1, "contact.phone": 1 }
  ).sort({ date_of_birth: 1 }).limit(5).toArray());

// ---------------------------------------------------------------------
// Q2  A patient's appointments, newest first
// One collection, no join: the doctor's name is stored in the appointment.
// (index: patient_id, scheduled_at desc)
// ---------------------------------------------------------------------
show("Q2 appointments of patient 12, newest first",
  db.appointments.find(
    { patient_id: 12 },
    { _id: 0, scheduled_at: 1, status: 1, doctor_name: 1, reason: 1 }
  ).sort({ scheduled_at: -1 }).limit(5).toArray());

// ---------------------------------------------------------------------
// Q3  A patient's clinical history from ONE collection
// In SQL this took a 6-table join (Portfolio 2, Q4). Here the diagnoses and
// the drugs are inside each consultation document. Dotted paths reach
// into the embedded arrays. (index: patient_id, consulted_at desc)
// ---------------------------------------------------------------------
show("Q3 clinical history of patient 12",
  db.consultations.find(
    { patient_id: 12 },
    { _id: 0, consulted_at: 1, "diagnoses.icd_code": 1, "prescriptions.items.medication.generic_name": 1 }
  ).sort({ consulted_at: -1 }).limit(3).toArray());

// ---------------------------------------------------------------------
// Q4  One whole visit with a single read
// The complete consultation of the sample workflow: notes, diagnosis,
// two prescribed drugs and an urgent lab test with its result.
// ---------------------------------------------------------------------
show("Q4 complete consultation 1", db.consultations.findOne({ _id: 1 }));

// ---------------------------------------------------------------------
// Q5  A doctor's week sheet
// slot_active: true is included on purpose, so that the unique partial
// index uq_doctor_slot_active can answer the query (it only contains
// active slots). It means "not cancelled", like status <> 'CANCELLED' in SQL.
// ---------------------------------------------------------------------
show("Q5 week sheet of doctor 12 (12 to 16 Oct 2026)",
  db.appointments.find(
    { doctor_id: 12, slot_active: true,
      scheduled_at: { $gte: ISODate("2026-10-12T00:00:00Z"), $lt: ISODate("2026-10-17T00:00:00Z") } },
    { _id: 0, scheduled_at: 1, status: 1, patient_name: 1, reason: 1 }
  ).sort({ scheduled_at: 1 }).toArray());

// ---------------------------------------------------------------------
// Q6  Aggregation: diagnoses per ICD code (unwind, group, conditional sum)
// $unwind turns each element of the diagnoses array into its own row.
// ---------------------------------------------------------------------
show("Q6 diagnoses per ICD code",
  db.consultations.aggregate([
    { $unwind: "$diagnoses" },
    { $group: {
        _id: "$diagnoses.icd_code",
        description: { $first: "$diagnoses.description" },
        total: { $sum: 1 },
        severe: { $sum: { $cond: [{ $eq: ["$diagnoses.severity", "SEVERE"] }, 1, 0] } }
    } },
    { $sort: { total: -1, _id: 1 } }
  ]).toArray());

// ---------------------------------------------------------------------
// Q7  Most prescribed medications (two levels of embedded arrays)
// ---------------------------------------------------------------------
show("Q7 prescription lines and drug-days per medication",
  db.consultations.aggregate([
    { $unwind: "$prescriptions" },
    { $unwind: "$prescriptions.items" },
    { $group: {
        _id: "$prescriptions.items.medication.generic_name",
        prescriptions: { $sum: 1 },
        total_drug_days: { $sum: "$prescriptions.items.duration_days" }
    } },
    { $sort: { total_drug_days: -1, _id: 1 } },
    { $limit: 5 }
  ]).toArray());

// ---------------------------------------------------------------------
// Q8  Share of abnormal results per lab test
// A lab request without a result has no "result" field, so $match on its
// existence keeps only reported results.
// ---------------------------------------------------------------------
show("Q8 abnormal lab results per test",
  db.consultations.aggregate([
    { $unwind: "$lab_requests" },
    { $match: { "lab_requests.result": { $exists: true } } },
    { $group: {
        _id: "$lab_requests.test.name",
        results: { $sum: 1 },
        abnormal: { $sum: { $cond: ["$lab_requests.result.abnormal", 1, 0] } }
    } },
    { $project: { results: 1, abnormal: 1,
                  abnormal_pct: { $round: [{ $multiply: [{ $divide: ["$abnormal", "$results"] }, 100] }, 1] } } },
    { $sort: { abnormal_pct: -1, _id: 1 } }
  ]).toArray());

// ---------------------------------------------------------------------
// Q9  Patients diagnosed with malaria since 1 October 2026
// Matching a value inside an array needs no join and no subquery.
// (index: diagnoses.icd_code, consulted_at desc)
// ---------------------------------------------------------------------
show("Q9 malaria patients since 1 Oct 2026 (distinct patient ids)",
  db.consultations.distinct("patient_id", {
    "diagnoses.icd_code": "B50.9",
    consulted_at: { $gte: ISODate("2026-10-01T00:00:00Z") }
  }).sort(function (a, b) { return a - b; }));

// ---------------------------------------------------------------------
// Q10 Laboratory work queue: lab requests that are still open
// $elemMatch makes sure ONE array element satisfies the condition.
// The second $match then removes the other, finished elements of the
// same consultation after $unwind. (index: lab_requests.status)
// ---------------------------------------------------------------------
show("Q10 open lab requests, oldest first",
  db.consultations.aggregate([
    { $match: { lab_requests: { $elemMatch: { status: { $in: ["REQUESTED", "COLLECTED"] } } } } },
    { $unwind: "$lab_requests" },
    { $match: { "lab_requests.status": { $in: ["REQUESTED", "COLLECTED"] } } },
    { $project: { _id: 0, consultation_id: "$_id",
                  lab_request_id: "$lab_requests.lab_request_id",
                  test: "$lab_requests.test.name",
                  priority: "$lab_requests.priority",
                  status: "$lab_requests.status",
                  requested_at: "$lab_requests.requested_at" } },
    { $sort: { requested_at: 1, lab_request_id: 1 } },
    { $limit: 5 }
  ]).toArray());

// ---------------------------------------------------------------------
// Q11 Appointment outcomes per month (same question as SQL Q6)
// ---------------------------------------------------------------------
show("Q11 appointment outcomes per month, May to Oct 2026",
  db.appointments.aggregate([
    { $match: { scheduled_at: { $gte: ISODate("2026-05-01T00:00:00Z"), $lt: ISODate("2026-11-01T00:00:00Z") } } },
    { $group: {
        _id: { $dateToString: { format: "%Y-%m", date: "$scheduled_at" } },
        total: { $sum: 1 },
        completed: { $sum: { $cond: [{ $eq: ["$status", "COMPLETED"] }, 1, 0] } },
        cancelled: { $sum: { $cond: [{ $eq: ["$status", "CANCELLED"] }, 1, 0] } },
        no_show:   { $sum: { $cond: [{ $eq: ["$status", "NO_SHOW"] }, 1, 0] } }
    } },
    { $sort: { _id: 1 } }
  ]).toArray());

// ---------------------------------------------------------------------
// Q12 $lookup: the "join" of a document database
// Appointments only hold doctor_id, so finding the specialisation needs a
// $lookup into doctors. This is the price of REFERENCING instead of
// embedding: it works, but it is the query shape to avoid on hot paths.
// ---------------------------------------------------------------------
show("Q12 completed appointments per specialisation, Oct 2026",
  db.appointments.aggregate([
    { $match: { status: "COMPLETED",
                scheduled_at: { $gte: ISODate("2026-10-01T00:00:00Z"), $lt: ISODate("2026-11-01T00:00:00Z") } } },
    { $lookup: { from: "doctors", localField: "doctor_id", foreignField: "_id", as: "doctor" } },
    { $unwind: "$doctor" },
    { $group: { _id: "$doctor.specialisation", completed: { $sum: 1 } } },
    { $sort: { completed: -1, _id: 1 } }
  ]).toArray());

// ---------------------------------------------------------------------
// Q13 Statistics over an embedded array ($size inside $avg)
// ---------------------------------------------------------------------
show("Q13 diagnoses per consultation",
  db.consultations.aggregate([
    { $group: { _id: null, consultations: { $sum: 1 },
                avg_diagnoses: { $avg: { $size: "$diagnoses" } } } },
    { $project: { _id: 0, consultations: 1, avg_diagnoses: { $round: ["$avg_diagnoses", 3] } } }
  ]).toArray());
