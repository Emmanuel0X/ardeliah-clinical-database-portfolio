// =====================================================================
// Ardeliah Clinical System: MongoDB collections, validators and indexes
// Portfolio 4: NoSQL and Advanced Data Models
//
// Run with mongosh (MongoDB 6.0 or later, local install or Atlas):
//   mongosh "mongodb://localhost:27017" --file create-collections.js
//
// Re-runnable: it drops and recreates the database collections.
//
// Design in one paragraph (details in nosql-model.md): data that is
// created and read together is EMBEDDED in one document (a consultation
// holds its diagnoses, prescriptions and lab requests; a patient holds
// their medical history; a doctor holds their schedule). Data that is
// shared, changes independently or grows without bound is REFERENCED by
// id (appointments point to patients and doctors; reference lists such as
// ICD codes and medications are their own collections).
// =====================================================================
db = db.getSiblingDB("ardeliah_nosql");

["users", "staff", "patients", "doctors", "appointments", "consultations",
 "icd_codes", "medications", "lab_tests"].forEach(function (name) {
  db.getCollection(name).drop();
});

// Reusable pieces of JSON Schema ---------------------------------------
var severity = ["MILD", "MODERATE", "SEVERE"];
var timeOfDay = "^([01][0-9]|2[0-3]):[0-5][0-9]$";          // HH:MM, 24 hour
var icdPattern = "^[A-Z][0-9]{2}(\\.[0-9A-Z]{1,4})?$";        // e.g. B50.9, I10, A09

// ---------------------------------------------------------------------
// patients: demographics, contact and medical history in one document.
// Note: a validator cannot compare against "today", so the relational
// rule date_of_birth <= CURRENT_DATE has to live in the application.
// ---------------------------------------------------------------------
db.createCollection("patients", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["first_name", "last_name", "date_of_birth", "gender", "contact", "medical_history"],
    properties: {
      first_name:    { bsonType: "string", minLength: 1 },
      last_name:     { bsonType: "string", minLength: 1 },
      date_of_birth: { bsonType: "date" },
      gender:        { enum: ["M", "F", "O"] },
      blood_group:   { enum: ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"] },
      registered_on: { bsonType: "date" },
      contact: {
        bsonType: "object",
        properties: {
          phone:   { bsonType: "string" },
          email:   { bsonType: "string", pattern: "^[^@\\s]+@[^@\\s]+$" },
          address: { bsonType: "string" }
        }
      },
      medical_history: {
        bsonType: "array",
        items: {
          bsonType: "object",
          required: ["condition", "noted_on"],
          properties: {
            condition: { bsonType: "string" },
            noted_on:  { bsonType: "date" },
            notes:     { bsonType: "string" }
          }
        }
      }
    }
  } },
  validationLevel: "strict",
  validationAction: "error"
});

// ---------------------------------------------------------------------
// doctors: profile, specialisation name (copied, it rarely changes) and
// the weekly schedule embedded.
// ---------------------------------------------------------------------
db.createCollection("doctors", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["first_name", "last_name", "licence_no", "specialisation", "schedule"],
    properties: {
      first_name:     { bsonType: "string", minLength: 1 },
      last_name:      { bsonType: "string", minLength: 1 },
      licence_no:     { bsonType: "string", minLength: 1 },
      specialisation: { bsonType: "string", minLength: 1 },
      phone:          { bsonType: "string" },
      schedule: {
        bsonType: "array",
        items: {
          bsonType: "object",
          required: ["day_of_week", "start", "end"],
          properties: {
            day_of_week: { bsonType: "number", minimum: 1, maximum: 7 },   // ISO: 1 = Monday
            start:       { bsonType: "string", pattern: timeOfDay },
            end:         { bsonType: "string", pattern: timeOfDay }
          }
        }
      }
    }
  } },
  validationLevel: "strict",
  validationAction: "error"
});

// ---------------------------------------------------------------------
// appointments: referenced by patient_id / doctor_id, with the two names
// copied in so list screens need no lookups ("extended reference").
// slot_active is false for cancelled appointments; it exists so that a
// partial unique index can protect the slot (see the indexes below).
// ---------------------------------------------------------------------
db.createCollection("appointments", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["patient_id", "doctor_id", "scheduled_at", "status", "slot_active"],
    properties: {
      patient_id:   { bsonType: "number" },
      patient_name: { bsonType: "string" },
      doctor_id:    { bsonType: "number" },
      doctor_name:  { bsonType: "string" },
      scheduled_at: { bsonType: "date" },
      status:       { enum: ["SCHEDULED", "CHECKED_IN", "COMPLETED", "CANCELLED", "NO_SHOW"] },
      slot_active:  { bsonType: "bool" },
      reason:       { bsonType: "string" },
      booked_by_staff_id: { bsonType: "number" }
    }
  } },
  validationLevel: "strict",
  validationAction: "error"
});

