// =====================================================================
// Ardeliah Clinical System: MongoDB write examples and constraint tests
// Portfolio 4: NoSQL and Advanced Data Models
//
// Run after insert-sample-documents.js (which creates the documents these
// examples change; re-run that script to reset them):
//   mongosh "mongodb://localhost:27017" --file write-examples.js
//
// W1-W2 show that a change touching several "rows" in the relational model
// is ONE atomic update of ONE document here. W3-W6 test the rules that
// the database itself enforces: the unique slot index and the validators.
// =====================================================================
db = db.getSiblingDB("ardeliah_nosql");

// ---------------------------------------------------------------------
// W1  A technician reports a lab result
// Relational: INSERT into lab_result and UPDATE lab_request, in a transaction.
// Document: one updateOne on one document, atomic by itself. arrayFilters
// picks the array element, and requiring status REQUESTED makes the update
// a safe no-op if somebody already reported it (no double reporting).
// ---------------------------------------------------------------------
print("\n=== W1 record a lab result");
var w1 = db.consultations.updateOne(
  { _id: 900001 },
  { $set: {
      "lab_requests.$[r].status": "COMPLETED",
      "lab_requests.$[r].result": { value: 14.2, abnormal: true, comment: "Raised, suggests infection",
                                    recorded_at: ISODate("2027-03-10T09:30:00Z"), technician_id: 9 } } },
  { arrayFilters: [{ "r.lab_request_id": 900002, "r.status": "REQUESTED" }] });
printjson({ matchedCount: w1.matchedCount, modifiedCount: w1.modifiedCount });
printjson(db.consultations.findOne({ _id: 900001 }, { _id: 0, "lab_requests": 1 }).lab_requests[1]);

print("\n--- W1 again: the request is no longer REQUESTED, so nothing changes");
var w1b = db.consultations.updateOne(
  { _id: 900001 },
  { $set: { "lab_requests.$[r].status": "COMPLETED" } },
  { arrayFilters: [{ "r.lab_request_id": 900002, "r.status": "REQUESTED" }] });
printjson({ matchedCount: w1b.matchedCount, modifiedCount: w1b.modifiedCount });

// ---------------------------------------------------------------------
// W2  The doctor adds a diagnosis after the result arrives
// $push appends to the embedded array in place.
// ---------------------------------------------------------------------
print("\n=== W2 add a diagnosis");
var w2 = db.consultations.updateOne(
  { _id: 900001 },
  { $push: { diagnoses: { icd_code: "D64.9", description: "Anaemia, unspecified", severity: "MILD",
                          notes: "Haemoglobin 10.8 g/dL" } } });
printjson({ matchedCount: w2.matchedCount, modifiedCount: w2.modifiedCount });
printjson(db.consultations.findOne({ _id: 900001 }, { _id: 0, "diagnoses.icd_code": 1 }).diagnoses.map(function (d) { return d.icd_code; }));

// ---------------------------------------------------------------------
// W3  Cancel an appointment and rebook the same slot
// Cancelling sets BOTH status and slot_active, in one atomic update.
// Because the unique index only covers slot_active: true, the slot is free.
// ---------------------------------------------------------------------
print("\n=== W3 cancel and rebook the slot");
var w3a = db.appointments.updateOne(
  { _id: 900002, status: "SCHEDULED" },
  { $set: { status: "CANCELLED", slot_active: false } });
printjson({ cancelled: w3a.modifiedCount });
db.appointments.insertOne({
  _id: 900003, patient_id: 900001, patient_name: "Zainab Musa",
  doctor_id: 2, doctor_name: "Dr Chiamaka Eze",
  scheduled_at: ISODate("2027-03-10T09:00:00Z"), status: "SCHEDULED", slot_active: true,
  reason: "Follow-up", booked_by_staff_id: 1 });
print("rebooked doctor 2 at 09:00 as appointment 900003");

// ---------------------------------------------------------------------
// W4  Double booking is rejected by the unique partial index
// Same doctor and time as appointment 900003, which is active.
// Expected: error code 11000 (duplicate key).
// ---------------------------------------------------------------------
print("\n=== W4 double booking attempt");
try {
  db.appointments.insertOne({
    _id: 900004, patient_id: 900002, patient_name: "Kunle Adebayo",
    doctor_id: 2, doctor_name: "Dr Chiamaka Eze",
    scheduled_at: ISODate("2027-03-10T09:00:00Z"), status: "SCHEDULED", slot_active: true,
    reason: "Blood pressure check", booked_by_staff_id: 1 });
  print("UNEXPECTED: the second booking was accepted");
} catch (e) {
  print("Rejected as expected. code=" + e.code + " (" + (e.codeName || "DuplicateKey") + ")");
  print(String(e.message).split("\n")[0].slice(0, 160));
}

// ---------------------------------------------------------------------
// W5  The validator refuses a prescription with a duration of 0 days
// The relational CHECK (duration_days > 0) became schema validation.
// Expected: error code 121 (Document failed validation).
// ---------------------------------------------------------------------
print("\n=== W5 invalid prescription (duration_days = 0)");
try {
  db.consultations.insertOne({
    _id: 900005, appointment_id: 900002, patient_id: 900002, doctor_id: 2,
    consulted_at: ISODate("2027-03-10T09:10:00Z"),
    diagnoses: [],
    prescriptions: [ { prescription_id: 900005, issued_at: ISODate("2027-03-10T09:30:00Z"), status: "ISSUED",
      items: [ { medication: { generic_name: "Amlodipine", form: "tablet", strength: "5 mg" },
                 dosage: "1 tablet", frequency: "once daily", duration_days: 0 } ] } ],
    lab_requests: [] });
  print("UNEXPECTED: the invalid consultation was accepted");
} catch (e) {
  print("Rejected as expected. code=" + e.code + " (" + (e.codeName || "DocumentValidationFailure") + ")");
  print(String(e.message).split("\n")[0].slice(0, 160));
}

// ---------------------------------------------------------------------
// W6  The validator refuses an unknown gender code
// ---------------------------------------------------------------------
print("\n=== W6 invalid patient (gender = 'X')");
try {
  db.patients.insertOne({
    _id: 900006, first_name: "Test", last_name: "Patient",
    date_of_birth: ISODate("1990-01-01T00:00:00Z"), gender: "X",
    contact: { phone: "08000000000" }, medical_history: [] });
  print("UNEXPECTED: the invalid patient was accepted");
} catch (e) {
  print("Rejected as expected. code=" + e.code + " (" + (e.codeName || "DocumentValidationFailure") + ")");
  print(String(e.message).split("\n")[0].slice(0, 160));
}

print("\nDone. Re-run insert-sample-documents.js to reset the example documents.");
