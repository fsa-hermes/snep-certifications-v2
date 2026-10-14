-- Migration 001: Create artists and labels tables
-- Run this first to set up the reference tables

-- ─── Artists table ───
CREATE TABLE IF NOT EXISTS artists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    name TEXT NOT NULL,
    name_normalized TEXT NOT NULL,  -- lowercase, trimmed for deduplication
    slug TEXT UNIQUE,               -- URL-friendly slug
    UNIQUE (name_normalized)
);

-- ─── Labels table ───
CREATE TABLE IF NOT EXISTS labels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    name TEXT NOT NULL,
    name_normalized TEXT NOT NULL,
    slug TEXT UNIQUE,
    parent_label_id UUID REFERENCES labels(id),  -- for label hierarchies (e.g., Universal → Polydor)
    UNIQUE (name_normalized)
);

-- ─── Indexes for reference tables ───
CREATE INDEX IF NOT EXISTS idx_artists_name_normalized ON artists(name_normalized);
CREATE INDEX IF NOT EXISTS idx_artists_slug ON artists(slug);
CREATE INDEX IF NOT EXISTS idx_labels_name_normalized ON labels(name_normalized);
CREATE INDEX IF NOT EXISTS idx_labels_slug ON labels(slug);
CREATE INDEX IF NOT EXISTS idx_labels_parent ON labels(parent_label_id);

-- ─── RLS Policies ───
ALTER TABLE artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE labels ENABLE ROW LEVEL SECURITY;

-- Public read access for artists/labels
CREATE POLICY "Public read artists" ON artists FOR SELECT USING (true);
CREATE POLICY "Public read labels" ON labels FOR SELECT USING (true);

-- ─── Updated_at triggers ───
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_artists_updated_at BEFORE UPDATE ON artists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_labels_updated_at BEFORE UPDATE ON labels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();