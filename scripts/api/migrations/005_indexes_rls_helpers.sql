-- Migration 005: Additional indexes, RLS policies, and helper functions
-- Performance optimization and security hardening

-- ─── Additional indexes on certifications ───
CREATE INDEX IF NOT EXISTS idx_certifications_categorie ON certifications(categorie);
CREATE INDEX IF NOT EXISTS idx_certifications_certification ON certifications(certification);
CREATE INDEX IF NOT EXISTS idx_certifications_date_constat ON certifications(date_constat);
CREATE INDEX IF NOT EXISTS idx_certifications_date_sortie ON certifications(date_sortie);
CREATE INDEX IF NOT EXISTS idx_certifications_artiste_search ON certifications USING GIN (to_tsvector('french', artiste));
CREATE INDEX IF NOT EXISTS idx_certifications_titre_search ON certifications USING GIN (to_tsvector('french', titre));
CREATE INDEX IF NOT EXISTS idx_certifications_dedup_key ON certifications(dedup_key);

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_certifications_artist_cert_date ON certifications(artiste, certification, date_constat);
CREATE INDEX IF NOT EXISTS idx_certifications_label_cert_date ON certifications(label_id, certification, date_constat);

-- ─── Additional indexes on certification_history ───
CREATE INDEX IF NOT EXISTS idx_certification_history_cert_level ON certification_history(certification_id, certification_level);
CREATE INDEX IF NOT EXISTS idx_certification_history_cert_current ON certification_history(certification_id, is_current) WHERE is_current;

-- ─── RLS Policies for certifications ───
ALTER TABLE certifications ENABLE ROW LEVEL SECURITY;

-- Public read access
CREATE POLICY "Public read certifications" ON certifications FOR SELECT USING (true);

-- ─── RLS Policies for certification_history ───
ALTER TABLE certification_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read certification_history" ON certification_history FOR SELECT USING (true);

