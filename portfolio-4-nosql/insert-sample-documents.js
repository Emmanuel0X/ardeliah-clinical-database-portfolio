// =====================================================================
// Ardeliah Clinical System: hand-written example documents
// Portfolio 4: NoSQL and Advanced Data Models
//
// Run after create-collections.js and import-data.sh:
//   mongosh "mongodb://localhost:27017" --file insert-sample-documents.js
//
// These documents are written by hand (ids 900001 and up, so they never
// collide with the imported data) to show clearly WHAT IS EMBEDDED and
// WHAT IS REFERENCED. Re-running the script resets them.
//
//   EMBEDDED (copied inside the document that uses it):
//     patient.contact, patient.medical_history[]         read with the patient
//     doctor.schedule[]                                  read with the doctor
//     consultation.diagnoses[]                           created with the visit
//     consultation.prescriptions[].items[]               created with the visit
//     consultation.lab_requests[].result                 belongs to one request
//
//   REFERENCED (stored once, pointed to by an id):
//     appointment.patient_id -> patients._id
//     appointment.doctor_id  -> doctors._id
//     consultation.appointment_id -> appointments._id
//     lab_requests[].result.technician_id -> staff._id
//
//   COPIED ON PURPOSE (a snapshot that must not change later):
//     diagnoses[].description, items[].medication.{generic_name,form,strength},
//     lab_requests[].test.name. A medical record must show the drug as it was
//     prescribed, even if the pharmacy catalogue is later edited.
//     appointment.patient_name / doctor_name are copied for fast list screens.
// =====================================================================
db = db.getSiblingDB("ardeliah_nosql");

["patients", "appointments", "consultations"].forEach(function (c) {
  db.getCollection(c).deleteMany({ _id: { $gte: 900000 } });
});

// ---------------------------------------------------------------------
// Two patients. The first has a history and an email; the second is a
// walk-in with no email and no blood group. Documents in one collection
// do not have to have identical fields: this is the "flexible schema".
// ---------------------------------------------------------------------
db.patients.insertMany([
  {
    _id: 900001,
    first_name: "Zainab", last_name: "Musa",
    date_of_birth: ISODate("1988-05-17T00:00:00Z"),
    gender: "F", blood_group: "B+",
    contact: { phone: "08090001111", email: "zainab.musa@example.com", address: "Jabi, Abuja" },
    registered_on: ISODate("2026-11-01T00:00:00Z"),
    medical_history: [
      { condition: "Asthma", noted_on: ISODate("2015-03-02T00:00:00Z"), notes: "Uses salbutamol when needed" },
      { condition: "Penicillin allergy", noted_on: ISODate("2019-08-12T00:00:00Z") }
    ]
  },
  {
    _id: 900002,
    first_name: "Kunle", last_name: "Adebayo",
    date_of_birth: ISODate("1979-12-03T00:00:00Z"),
    gender: "M",
    contact: { phone: "08090002222", address: "Wuse II, Abuja" },
    registered_on: ISODate("2026-11-02T00:00:00Z"),
    medical_history: []
  }
]);

// ---------------------------------------------------------------------
// Appointments reference doctors 1 and 2 (loaded by import-data.sh).
// The date is in March 2027, after every imported appointment.
// ---------------------------------------------------------------------
db.appointments.insertMany([
  { _id: 900001, patient_id: 900001, patient_name: "Zainab Musa",
    doctor_id: 1, doctor_name: "Dr Aminu Ibrahim",
    scheduled_at: ISODate("2027-03-10T08:00:00Z"), status: "COMPLETED", slot_active: true,
    reason: "Wheeze and fatigue", booked_by_staff_id: 1 },
  { _id: 900002, patient_id: 900002, patient_name: "Kunle Adebayo",
    doctor_id: 2, doctor_name: "Dr Chiamaka Eze",
    scheduled_at: ISODate("2027-03-10T09:00:00Z"), status: "SCHEDULED", slot_active: true,
    reason: "Blood pressure check", booked_by_staff_id: 1 }
]);

// ---------------------------------------------------------------------
// One consultation: the whole visit in a single document.
//   - two diagnoses (embedded array)
//   - one prescription with two drug lines (array inside an array)
//   - two lab requests: one reported, one still waiting (no "result" yet)
// ---------------------------------------------------------------------
db.consultations.insertOne({
  _id: 900001,
  appointment_id: 900001,
  patient_id: 900001,
  doctor_id: 1,
  consulted_at: ISODate("2027-03-10T08:10:00Z"),
  clinical_notes: "Wheeze on auscultation, no fever. Known asthma. Looks pale; check blood count.",
  diagnoses: [
    { icd_code: "J45.9", description: "Asthma, unspecified", severity: "MODERATE", notes: "Poor control this month" },
    { icd_code: "J06.9", description: "Acute upper respiratory infection, unspecified", severity: "MILD" }
  ],
  prescriptions: [
    { prescription_id: 900001, issued_at: ISODate("2027-03-10T08:40:00Z"), status: "ISSUED",
      items: [
        { medication: { generic_name: "Salbutamol", form: "inhaler", strength: "100 mcg" },
          dosage: "2 puffs", frequency: "every 6 hours as needed", duration_days: 14 },
        { medication: { generic_name: "Paracetamol", form: "tablet", strength: "500 mg" },
          dosage: "2 tablets", frequency: "every 6 hours as needed", duration_days: 3 }
      ] }
  ],
  lab_requests: [
    { lab_request_id: 900001, test: { name: "Haemoglobin", unit: "g/dL" },
      priority: "ROUTINE", status: "COMPLETED", requested_at: ISODate("2027-03-10T08:15:00Z"),
      result: { value: 10.8, abnormal: true, comment: "Mild anaemia",
                recorded_at: ISODate("2027-03-10T09:05:00Z"), technician_id: 2 } },
    { lab_request_id: 900002, test: { name: "White blood cell count", unit: "x10^9/L" },
      priority: "URGENT", status: "REQUESTED", requested_at: ISODate("2027-03-10T08:16:00Z") }
  ]
});

print("Inserted: " + db.patients.countDocuments({ _id: { $gte: 900000 } }) + " patients, " +
      db.appointments.countDocuments({ _id: { $gte: 900000 } }) + " appointments, " +
      db.consultations.countDocuments({ _id: { $gte: 900000 } }) + " consultation");
printjson(db.consultations.findOne({ _id: 900001 }));
