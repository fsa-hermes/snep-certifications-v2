-- Migration 004: Data migration - Extract artists and labels from existing certifications
-- Parses the existing artiste and editeur fields to populate new tables

-- ─── Helper function: normalize name for deduplication ───
CREATE OR REPLACE FUNCTION normalize_name(raw_name TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN lower(trim(regexp_replace(raw_name, '\s+', ' ', 'g')));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ─── Helper function: generate slug ───
CREATE OR REPLACE FUNCTION generate_slug(raw_name TEXT)
RETURNS TEXT AS $$
DECLARE
    slug TEXT;
BEGIN
    slug := lower(trim(raw_name));
    slug := regexp_replace(slug, '[^a-z0-9]+', '-', 'g');
    slug := regexp_replace(slug, '^-+|-+$', '', 'g');
    RETURN slug;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ─── Helper function: split artists by common separators ───
-- Handles: "feat.", "ft.", "featuring", "&", "et", "with", ",", "vs.", "vs", "x", "×"
CREATE OR REPLACE FUNCTION split_artists(raw_artiste TEXT)
RETURNS TABLE(artist_name TEXT, role artist_role, position INTEGER) AS $$
DECLARE
    parts TEXT[];
    main_artist TEXT;
    feat_part TEXT;
    i INTEGER := 0;
    part TEXT;
    detected_role artist_role;
BEGIN
    -- First, extract featured artists
    -- Pattern: "Main Artist feat. Featured Artist" or "Main Artist ft. Featured Artist"
    IF raw_artiste ~* '(feat\.|ft\.|featuring)\s+' THEN
        main_artist := regexp_replace(raw_artiste, '(feat\.|ft\.|featuring)\s+.*$', '', 'i');
        feat_part := regexp_replace(raw_artiste, '^.*?(feat\.|ft\.|featuring)\s+', '', 'i');
        
        -- Return main artist
        i := i + 1;
        RETURN QUERY SELECT trim(main_artist), 'primary'::artist_role, i;
        
        -- Split featured artists by &, et, , 
        parts := regexp_split_to_array(feat_part, '\s*[&,]\s*|\s+et\s+');
        FOREACH part IN ARRAY parts LOOP
            i := i + 1;
            RETURN QUERY SELECT trim(part), 'featured'::artist_role, i;
        END LOOP;
        
        RETURN;
    END IF;

    -- Pattern: "Artist 1 & Artist 2" or "Artist 1 et Artist 2" or "Artist 1, Artist 2"
    IF raw_artiste ~* '\s+(&|et)\s+' OR raw_artiste ~ ',\s*' THEN
        parts := regexp_split_to_array(raw_artiste, '\s*[&,]\s*|\s+et\s+');
        FOREACH part IN ARRAY parts LOOP
            i := i + 1;
            -- First artist is primary, others are "with"
            IF i = 1 THEN
                detected_role := 'primary'::artist_role;
            ELSE
                detected_role := 'with'::artist_role;
            END IF;
            RETURN QUERY SELECT trim(part), detected_role, i;
        END LOOP;
        
        RETURN;
    END IF;

    -- Pattern: "Artist 1 vs Artist 2" or "Artist 1 x Artist 2"
    IF raw_artiste ~* '\s+(vs\.?|x|×)\s+' THEN
        parts := regexp_split_to_array(raw_artiste, '\s+(vs\.?|x|×)\s+');
        FOREACH part IN ARRAY parts LOOP
            i := i + 1;
            IF i = 1 THEN
                detected_role := 'primary'::artist_role;
            ELSE
                detected_role := 'with'::artist_role;
            END IF;
            RETURN QUERY SELECT trim(part), detected_role, i;
        END LOOP;
        
        RETURN;
    END IF;

    -- Single artist
    i := i + 1;
    RETURN QUERY SELECT trim(raw_artiste), 'primary'::artist_role, i;
END;
$$ LANGUAGE plpgsql;

-- ─── Step 1: Extract and insert unique artists ───
WITH artist_data AS (
    SELECT DISTINCT
        normalize_name(artist_name) AS name_normalized,
        trim(artist_name) AS name,
        generate_slug(trim(artist_name)) AS slug
    FROM certifications c
    CROSS JOIN LATERAL split_artists(c.artiste)
    WHERE artist_name IS NOT NULL AND trim(artist_name) != ''
)
INSERT INTO artists (name_normalized, name, slug)
SELECT name_normalized, name, slug
FROM artist_data
ON CONFLICT (name_normalized) DO UPDATE SET
    name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    updated_at = NOW();

-- ─── Step 2: Extract and insert unique labels from editeur field ───
WITH label_data AS (
    SELECT DISTINCT
        normalize_name(trim(editeur)) AS name_normalized,
        trim(editeur) AS name,
        generate_slug(trim(editeur)) AS slug
    FROM certifications
    WHERE editeur IS NOT NULL AND trim(editeur) != ''
)
INSERT INTO labels (name_normalized, name, slug)
SELECT name_normalized, name, slug
FROM label_data
ON CONFLICT (name_normalized) DO UPDATE SET
    name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    updated_at = NOW();

-- ─── Step 3: Link certifications to labels ───
UPDATE certifications c
SET label_id = l.id
FROM labels l
WHERE l.name_normalized = normalize_name(c.editeur)
  AND c.editeur IS NOT NULL
  AND trim(c.editeur) != '';

-- ─── Step 4: Link certifications to artists via junction table ───
WITH artist_links AS (
    SELECT
        c.id AS certification_id,
        a.id AS artist_id,
        sa.role,
        sa.position
    FROM certifications c
    CROSS JOIN LATERAL split_artists(c.artiste) sa
    JOIN artists a ON a.name_normalized = normalize_name(sa.artist_name)
    WHERE sa.artist_name IS NOT NULL AND trim(sa.artist_name) != ''
)
INSERT INTO certification_artists (certification_id, artist_id, role, position)
SELECT certification_id, artist_id, role, position
FROM artist_links
ON CONFLICT (certification_id, artist_id, role) DO UPDATE SET
    position = EXCLUDED.position;

-- ─── Step 5: Create initial certification_history entries from existing data ───
-- Each existing certification becomes the "current" level in history
INSERT INTO certification_history (certification_id, certification_level, date_constat, date_sortie, source_url, is_current)
SELECT
    c.id,
    c.certification::certification_level,
    c.date_constat,
    c.date_sortie,
    c.source_url,
    TRUE
FROM certifications c
WHERE c.certification IS NOT NULL
  AND c.certification IN ('Argent', 'Or', 'Platine', 'Diamant')
ON CONFLICT DO NOTHING;

-- ─── Verification queries ───
-- Check artists created
-- SELECT count(*) FROM artists;

-- Check labels created
-- SELECT count(*) FROM labels;

-- Check certification_artists links
-- SELECT count(*) FROM certification_artists;

-- Check certifications with label_id
-- SELECT count(*) FROM certifications WHERE label_id IS NOT NULL;

-- Check certification_history entries
-- SELECT count(*) FROM certification_history;