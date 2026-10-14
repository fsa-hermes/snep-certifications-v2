-- Migration 005: Additional indexes, RLS policies, and helper functions
-- Run after 004

-- ─── Additional indexes on certifications ───
CREATE INDEX IF NOT EXISTS idx_certifications_categorie ON certifications(categorie);
CREATE INDEX IF NOT EXISTS idx_certifications_certification ON certifications(certification);
CREATE INDEX IF NOT EXISTS idx_certifications_date_constat ON certifications(date_constat);
CREATE INDEX IF NOT EXISTS idx_certifications_date_sortie ON certifications(date_sortie);
CREATE INDEX IF NOT EXISTS idx_certifications_dedup_key ON certifications(dedup_key);

-- GIN index for full-text search on titre
CREATE INDEX IF NOT EXISTS idx_certifications_titre_fts
  ON certifications USING GIN (to_tsvector('french', titre));

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_certifications_cert_date ON certifications(certification, date_constat DESC);
CREATE INDEX IF NOT EXISTS idx_certifications_cat_date ON certifications(categorie, date_constat DESC);

-- ─── RLS on certifications ───
ALTER TABLE certifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read access" ON certifications;
CREATE POLICY "Public read access" ON certifications FOR SELECT USING (true);

-- ─── RLS on certification_history ───
ALTER TABLE certification_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read access" ON certification_history;
CREATE POLICY "Public read access" ON certification_history FOR SELECT USING (true);

-- ─── RLS on certification_artists ───
ALTER TABLE certification_artists ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read access" ON certification_artists;
CREATE POLICY "Public read access" ON certification_artists FOR SELECT USING (true);

