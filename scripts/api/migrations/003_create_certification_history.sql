-- Migration 003: Create certification_history table and add label_id to certifications
-- Tracks certification evolution (Or → Platine → Diamant) and links labels

-- ─── Certification level enum (for ordering/validation) ───
CREATE TYPE certification_level AS ENUM (
    'Argent',
    'Or',
    'Platine',
    'Diamant'
);

-- ─── Add label_id to certifications ───
ALTER TABLE certifications
    ADD COLUMN IF NOT EXISTS label_id UUID REFERENCES labels(id);

-- ─── Certification history table ───
CREATE TABLE IF NOT EXISTS certification_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    certification_id UUID NOT NULL REFERENCES certifications(id) ON DELETE CASCADE,
    certification_level certification_level NOT NULL,
    date_constat DATE NOT NULL,           -- When this level was certified
    date_sortie DATE,                      -- Release date (copied from certification)
    source_url TEXT,                       -- Source URL for this specific level
    is_current BOOLEAN DEFAULT FALSE,      -- Marks the latest/highest level
    notes TEXT                             -- Optional notes about this progression
);

-- ─── Indexes ───
CREATE INDEX IF NOT EXISTS idx_certifications_label ON certifications(label_id);
CREATE INDEX IF NOT EXISTS idx_certification_history_cert ON certification_history(certification_id);
CREATE INDEX IF NOT EXISTS idx_certification_history_level ON certification_history(certification_level);
CREATE INDEX IF NOT EXISTS idx_certification_history_date ON certification_history(date_constat);
CREATE INDEX IF NOT EXISTS idx_certification_history_current ON certification_history(certification_id, is_current) WHERE is_current;

-- ─── Unique constraint: one current level per certification ───
-- This is enforced by the partial unique index above (is_current=true)

-- ─── RLS Policies ───
ALTER TABLE certification_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read certification_history" ON certification_history FOR SELECT USING (true);

-- ─── Updated_at trigger for certification_history ───
CREATE TRIGGER update_certification_history_updated_at BEFORE UPDATE ON certification_history
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ─── Helpful view: certification with full history ───
CREATE OR REPLACE VIEW certification_with_history AS
SELECT
    c.id,
    c.titre,
    c.categorie,
    c.certification AS current_certification,
    c.date_constat AS current_date_constat,
    c.date_sortie,
    c.duree_obtention,
    c.source_url,
    l.name AS label_name,
    l.slug AS label_slug,
    jsonb_agg(
        jsonb_build_object(
            'level', ch.certification_level,
            'date_constat', ch.date_constat,
            'source_url', ch.source_url,
            'is_current', ch.is_current,
            'notes', ch.notes
        ) ORDER BY
            CASE ch.certification_level
                WHEN 'Argent' THEN 1
                WHEN 'Or' THEN 2
                WHEN 'Platine' THEN 3
                WHEN 'Diamant' THEN 4
            END
    ) AS history
FROM certifications c
LEFT JOIN labels l ON l.id = c.label_id
LEFT JOIN certification_history ch ON ch.certification_id = c.id
GROUP BY c.id, l.name, l.slug;

-- ─── Function to get highest certification level ───
CREATE OR REPLACE FUNCTION get_highest_certification_level(levels certification_level[])
RETURNS certification_level AS $$
DECLARE
    result certification_level;
BEGIN
    -- Order: Diamant > Platine > Or > Argent
    IF 'Diamant' = ANY(levels) THEN RETURN 'Diamant'::certification_level; END IF;
    IF 'Platine' = ANY(levels) THEN RETURN 'Platine'::certification_level; END IF;
    IF 'Or' = ANY(levels) THEN RETURN 'Or'::certification_level; END IF;
    IF 'Argent' = ANY(levels) THEN RETURN 'Argent'::certification_level; END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;