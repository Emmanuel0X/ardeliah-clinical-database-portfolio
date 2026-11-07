#!/usr/bin/env bash
# =====================================================================
# Imports the sample documents exported from PostgreSQL into MongoDB.
# Portfolio 4: NoSQL and Advanced Data Models
#
# Prerequisites: MongoDB Database Tools (mongoimport), a running MongoDB,
# and collections created by create-collections.js (so the validators and
# indexes are in force while loading, which doubles as a test of them:
# mongoimport stops reporting success if a document fails validation).
#
# Usage:   ./import-data.sh                         (local MongoDB)
#          MONGO_URI="mongodb+srv://..." ./import-data.sh   (Atlas)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

URI="${MONGO_URI:-mongodb://localhost:27017}"
DB="ardeliah_nosql"

# Parents first is not required in MongoDB (no foreign keys), but this
# order mirrors the relational load order and reads naturally.
for c in users staff icd_codes medications lab_tests doctors patients appointments consultations; do
  echo "== importing $c"
  mongoimport --uri "$URI" --db "$DB" --collection "$c" --file "data/$c.ndjson"
done

echo "== document counts"
mongosh "$URI/$DB" --quiet --eval '
  db.getCollectionNames().sort().forEach(function (c) { print(c.padEnd(14) + db.getCollection(c).countDocuments()); })'
