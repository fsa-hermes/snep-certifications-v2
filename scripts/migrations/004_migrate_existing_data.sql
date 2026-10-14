-- Migration 004: Migrate existing data to new schema
-- Run after 001, 002, 003

-- ─── Helper functions ───
CREATE OR REPLACE FUNCTION normalize_name(raw_name TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN lower(trim(regexp_replace(raw_name, '\s+', ' ', 'g')));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION generate_slug(raw_name TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN lower(regexp_replace(trim(raw_name), '[^a-z0-9]+', '-', 'g'));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ─── Split artists string into array ───
-- Handles: "A feat. B", "A ft B", "A featuring B", "A & B", "A et B", "A with B", "A vs B", "A x B", "A, B"
CREATE OR REPLACE FUNCTION split_artists(raw_artists TEXT)
RETURNS TABLE(artist_name TEXT, role artist_role, position INT) AS $$
DECLARE
  parts TEXT[];
  i INT := 0;
  name TEXT;
  detected_role artist_role;
BEGIN
  -- Normalize separators
  raw_artists := regexp_replace(raw_artists, '(feat\.?|featuring|ft)\.?\s+', ' feat. ', 'gi');
  raw_artists := regexp_replace(raw_artists, '\s+(et|and|with)\s+', ' & ', 'gi');
  raw_artists := regexp_replace(raw_artists, '\s+(vs|x)\s+', ' & ', 'gi');
  
  parts := regexp_split_to_array(raw_artists, '\s*[,;&]\s*|\s+&\s+');
  
  FOREACH name IN ARRAY parts LOOP
    i := i + 1;
    name := trim(name);
    IF name = '' THEN CONTINUE; END IF;
    
    -- Detect role from prefix
    IF name ~* '^feat\.?\s+' THEN
      detected_role := 'featured';
      name := regexp_replace(name, '^feat\.?\s+', '', 'i');
    ELSIF name ~* '^with\s+' THEN
      detected_role := 'with';
      name := regexp_replace(name, '^with\s+', '', 'i');
    ELSIF name ~* '^remix' THEN
      detected_role := 'remixer';
    ELSIF i = 1 THEN
      detected_role := 'primary';
    ELSE
      detected_role := 'with';
    END IF;
    
    RETURN QUERY SELECT name, detected_role, i;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ─── 1. Populate artists from certifications.artiste ───
INSERT INTO artists (name, slug, normalized_name)
SELECT DISTINCT
  trim(artist_name),
  generate_slug(trim(artist_name)),
  normalize_name(trim(artist_name))
FROM certifications,
LATERAL split_artists(certifications.artiste)
ON CONFLICT (slug) DO UPDATE SET
  normalized_name = EXCLUDED.normalized_name,
  updated_at = NOW();

-- ─── 2. Populate labels from certifications.editeur ───
-- Take first label before " / " as main, rest as parent hierarchy
INSERT INTO labels (name, slug, normalized_name, parent_label_id)
SELECT DISTINCT
  trim(parts[1]),
  generate_slug(trim(parts[1])),
  normalize_name(trim(parts[1])),
  NULL
FROM (
  SELECT regexp_split_to_array(editeur, '\s*/\s*') AS parts
  FROM certifications
  WHERE editeur IS NOT NULL AND editeur != ''
) sub
ON CONFLICT (slug) DO UPDATE SET
  normalized_name = EXCLUDED.normalized_name,
  updated_at = NOW();

-- ─── 3. Link certifications to labels ───
UPDATE certifications c
SET label_id = l.id
FROM labels l
WHERE c.editeur IS NOT NULL
  AND l.normalized_name = normalize_name(split_part(c.editeur, '/', 1));

-- ─── 4. Populate certification_artists junction ───
INSERT INTO certification_artists (certification_id, artist_id, role, position)
SELECT
  c.id,
  a.id,
  sa.role,
  sa.position
FROM certifications c,
LATERAL split_artists(c.artiste) sa
JOIN artists a ON a.normalized_name = normalize_name(sa.artist_name)
ON CONFLICT (certification_id, artist_id, role) DO NOTHING;

-- ─── 5. Create initial history entries from existing certifications ───
-- Use date_constat as the "changed_at" for initial entry
INSERT INTO certification_history (certification_id, old_level, new_level, changed_at, source, is_current)
SELECT
  c.id,
  NULL::certification_level,
  CASE
    WHEN lower(c.certification) LIKE '%diamant%' THEN 'Diamant'::certification_level
    WHEN lower(c.certification) LIKE '%triple platine%' THEN 'Platine'::certification_level
    WHEN lower(c.certification) LIKE '%double platine%' THEN 'Platine'::certification_level
    WHEN lower(c.certification) LIKE '%platine%' THEN 'Platine'::certification_level
    WHEN lower(c.certification) LIKE '%or%' THEN 'Or'::certification_level
    WHEN lower(c.certification) LIKE '%argent%' THEN 'Argent'::certification_level
    ELSE 'Or'::certification_level
  END,
  COALESCE(c.date_constat, c.created_at, NOW()),
  'SNEP',
  TRUE
FROM certifications c
WHERE NOT EXISTS (
  SELECT 1 FROM certification_history h WHERE h.certification_id = c.id
);