// ---------------------------------------------------------------------
// consultations: the clinical aggregate. Everything that happens during
// a visit lives in one document, so one read returns the whole visit and
// one write changes it atomically.
// ---------------------------------------------------------------------
db.createCollection("consultations", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["appointment_id", "patient_id", "doctor_id", "consulted_at",
               "diagnoses", "prescriptions", "lab_requests"],
    properties: {
      appointment_id: { bsonType: "number" },
      patient_id:     { bsonType: "number" },
      doctor_id:      { bsonType: "number" },
      consulted_at:   { bsonType: "date" },
      clinical_notes: { bsonType: "string" },
      diagnoses: {
        bsonType: "array",
        items: {
          bsonType: "object",
          required: ["icd_code", "severity"],
          properties: {
            icd_code:    { bsonType: "string", pattern: icdPattern },
            description: { bsonType: "string" },
            severity:    { enum: severity },
            notes:       { bsonType: "string" }
          }
        }
      },
      prescriptions: {
        bsonType: "array",
        items: {
          bsonType: "object",
          required: ["prescription_id", "issued_at", "status", "items"],
          properties: {
            prescription_id: { bsonType: "number" },
            issued_at:       { bsonType: "date" },
            status:          { enum: ["ISSUED", "DISPENSED", "CANCELLED", "EXPIRED"] },
            items: {
              bsonType: "array",
              minItems: 1,
              items: {
                bsonType: "object",
                required: ["medication", "dosage", "frequency", "duration_days"],
                properties: {
                  medication: {
                    bsonType: "object",
                    required: ["generic_name", "form", "strength"],
                    properties: {
                      generic_name: { bsonType: "string" },
                      form:         { bsonType: "string" },
                      strength:     { bsonType: "string" }
                    }
                  },
                  dosage:        { bsonType: "string" },
                  frequency:     { bsonType: "string" },
                  duration_days: { bsonType: "number", minimum: 1 }
                }
              }
            }
          }
        }
      },
      lab_requests: {
        bsonType: "array",
        items: {
          bsonType: "object",
          required: ["lab_request_id", "test", "priority", "status", "requested_at"],
          properties: {
            lab_request_id: { bsonType: "number" },
            test: {
              bsonType: "object",
              required: ["name"],
              properties: { name: { bsonType: "string" }, unit: { bsonType: "string" } }
            },
            priority:     { enum: ["ROUTINE", "URGENT"] },
            status:       { enum: ["REQUESTED", "COLLECTED", "COMPLETED", "CANCELLED"] },
            requested_at: { bsonType: "date" },
            result: {                       // absent until the technician reports
              bsonType: "object",
              required: ["value", "abnormal", "recorded_at", "technician_id"],
              properties: {
                value:         { bsonType: "number" },
                abnormal:      { bsonType: "bool" },
                comment:       { bsonType: "string" },
                recorded_at:   { bsonType: "date" },
                technician_id: { bsonType: "number" }
              }
            }
          }
        }
      }
    }
  } },
  validationLevel: "strict",
  validationAction: "error"
});

// ---------------------------------------------------------------------
// Authentication data is kept apart from clinical data, so that it can
// get different access rules, backups and encryption.
// ---------------------------------------------------------------------
db.createCollection("users", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["username", "role", "is_active", "password_hash"],
    properties: {
      username:      { bsonType: "string", minLength: 3 },
      role:          { enum: ["PATIENT", "DOCTOR", "RECEPTIONIST", "LAB_TECHNICIAN", "ADMIN"] },
      is_active:     { bsonType: "bool" },
      password_hash: { bsonType: "string" }
    }
  } }
});

// Small reference collections: no validators needed beyond the basics.
db.createCollection("staff");
db.createCollection("icd_codes");
db.createCollection("medications");
db.createCollection("lab_tests");

// =====================================================================
// Indexes. Each one is there for a query in queries.js.
// =====================================================================

// Reception looks patients up by name (Q1).
db.patients.createIndex({ last_name: 1, first_name: 1 });

// Email must be unique, but only for patients who have one (walk-in
// patients may have none). Partial index = unique only where it exists.
db.patients.createIndex(
  { "contact.email": 1 },
  { unique: true, partialFilterExpression: { "contact.email": { $exists: true } } }
);

// "My appointments, newest first" (Q2).
db.appointments.createIndex({ patient_id: 1, scheduled_at: -1 });

// DOUBLE-BOOKING GUARD, the equivalent of uq_doctor_slot_active in
// PostgreSQL: one live appointment per doctor and time. Cancelled
// appointments have slot_active = false, so they are ignored and the slot
// can be rebooked. As in Portfolio 2, this one index also serves the
// doctor's day/week sheet (Q5), because that query asks for
// slot_active: true as well. (No separate doctor_id + scheduled_at index
// is created: two indexes with the same key pattern can be rejected
// depending on the server version.)
db.appointments.createIndex(
  { doctor_id: 1, scheduled_at: 1 },
  { name: "uq_doctor_slot_active", unique: true, partialFilterExpression: { slot_active: true } }
);

// A patient's complete clinical history, newest first (Q3).
db.consultations.createIndex({ patient_id: 1, consulted_at: -1 });

// Diagnosis search by ICD code, e.g. malaria cases in a period (Q9).
// This is a multikey index: one entry per element of the diagnoses array.
db.consultations.createIndex({ "diagnoses.icd_code": 1, consulted_at: -1 });

// The laboratory work queue (Q10) filters on the status of lab requests
// inside the array, also a multikey index. (In PostgreSQL a partial index
// covered only the pending rows; here it is kept simple and complete.)
db.consultations.createIndex({ "lab_requests.status": 1, consulted_at: 1 });

db.users.createIndex({ username: 1 }, { unique: true });

print("Collections: " + db.getCollectionNames().sort().join(", "));
