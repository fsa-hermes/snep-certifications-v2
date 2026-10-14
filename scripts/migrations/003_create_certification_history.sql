-- Migration 003: Add label_id to certifications, create certification_level enum, certification_history table
-- Run after 001, 002

-- ─── Certification level enum (ordered hierarchy) ───
DO $$ BEGIN
  CREATE TYPE certification_level AS ENUM (
    'Argent',      -- Niveau le plus bas (si existe)
    'Or',          -- Niveau de base
    'Platine',     -- Niveau supérieur
    'Diamant'      -- Niveau le plus haut
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─── Add label_id to certifications ───
ALTER TABLE certifications
  ADD COLUMN IF NOT EXISTS label_id UUID REFERENCES labels(id);

CREATE INDEX IF NOT EXISTS idx_certifications_label ON certifications(label_id);

-- ─── Change certification column to use enum (safe migration) ───
-- First add new column with enum
ALTER TABLE certifications
  ADD COLUMN IF NOT EXISTS certification_level certification_level;

-- Migrate existing text values to enum (will be done in 004_migrate_existing_data.sql)
-- Then drop old column and rename (optional, keep both for compatibility)

-- ─── Certification history table ───
CREATE TABLE IF NOT EXISTS certification_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  certification_id UUID NOT NULL REFERENCES certifications(id) ON DELETE CASCADE,
  old_level certification_level,
  new_level certification_level NOT NULL,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source TEXT DEFAULT 'SNEP',  -- 'SNEP', 'manual', 'import'
  is_current BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Only one current level per certification
CREATE UNIQUE INDEX IF NOT EXISTS uq_cert_history_current
  ON certification_history(certification_id)
  WHERE is_current = TRUE;

CREATE INDEX IF NOT EXISTS idx_cert_history_cert ON certification_history(certification_id);
CREATE INDEX IF NOT EXISTS idx_cert_history_changed ON certification_history(changed_at);

-- ─── View: certifications with current level + history count ───
CREATE OR REPLACE VIEW certifications_with_history AS
SELECT
  c.*,
  l.name AS label_name,
  l.slug AS label_slug,
  ch.new_level AS current_level,
  (
    SELECT jsonb_agg(jsonb_build_object(
      'artist_id', ca.artist_id,
      'name', a.name,
      'slug', a.slug,
      'role', ca.role,
      'position', ca.position
    ) ORDER BY ca.position)
    FROM certification_artists ca
    JOIN artists a ON a.id = ca.artist_id
    WHERE ca.certification_id = c.id
  ) AS artists,
  (
    SELECT COUNT(*) FROM certification_history h WHERE h.certification_id = c.id
  ) AS history_count
FROM certifications c
LEFT JOIN labels l ON l.id = c.label_id
LEFT JOIN certification_history ch ON ch.certification_id = c.id AND ch.is_current = TRUE;

-- ─── Helper: get highest certification level reached ───
CREATE OR REPLACE FUNCTION get_highest_certification_level(cert_id UUID)
RETURNS certification_level AS $$
DECLARE
  max_level certification_level;
BEGIN
  SELECT MAX(new_level) INTO max_level
  FROM certification_history
  WHERE certification_id = cert_id;
  RETURN COALESCE(max_level, 'Or');
END;
$$ LANGUAGE plpgsql;

-- ─── RLS ───
ALTER TABLE certification_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read access" ON certification_history;
CREATE POLICY "Public read access" ON certification_history FOR SELECT USING (true);