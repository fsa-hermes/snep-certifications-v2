-- Master migration runner: Execute all migrations in order
-- Run this file to apply all schema changes

-- ─── Migration 001: Artists and Labels ───
\ir 001_create_artists_labels.sql

-- ─── Migration 002: Certification-Artists Junction ───
\ir 002_create_certification_artists.sql

-- ─── Migration 003: Certification History + Label FK ───
\ir 003_create_certification_history.sql

-- ─── Migration 004: Data Migration ───
\ir 004_migrate_existing_data.sql

-- ─── Migration 005: Indexes, RLS, Helpers ───
\ir 005_indexes_rls_helpers.sql

-- ─── Final verification ───
DO $$
DECLARE
    v_artists_count INT;
    v_labels_count INT;
    v_cert_artists_count INT;
    v_history_count INT;
    v_certs_with_label INT;
BEGIN
    SELECT count(*) INTO v_artists_count FROM artists;
    SELECT count(*) INTO v_labels_count FROM labels;
    SELECT count(*) INTO v_cert_artists_count FROM certification_artists;
    SELECT count(*) INTO v_history_count FROM certification_history;
    SELECT count(*) INTO v_certs_with_label FROM certifications WHERE label_id IS NOT NULL;

    RAISE NOTICE '=== Migration Summary ===';
    RAISE NOTICE 'Artists created: %', v_artists_count;
    RAISE NOTICE 'Labels created: %', v_labels_count;
    RAISE NOTICE 'Certification-Artist links: %', v_cert_artists_count;
    RAISE NOTICE 'History entries: %', v_history_count;
    RAISE NOTICE 'Certifications with label_id: %', v_certs_with_label;
    RAISE NOTICE '=========================';
END $$;