-- ─── Function: Get artist certifications with history ───
CREATE OR REPLACE FUNCTION get_artist_certifications(p_artist_id UUID, p_limit INT DEFAULT 50, p_offset INT DEFAULT 0)
RETURNS TABLE(
    certification_id UUID,
    titre TEXT,
    certification_level certification_level,
    date_constat DATE,
    label_name TEXT,
    artist_role artist_role,
    history JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.titre,
        ch.certification_level,
        ch.date_constat,
        l.name,
        ca.role,
        jsonb_agg(
            jsonb_build_object(
                'level', ch2.certification_level,
                'date_constat', ch2.date_constat,
                'is_current', ch2.is_current
            ) ORDER BY
                CASE ch2.certification_level
                    WHEN 'Argent' THEN 1
                    WHEN 'Or' THEN 2
                    WHEN 'Platine' THEN 3
                    WHEN 'Diamant' THEN 4
                END
        ) AS history
    FROM certifications c
    JOIN certification_artists ca ON ca.certification_id = c.id
    JOIN certification_history ch ON ch.certification_id = c.id AND ch.is_current
    LEFT JOIN labels l ON l.id = c.label_id
    LEFT JOIN certification_history ch2 ON ch2.certification_id = c.id
    WHERE ca.artist_id = p_artist_id
    GROUP BY c.id, c.titre, ch.certification_level, ch.date_constat, l.name, ca.role
    ORDER BY ch.date_constat DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─── Function: Get label certifications ───
CREATE OR REPLACE FUNCTION get_label_certifications(p_label_id UUID, p_limit INT DEFAULT 50, p_offset INT DEFAULT 0)
RETURNS TABLE(
    certification_id UUID,
    titre TEXT,
    artiste TEXT,
    certification_level certification_level,
    date_constat DATE,
    history JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.titre,
        c.artiste,
        ch.certification_level,
        ch.date_constat,
        jsonb_agg(
            jsonb_build_object(
                'level', ch2.certification_level,
                'date_constat', ch2.date_constat,
                'is_current', ch2.is_current
            ) ORDER BY
                CASE ch2.certification_level
                    WHEN 'Argent' THEN 1
                    WHEN 'Or' THEN 2
                    WHEN 'Platine' THEN 3
                    WHEN 'Diamant' THEN 4
                END
        ) AS history
    FROM certifications c
    JOIN certification_history ch ON ch.certification_id = c.id AND ch.is_current
    LEFT JOIN certification_history ch2 ON ch2.certification_id = c.id
    WHERE c.label_id = p_label_id
    GROUP BY c.id, c.titre, c.artiste, ch.certification_level, ch.date_constat
    ORDER BY ch.date_constat DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─── Function: Search certifications (full-text) ───
CREATE OR REPLACE FUNCTION search_certifications(
    p_query TEXT,
    p_categorie TEXT DEFAULT NULL,
    p_certification certification_level DEFAULT NULL,
    p_label_id UUID DEFAULT NULL,
    p_date_from DATE DEFAULT NULL,
    p_date_to DATE DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE(
    certification_id UUID,
    titre TEXT,
    artiste TEXT,
    categorie TEXT,
    certification certification_level,
    date_constat DATE,
    label_name TEXT,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.titre,
        c.artiste,
        c.categorie,
        c.certification::certification_level,
        c.date_constat,
        l.name,
        ts_rank_cd(
            to_tsvector('french', c.titre || ' ' || c.artiste),
            plainto_tsquery('french', p_query)
        ) AS rank
    FROM certifications c
    LEFT JOIN labels l ON l.id = c.label_id
    WHERE
        (p_query IS NULL OR p_query = '' OR to_tsvector('french', c.titre || ' ' || c.artiste) @@ plainto_tsquery('french', p_query))
        AND (p_categorie IS NULL OR c.categorie = p_categorie)
        AND (p_certification IS NULL OR c.certification = p_certification)
        AND (p_label_id IS NULL OR c.label_id = p_label_id)
        AND (p_date_from IS NULL OR c.date_constat >= p_date_from)
        AND (p_date_to IS NULL OR c.date_constat <= p_date_to)
    ORDER BY rank DESC, c.date_constat DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─── Function: Upsert certification with history tracking ───
-- Call this when a certification is upgraded (e.g., Or → Platine)
CREATE OR REPLACE FUNCTION upsert_certification_with_history(
    p_categorie TEXT,
    p_titre TEXT,
    p_artiste TEXT,
    p_editeur TEXT,
    p_certification certification_level,
    p_date_sortie DATE,
    p_date_constat DATE,
    p_duree_obtention TEXT,
    p_source_url TEXT,
    p_dedup_key TEXT
)
RETURNS UUID AS $$
DECLARE
    v_cert_id UUID;
    v_label_id UUID;
    v_old_level certification_level;
BEGIN
    -- Get or create label
    IF p_editeur IS NOT NULL AND trim(p_editeur) != '' THEN
        INSERT INTO labels (name_normalized, name, slug)
        VALUES (normalize_name(p_editeur), trim(p_editeur), generate_slug(trim(p_editeur)))
        ON CONFLICT (name_normalized) DO UPDATE SET
            name = EXCLUDED.name,
            slug = EXCLUDED.slug
        RETURNING id INTO v_label_id;
    END IF;

    -- Check if certification exists
    SELECT id, certification::certification_level INTO v_cert_id, v_old_level
    FROM certifications
    WHERE dedup_key = p_dedup_key;

    IF v_cert_id IS NOT NULL THEN
        -- Certification exists - check if level upgraded
        IF v_old_level IS DISTINCT FROM p_certification THEN
            -- Mark old history as not current
            UPDATE certification_history
            SET is_current = FALSE
            WHERE certification_id = v_cert_id AND is_current = TRUE;

            -- Add new history entry
            INSERT INTO certification_history (certification_id, certification_level, date_constat, date_sortie, source_url, is_current, notes)
            VALUES (v_cert_id, p_certification, p_date_constat, p_date_sortie, p_source_url, TRUE,
                'Upgraded from ' || v_old_level || ' to ' || p_certification);

            -- Update certification record
            UPDATE certifications
            SET certification = p_certification,
                date_constat = p_date_constat,
                date_sortie = COALESCE(p_date_sortie, date_sortie),
                duree_obtention = COALESCE(p_duree_obtention, duree_obtention),
                label_id = COALESCE(v_label_id, label_id),
                updated_at = NOW()
            WHERE id = v_cert_id;
        END IF;
    ELSE
        -- New certification
        INSERT INTO certifications (categorie, titre, artiste, editeur, certification, date_sortie, date_constat, duree_obtention, source_url, dedup_key, label_id)
        VALUES (p_categorie, p_titre, p_artiste, p_editeur, p_certification, p_date_sortie, p_date_constat, p_duree_obtention, p_source_url, p_dedup_key, v_label_id)
        RETURNING id INTO v_cert_id;

        -- Create initial history entry
        INSERT INTO certification_history (certification_id, certification_level, date_constat, date_sortie, source_url, is_current)
        VALUES (v_cert_id, p_certification, p_date_constat, p_date_sortie, p_source_url, TRUE);
    END IF;

    RETURN v_cert_id;
END;
$$ LANGUAGE plpgsql;

-- ─── View: Certification stats by level ───
CREATE OR REPLACE VIEW certification_stats_by_level AS
SELECT
    ch.certification_level,
    COUNT(DISTINCT ch.certification_id) AS count,
    MIN(ch.date_constat) AS first_date,
    MAX(ch.date_constat) AS last_date
FROM certification_history ch
WHERE ch.is_current = TRUE
GROUP BY ch.certification_level
ORDER BY
    CASE ch.certification_level
        WHEN 'Argent' THEN 1
        WHEN 'Or' THEN 2
        WHEN 'Platine' THEN 3
        WHEN 'Diamant' THEN 4
    END;

-- ─── View: Top artists by certification count ───
CREATE OR REPLACE VIEW top_artists_by_certifications AS
SELECT
    a.id,
    a.name,
    a.slug,
    COUNT(DISTINCT ca.certification_id) AS total_certifications,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Diamant' THEN ca.certification_id END) AS diamant_count,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Platine' THEN ca.certification_id END) AS platine_count,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Or' THEN ca.certification_id END) AS or_count,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Argent' THEN ca.certification_id END) AS argent_count,
    MAX(ch.date_constat) AS latest_certification
FROM artists a
JOIN certification_artists ca ON ca.artist_id = a.id
JOIN certification_history ch ON ch.certification_id = ca.certification_id AND ch.is_current
WHERE ca.role = 'primary'
GROUP BY a.id, a.name, a.slug
ORDER BY total_certifications DESC;

-- ─── View: Top labels by certification count ───
CREATE OR REPLACE VIEW top_labels_by_certifications AS
SELECT
    l.id,
    l.name,
    l.slug,
    COUNT(DISTINCT c.id) AS total_certifications,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Diamant' THEN c.id END) AS diamant_count,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Platine' THEN c.id END) AS platine_count,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Or' THEN c.id END) AS or_count,
    COUNT(DISTINCT CASE WHEN ch.certification_level = 'Argent' THEN c.id END) AS argent_count,
    MAX(ch.date_constat) AS latest_certification
FROM labels l
JOIN certifications c ON c.label_id = l.id
JOIN certification_history ch ON ch.certification_id = c.id AND ch.is_current
GROUP BY l.id, l.name, l.slug
ORDER BY total_certifications DESC;