-- Master migration runner
-- Run this in Supabase SQL Editor to execute all migrations in order

-- 001: Artists and Labels
\i 001_create_artists_labels.sql

-- 002: Certification-Artists junction
\i 002_create_certification_artists.sql

-- 003: Certification history & level enum
\i 003_create_certification_history.sql

-- 004: Migrate existing data
\i 004_migrate_existing_data.sql

-- 005: Indexes, RLS, helpers
\i 005_indexes_rls_helpers.sql

-- ─── Verification queries ───
SELECT '=== MIGRATION COMPLETE ===' AS status;

SELECT 'Tables created:' AS check;
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('artists', 'labels', 'certifications', 'certification_artists', 'certification_history')
ORDER BY table_name;

SELECT 'Certifications count:' AS check, COUNT(*) FROM certifications;
SELECT 'Artists count:' AS check, COUNT(*) FROM artists;
SELECT 'Labels count:' AS check, COUNT(*) FROM labels;
SELECT 'Junction rows:' AS check, COUNT(*) FROM certification_artists;
SELECT 'History rows:' AS check, COUNT(*) FROM certification_history;

SELECT 'Level distribution:' AS check;
SELECT * FROM certification_level_distribution;

SELECT 'Sample with artists & history:' AS check;
SELECT
  c.titre,
  c.certification,
  cw.current_level,
  cw.artists,
  cw.history_count
FROM certifications_with_history cw
JOIN certifications c ON c.id = cw.id
LIMIT 5;