-- ─── Helper: get all certifications for an artist ───
CREATE OR REPLACE FUNCTION get_artist_certifications(p_artist_id UUID)
RETURNS TABLE (
  id UUID,
  titre TEXT,
  certification certification_level,
  date_constat DATE,
  categorie TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT c.id, c.titre, ch.new_level, c.date_constat, c.categorie
  FROM certifications c
  JOIN certification_artists ca ON ca.certification_id = c.id
  LEFT JOIN certification_history ch ON ch.certification_id = c.id AND ch.is_current = TRUE
  WHERE ca.artist_id = p_artist_id
  ORDER BY c.date_constat DESC;
END;
$$ LANGUAGE plpgsql;

-- ─── Helper: get all certifications for a label ───
CREATE OR REPLACE FUNCTION get_label_certifications(p_label_id UUID)
RETURNS TABLE (
  id UUID,
  titre TEXT,
  certification certification_level,
  date_constat DATE,
  categorie TEXT,
  artist_names TEXT[]
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.titre,
    ch.new_level,
    c.date_constat,
    c.categorie,
    (
      SELECT array_agg(a.name ORDER BY ca.position)
      FROM certification_artists ca
      JOIN artists a ON a.id = ca.artist_id
      WHERE ca.certification_id = c.id
    )
  FROM certifications c
  LEFT JOIN certification_history ch ON ch.certification_id = c.id AND ch.is_current = TRUE
  WHERE c.label_id = p_label_id
  ORDER BY c.date_constat DESC;
END;
$$ LANGUAGE plpgsql;

-- ─── Full-text search function ───
CREATE OR REPLACE FUNCTION search_certifications(
  search_query TEXT DEFAULT NULL,
  cert_level certification_level DEFAULT NULL,
  cat TEXT DEFAULT NULL,
  art_name TEXT DEFAULT NULL,
  lbl_name TEXT DEFAULT NULL,
  date_from DATE DEFAULT NULL,
  date_to DATE DEFAULT NULL,
  sort_by TEXT DEFAULT 'date_constat',
  sort_desc BOOLEAN DEFAULT TRUE,
  page_limit INT DEFAULT 50,
  page_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  titre TEXT,
  editeur TEXT,
  certification certification_level,
  date_sortie DATE,
  date_constat DATE,
  duree_obtention TEXT,
  categorie TEXT,
  label_name TEXT,
  artists JSONB,
  current_level certification_level,
  history_count INT
) AS $$
DECLARE
  sort_col TEXT;
  sort_dir TEXT;
BEGIN
  sort_col := CASE
    WHEN sort_by IN ('titre', 'date_constat', 'date_sortie', 'certification', 'categorie', 'created_at', 'current_level', 'highest_level')
    THEN sort_by ELSE 'date_constat' END;
  sort_dir := CASE WHEN sort_desc THEN 'DESC' ELSE 'ASC' END;

  RETURN QUERY EXECUTE format(
    $q$
    SELECT
      c.id, c.titre, c.editeur, c.certification::certification_level,
      c.date_sortie, c.date_constat, c.duree_obtention, c.categorie,
      l.name AS label_name,
      cw.artists,
      cw.current_level,
      cw.history_count
    FROM certifications_with_history cw
    JOIN certifications c ON c.id = cw.id
    LEFT JOIN labels l ON l.id = c.label_id
    WHERE ($1 IS NULL OR cw.titre ILIKE '%' || $1 || '%'
           OR EXISTS (
             SELECT 1 FROM certification_artists ca
             JOIN artists a ON a.id = ca.artist_id
             WHERE ca.certification_id = c.id AND a.name ILIKE '%' || $1 || '%'
           )
           OR c.editeur ILIKE '%' || $1 || '%')
      AND ($2 IS NULL OR cw.current_level = $2)
      AND ($3 IS NULL OR c.categorie = $3)
      AND ($4 IS NULL OR EXISTS (
        SELECT 1 FROM certification_artists ca
        JOIN artists a ON a.id = ca.artist_id
        WHERE ca.certification_id = c.id AND a.name ILIKE '%' || $4 || '%'
      ))
      AND ($5 IS NULL OR l.name ILIKE '%' || $5 || '%')
      AND ($6 IS NULL OR c.date_constat >= $6)
      AND ($7 IS NULL OR c.date_constat <= $7)
    ORDER BY cw.%I %s
    LIMIT $8 OFFSET $9
    $q$, sort_col, sort_dir
  USING search_query, cert_level, cat, art_name, lbl_name, date_from, date_to, page_limit, page_offset;
END;
$$ LANGUAGE plpgsql;

-- ─── Upsert function that auto-creates history on level upgrade ───
CREATE OR REPLACE FUNCTION upsert_certification_with_history(
  p_titre TEXT,
  p_artiste TEXT,
  p_editeur TEXT,
  p_certification TEXT,
  p_categorie TEXT,
  p_date_sortie DATE,
  p_date_constat DATE,
  p_duree_obtention TEXT,
  p_source_url TEXT,
  p_dedup_key TEXT
)
RETURNS UUID AS $$
DECLARE
  v_cert_id UUID;
  v_new_level certification_level;
  v_old_level certification_level;
  v_current_level certification_level;
BEGIN
  -- Map text certification to enum
  v_new_level := CASE
    WHEN lower(p_certification) LIKE '%diamant%' THEN 'Diamant'::certification_level
    WHEN lower(p_certification) LIKE '%triple platine%' THEN 'Platine'::certification_level
    WHEN lower(p_certification) LIKE '%double platine%' THEN 'Platine'::certification_level
    WHEN lower(p_certification) LIKE '%platine%' THEN 'Platine'::certification_level
    WHEN lower(p_certification) LIKE '%or%' THEN 'Or'::certification_level
    WHEN lower(p_certification) LIKE '%argent%' THEN 'Argent'::certification_level
    ELSE 'Or'::certification_level
  END;

  -- Try to find existing by dedup_key
  SELECT id, ch.new_level INTO v_cert_id, v_current_level
  FROM certifications c
  LEFT JOIN certification_history ch ON ch.certification_id = c.id AND ch.is_current = TRUE
  WHERE c.dedup_key = p_dedup_key;

  IF v_cert_id IS NULL THEN
    -- Insert new certification
    INSERT INTO certifications (titre, artiste, editeur, certification, categorie, date_sortie, date_constat, duree_obtention, source_url, dedup_key)
    VALUES (p_titre, p_artiste, p_editeur, p_certification, p_categorie, p_date_sortie, p_date_constat, p_duree_obtention, p_source_url, p_dedup_key)
    RETURNING id INTO v_cert_id;

    -- Create initial history entry
    INSERT INTO certification_history (certification_id, old_level, new_level, changed_at, source, is_current)
    VALUES (v_cert_id, NULL, v_new_level, COALESCE(p_date_constat, NOW()), 'SNEP', TRUE);
  ELSE
    -- Check if level upgraded
    IF v_current_level IS DISTINCT FROM v_new_level THEN
      -- Mark old as not current
      UPDATE certification_history SET is_current = FALSE WHERE certification_id = v_cert_id AND is_current = TRUE;
      
      -- Add new history entry
      INSERT INTO certification_history (certification_id, old_level, new_level, changed_at, source, is_current)
      VALUES (v_cert_id, v_current_level, v_new_level, COALESCE(p_date_constat, NOW()), 'SNEP', TRUE);
      
      -- Update certification level
      UPDATE certifications SET certification = p_certification, date_constat = p_date_constat WHERE id = v_cert_id;
    END IF;
  END IF;

  RETURN v_cert_id;
END;
$$ LANGUAGE plpgsql;

-- ─── Stats views ───
CREATE OR REPLACE VIEW certification_stats AS
SELECT
  COUNT(*) AS total,
  COUNT(DISTINCT categorie) AS categories_count,
  COUNT(DISTINCT certification) AS levels_count,
  COUNT(DISTINCT label_id) AS labels_count
FROM certifications;

CREATE OR REPLACE VIEW certification_level_distribution AS
SELECT
  ch.new_level AS level,
  COUNT(DISTINCT ch.certification_id) AS count
FROM certification_history ch
WHERE ch.is_current = TRUE
GROUP BY ch.new_level
ORDER BY 
  CASE ch.new_level
    WHEN 'Diamant' THEN 1
    WHEN 'Platine' THEN 2
    WHEN 'Or' THEN 3
    WHEN 'Argent' THEN 4
  END;