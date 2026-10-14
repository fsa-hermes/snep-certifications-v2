-- Initial schema migration for SNEP certifications
-- Run this first to create the base tables

-- Artists table
CREATE TABLE IF NOT EXISTS artists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    normalized_name TEXT NOT NULL, -- lowercase, trimmed for matching
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_artists_normalized_name ON artists(normalized_name);
CREATE INDEX IF NOT EXISTS idx_artists_name_trgm ON artists USING GIN (name gin_trgm_ops);

-- Labels table
CREATE TABLE IF NOT EXISTS labels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    normalized_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_labels_normalized_name ON labels(normalized_name);
CREATE INDEX IF NOT EXISTS idx_labels_name_trgm ON labels USING GIN (name gin_trgm_ops);

-- Certifications table (enhanced from original)
CREATE TABLE IF NOT EXISTS certifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Original fields
    categorie TEXT,
    titre TEXT NOT NULL,
    artiste TEXT NOT NULL, -- Keep for backward compatibility
    editeur TEXT, -- Label/publisher name (text, not FK for now)
    certification TEXT NOT NULL,
    date_sortie DATE,
    date_constat DATE,
    duree_obtention TEXT,
    source_url TEXT,
    dedup_key TEXT NOT NULL UNIQUE,
    
    -- New FK references
    label_id UUID REFERENCES labels(id) ON DELETE SET NULL,
    
    -- Metadata
    scraped_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_certifications_dedup ON certifications(dedup_key);
CREATE INDEX IF NOT EXISTS idx_certifications_artiste ON certifications(artiste);
CREATE INDEX IF NOT EXISTS idx_certifications_titre ON certifications(titre);
CREATE INDEX IF NOT EXISTS idx_certifications_certification ON certifications(certification);
CREATE INDEX IF NOT EXISTS idx_certifications_categorie ON certifications(categorie);
CREATE INDEX IF NOT EXISTS idx_certifications_date_constat ON certifications(date_constat);
CREATE INDEX IF NOT EXISTS idx_certifications_date_sortie ON certifications(date_sortie);
CREATE INDEX IF NOT EXISTS idx_certifications_label_id ON certifications(label_id);
CREATE INDEX IF NOT EXISTS idx_certifications_scraped_at ON certifications(scraped_at);

-- Full-text search index
CREATE INDEX IF NOT EXISTS idx_certifications_fts ON certifications 
    USING GIN (
        to_tsvector('french', coalesce(titre, '') || ' ' || 
                           coalesce(artiste, '') || ' ' || 
                           coalesce(editeur, '') || ' ' || 
                           coalesce(categorie, ''))
    );

-- Certification-Artists junction table (many-to-many with roles)
CREATE TABLE IF NOT EXISTS certification_artists (
    certification_id UUID NOT NULL REFERENCES certifications(id) ON DELETE CASCADE,
    artist_id UUID NOT NULL REFERENCES artists(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('singer', 'composer', 'both')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (certification_id, artist_id, role)
);

CREATE INDEX IF NOT EXISTS idx_certification_artists_artist_id ON certification_artists(artist_id);
CREATE INDEX IF NOT EXISTS idx_certification_artists_role ON certification_artists(role);

-- Certification history table for tracking changes
CREATE TABLE IF NOT EXISTS certification_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    certification_id UUID NOT NULL REFERENCES certifications(id) ON DELETE CASCADE,
    old_certification TEXT,
    new_certification TEXT NOT NULL,
    old_categorie TEXT,
    new_categorie TEXT,
    old_titre TEXT,
    new_titre TEXT,
    old_artiste TEXT,
    new_artiste TEXT,
    old_editeur TEXT,
    new_editeur TEXT,
    old_date_sortie DATE,
    new_date_sortie DATE,
    old_date_constat DATE,
    new_date_constat DATE,
    old_duree_obtention TEXT,
    new_duree_obtention TEXT,
    old_label_id UUID REFERENCES labels(id),
    new_label_id UUID REFERENCES labels(id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    change_reason TEXT DEFAULT 'scraper_update'
);

CREATE INDEX IF NOT EXISTS idx_certification_history_certification_id ON certification_history(certification_id);
CREATE INDEX IF NOT EXISTS idx_certification_history_changed_at ON certification_history(changed_at);

-- Trigger function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_artists_updated_at BEFORE UPDATE ON artists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_labels_updated_at BEFORE UPDATE ON labels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_certifications_updated_at BEFORE UPDATE ON certifications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable pg_trgm extension for fuzzy search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- View for easy querying with artist/label names
CREATE OR REPLACE VIEW certifications_with_details AS
SELECT 
    c.id,
    c.created_at,
    c.updated_at,
    c.categorie,
    c.titre,
    c.artiste,
    c.editeur,
    c.certification,
    c.date_sortie,
    c.date_constat,
    c.duree_obtention,
    c.source_url,
    c.dedup_key,
    c.scraped_at,
    c.label_id,
    l.name as label_name,
    json_agg(
        json_build_object(
            'id', a.id,
            'name', a.name,
            'role', ca.role
        )
    ) FILTER (WHERE a.id IS NOT NULL) as artists
FROM certifications c
LEFT JOIN labels l ON c.label_id = l.id
LEFT JOIN certification_artists ca ON c.id = ca.certification_id
LEFT JOIN artists a ON ca.artist_id = a.id
GROUP BY c.id, l.name;