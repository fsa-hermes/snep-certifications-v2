-- Migration 002: Create certification_artists junction table with role enum
-- Creates the many-to-many relationship between certifications and artists

-- ─── Artist role enum ───
CREATE TYPE artist_role AS ENUM (
    'primary',      -- Main artist
    'featured',     -- Featured artist (feat.)
    'with',         -- Collaborator (with, &, et)
    'remixer',      -- Remixer
    'producer',     -- Producer
    'original'      -- Original artist (for covers/remixes)
);

-- ─── Certification-Artists junction table ───
CREATE TABLE IF NOT EXISTS certification_artists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    certification_id UUID NOT NULL REFERENCES certifications(id) ON DELETE CASCADE,
    artist_id UUID NOT NULL REFERENCES artists(id) ON DELETE CASCADE,
    role artist_role NOT NULL DEFAULT 'primary',
    position INTEGER DEFAULT 0,  -- Order of artists (for display)
    UNIQUE (certification_id, artist_id, role)
);

-- ─── Indexes ───
CREATE INDEX IF NOT EXISTS idx_certification_artists_cert ON certification_artists(certification_id);
CREATE INDEX IF NOT EXISTS idx_certification_artists_artist ON certification_artists(artist_id);
CREATE INDEX IF NOT EXISTS idx_certification_artists_role ON certification_artists(role);

-- ─── RLS Policies ───
ALTER TABLE certification_artists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read certification_artists" ON certification_artists FOR SELECT USING (true);

-- ─── Updated_at trigger ───
CREATE TRIGGER update_certification_artists_updated_at BEFORE UPDATE ON certification_artists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ─── Helpful view: certification with primary artist ───
CREATE OR REPLACE VIEW certification_primary_artist AS
SELECT
    c.id AS certification_id,
    c.titre,
    c.certification,
    c.date_constat,
    a.id AS artist_id,
    a.name AS artist_name,
    a.slug AS artist_slug,
    ca.role
FROM certifications c
JOIN certification_artists ca ON ca.certification_id = c.id
JOIN artists a ON a.id = ca.artist_id
WHERE ca.role = 'primary' AND ca.position = 0;