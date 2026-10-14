-- Migration 002: Create certification_artists junction table with roles
-- Run after 001

-- ─── Artist role enum ───
DO $$ BEGIN
  CREATE TYPE artist_role AS ENUM (
    'primary',      -- Artiste principal
    'featured',     -- Featuring
    'with',         -- With / et
    'remixer',      -- Remixeur
    'producer',     -- Producteur
    'original'      -- Artiste original (pour remixes)
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─── Junction table: certifications <-> artists ───
CREATE TABLE IF NOT EXISTS certification_artists (
  certification_id UUID NOT NULL REFERENCES certifications(id) ON DELETE CASCADE,
  artist_id UUID NOT NULL REFERENCES artists(id) ON DELETE CASCADE,
  role artist_role NOT NULL DEFAULT 'primary',
  position INT NOT NULL DEFAULT 0,  -- Ordre d'affichage
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (certification_id, artist_id, role)
);

CREATE INDEX IF NOT EXISTS idx_cert_artists_artist ON certification_artists(artist_id);
CREATE INDEX IF NOT EXISTS idx_cert_artists_role ON certification_artists(role);

-- ─── View: primary artist per certification (for simple queries) ───
CREATE OR REPLACE VIEW certification_primary_artist AS
SELECT ca.certification_id, a.id AS artist_id, a.name, a.slug
FROM certification_artists ca
JOIN artists a ON a.id = ca.artist_id
WHERE ca.role = 'primary' AND ca.position = 0;

-- ─── RLS ───
ALTER TABLE certification_artists ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read access" ON certification_artists;
CREATE POLICY "Public read access" ON certification_artists FOR SELECT USING (true);