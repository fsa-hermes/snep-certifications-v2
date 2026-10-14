-- Migration 001: Create artists and labels tables
-- Run this first

-- ─── Artists table ───
CREATE TABLE IF NOT EXISTS artists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  normalized_name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_artists_normalized_name ON artists(normalized_name);
CREATE INDEX IF NOT EXISTS idx_artists_slug ON artists(slug);

-- ─── Labels table ───
CREATE TABLE IF NOT EXISTS labels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  normalized_name TEXT NOT NULL,
  parent_label_id UUID REFERENCES labels(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_labels_normalized_name ON labels(normalized_name);
CREATE INDEX IF NOT EXISTS idx_labels_slug ON labels(slug);
CREATE INDEX IF NOT EXISTS idx_labels_parent ON labels(parent_label_id);

-- ─── Updated_at triggers ───
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_artists_updated_at ON artists;
CREATE TRIGGER update_artists_updated_at
  BEFORE UPDATE ON artists
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_labels_updated_at ON labels;
CREATE TRIGGER update_labels_updated_at
  BEFORE UPDATE ON labels
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ─── RLS Policies ───
ALTER TABLE artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE labels ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read access" ON artists;
CREATE POLICY "Public read access" ON artists FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read access" ON labels;
CREATE POLICY "Public read access" ON labels FOR SELECT USING (true);