use snep_certifications_api::{
    db::DbPool,
    errors::ApiResult,
    models::*,
};
use chrono::NaiveDate;
use sqlx::{query, query_as, Row};
use uuid::Uuid;

/// Repository for certifications
pub struct CertificationRepository;

impl CertificationRepository {
    /// Get paginated certifications with filters
    pub async fn list(
        pool: &DbPool,
        params: &CertificationQueryParams,
    ) -> ApiResult<PaginatedResponse<CertificationResponse>> {
        let page = params.page.unwrap_or(1).max(1);
        let limit = params.limit.unwrap_or(50).clamp(1, 200);
        let offset = (page - 1) * limit;
        
        // Build WHERE clause dynamically
        let mut where_clauses = Vec::new();
        let mut param_count = 0;
        
        if params.search.is_some() {
            param_count += 1;
            where_clauses.push(format!("(c.titre ILIKE ${} OR c.artiste ILIKE ${} OR c.editeur ILIKE ${} OR c.categorie ILIKE ${})", param_count, param_count, param_count, param_count));
        }
        
        if params.certification.is_some() {
            param_count += 1;
            where_clauses.push(format!("c.certification = ${}", param_count));
        }
        
        if params.categorie.is_some() {
            param_count += 1;
            where_clauses.push(format!("c.categorie = ${}", param_count));
        }
        
        if params.artiste.is_some() {
            param_count += 1;
            where_clauses.push(format!("c.artiste ILIKE ${}", param_count));
        }
        
        if params.date_from.is_some() {
            param_count += 1;
            where_clauses.push(format!("c.date_constat >= ${}", param_count));
        }
        
        if params.date_to.is_some() {
            param_count += 1;
            where_clauses.push(format!("c.date_constat <= ${}", param_count));
        }
        
        let where_sql = if where_clauses.is_empty() {
            String::new()
        } else {
            format!("WHERE {}", where_clauses.join(" AND "))
        };
        
        // Validate sort column
        let sort_by = params.sort_by.as_deref().unwrap_or("date_constat");
        let valid_sort_columns = [
            "date_constat", "date_sortie", "titre", "artiste", 
            "certification", "categorie", "created_at"
        ];
        let sort_column = if valid_sort_columns.contains(&sort_by) {
            sort_by
        } else {
            "date_constat"
        };
        
        let sort_order = params.sort_order.as_deref().unwrap_or("desc");
        let sort_order = if sort_order.eq_ignore_ascii_case("asc") { "ASC" } else { "DESC" };
        
        // Count query
        let count_sql = format!(
            "SELECT COUNT(*) FROM certifications c {}",
            where_sql
        );
        
        let mut count_query = query(&count_sql);
        
        // Bind parameters for count
        let mut bind_idx = 0;
        if let Some(search) = &params.search {
            bind_idx += 1;
            let pattern = format!("%{}%", search);
            count_query = count_query.bind(&pattern);
        }
        if let Some(cert) = &params.certification {
            bind_idx += 1;
            count_query = count_query.bind(cert);
        }
        if let Some(cat) = &params.categorie {
            bind_idx += 1;
            count_query = count_query.bind(cat);
        }
        if let Some(art) = &params.artiste {
            bind_idx += 1;
            let pattern = format!("%{}%", art);
            count_query = count_query.bind(&pattern);
        }
        if let Some(date_from) = &params.date_from {
            bind_idx += 1;
            count_query = count_query.bind(date_from);
        }
        if let Some(date_to) = &params.date_to {
            bind_idx += 1;
            count_query = count_query.bind(date_to);
        }
        
        let total: i64 = count_query.fetch_one(pool).await?.get(0);
        let total_pages = ((total as f64) / (limit as f64)).ceil() as u32;
        
        // Data query
        let data_sql = format!(
            r#"
            SELECT 
                c.id, c.created_at, c.updated_at, c.categorie, c.titre, c.artiste,
                c.editeur, c.certification, c.date_sortie, c.date_constat,
                c.duree_obtention, c.source_url, c.dedup_key, c.label_id,
                c.scraped_at,
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
            {}
            GROUP BY c.id, l.name
            ORDER BY c.{} {}
            LIMIT ${} OFFSET ${}
            "#,
            where_sql, sort_column, sort_order, param_count + 1, param_count + 2
        );
        
        let mut data_query = query_as::<_, CertificationResponse>(&data_sql);
        
        // Bind parameters
        if let Some(search) = &params.search {
            let pattern = format!("%{}%", search);
            data_query = data_query.bind(&pattern);
        }
        if let Some(cert) = &params.certification {
            data_query = data_query.bind(cert);
        }
        if let Some(cat) = &params.categorie {
            data_query = data_query.bind(cat);
        }
        if let Some(art) = &params.artiste {
            let pattern = format!("%{}%", art);
            data_query = data_query.bind(&pattern);
        }
        if let Some(date_from) = &params.date_from {
            data_query = data_query.bind(date_from);
        }
        if let Some(date_to) = &params.date_to {
            data_query = data_query.bind(date_to);
        }
        
        data_query = data_query.bind(limit as i64).bind(offset as i64);
        
        let data = data_query.fetch_all(pool).await?;
        
        Ok(PaginatedResponse {
            data,
            total,
            page,
            limit,
            total_pages,
        })
    }
    
    /// Get certification by ID with full details
    pub async fn get_by_id(pool: &DbPool, id: Uuid) -> ApiResult<CertificationResponse> {
        let cert = query_as::<_, CertificationResponse>(
            r#"
            SELECT 
                c.id, c.created_at, c.updated_at, c.categorie, c.titre, c.artiste,
                c.editeur, c.certification, c.date_sortie, c.date_constat,
                c.duree_obtention, c.source_url, c.dedup_key, c.label_id,
                c.scraped_at,
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
            WHERE c.id = $1
            GROUP BY c.id, l.name
            "#
        )
        .bind(id)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| crate::errors::ApiError::NotFound(format!("Certification {} not found", id)))?;
        
        Ok(cert)
    }
    
    /// Get certification history
    pub async fn get_history(pool: &DbPool, certification_id: Uuid) -> ApiResult<Vec<CertificationHistory>> {
        let history = query_as::<_, CertificationHistory>(
            r#"
            SELECT 
                id, certification_id, old_certification, new_certification,
                old_categorie, new_categorie, old_titre, new_titre,
                old_artiste, new_artiste, old_editeur, new_editeur,
                old_date_sortie, new_date_sortie, old_date_constat, new_date_constat,
                old_duree_obtention, new_duree_obtention,
                old_label_id, new_label_id,
                changed_at, change_reason
            FROM certification_history
            WHERE certification_id = $1
            ORDER BY changed_at DESC
            "#
        )
        .bind(certification_id)
        .fetch_all(pool)
        .await?;
        
        Ok(history)
    }
    
    /// Get filter options (distinct values)
    pub async fn get_filter_options(pool: &DbPool) -> ApiResult<FilterOptionsResponse> {
        let certs = query("SELECT DISTINCT certification FROM certifications ORDER BY certification")
            .fetch_all(pool)
            .await?
            .into_iter()
            .map(|row| row.get("certification"))
            .collect();
        
        let cats = query("SELECT DISTINCT categorie FROM certifications WHERE categorie IS NOT NULL ORDER BY categorie")
            .fetch_all(pool)
            .await?
            .into_iter()
            .map(|row| row.get("categorie"))
            .collect();
        
        let artists = query("SELECT DISTINCT artiste FROM certifications ORDER BY artiste LIMIT 1000")
            .fetch_all(pool)
            .await?
            .into_iter()
            .map(|row| row.get("artiste"))
            .collect();
        
        Ok(FilterOptionsResponse {
            certifications: certs,
            categories: cats,
            artistes: artists,
        })
    }
    
    /// Get stats
    pub async fn get_stats(pool: &DbPool) -> ApiResult<StatsResponse> {
        let rows = query(
            r#"
            SELECT certification, categorie FROM certifications
            "#
        )
        .fetch_all(pool)
        .await?;
        
        let mut by_cert = std::collections::HashMap::new();
        let mut by_cat = std::collections::HashMap::new();
        let mut total = 0;
        
        for row in rows {
            total += 1;
            let cert: String = row.get("certification");
            *by_cert.entry(cert).or_insert(0) += 1;
            
            if let Some(cat): Option<String> = row.get("categorie") {
                *by_cat.entry(cat).or_insert(0) += 1;
            }
        }
        
        Ok(StatsResponse {
            total,
            by_certification: by_cert,
            by_category: by_cat,
        })
    }
    
    /// Insert or get artist by name
    pub async fn get_or_create_artist(pool: &DbPool, name: &str) -> ApiResult<Artist> {
        let normalized = name.trim().to_lowercase();
        
        // Try to find existing
        if let Some(artist) = query_as::<_, Artist>(
            "SELECT id, name, normalized_name, created_at, updated_at FROM artists WHERE normalized_name = $1"
        )
        .bind(&normalized)
        .fetch_optional(pool)
        .await? {
            return Ok(artist);
        }
        
        // Create new
        let artist = query_as::<_, Artist>(
            r#"
            INSERT INTO artists (name, normalized_name)
            VALUES ($1, $2)
            RETURNING id, name, normalized_name, created_at, updated_at
            "#
        )
        .bind(name.trim())
        .bind(&normalized)
        .fetch_one(pool)
        .await?;
        
        Ok(artist)
    }
    
    /// Insert or get label by name
    pub async fn get_or_create_label(pool: &DbPool, name: &str) -> ApiResult<Label> {
        let normalized = name.trim().to_lowercase();
        
        // Try to find existing
        if let Some(label) = query_as::<_, Label>(
            "SELECT id, name, normalized_name, created_at, updated_at FROM labels WHERE normalized_name = $1"
        )
        .bind(&normalized)
        .fetch_optional(pool)
        .await? {
            return Ok(label);
        }
        
        // Create new
        let label = query_as::<_, Label>(
            r#"
            INSERT INTO labels (name, normalized_name)
            VALUES ($1, $2)
            RETURNING id, name, normalized_name, created_at, updated_at
            "#
        )
        .bind(name.trim())
        .bind(&normalized)
        .fetch_one(pool)
        .await?;
        
        Ok(label)
    }
    
    /// Insert certification with artists and label
    pub async fn insert_certification(
        pool: &DbPool,
        cert: &CertificationInsert,
        artist_names: &[(&str, ArtistRole)],
    ) -> ApiResult<Certification> {
        let mut tx = pool.begin().await?;
        
        // Get or create label if editeur provided
        let label_id = if let Some(editeur) = &cert.editeur {
            if !editeur.trim().is_empty() {
                let label = Self::get_or_create_label(&mut *tx, editeur).await?;
                Some(label.id)
            } else {
                cert.label_id
            }
        } else {
            cert.label_id
        };
        
        // Insert certification
        let certification = query_as::<_, Certification>(
            r#"
            INSERT INTO certifications (
                categorie, titre, artiste, editeur, certification,
                date_sortie, date_constat, duree_obtention, source_url,
                dedup_key, label_id, scraped_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            ON CONFLICT (dedup_key) DO UPDATE SET
                updated_at = NOW(),
                categorie = EXCLUDED.categorie,
                titre = EXCLUDED.titre,
                artiste = EXCLUDED.artiste,
                editeur = EXCLUDED.editeur,
                certification = EXCLUDED.certification,
                date_sortie = EXCLUDED.date_sortie,
                date_constat = EXCLUDED.date_constat,
                duree_obtention = EXCLUDED.duree_obtention,
                source_url = EXCLUDED.source_url,
                label_id = EXCLUDED.label_id,
                scraped_at = EXCLUDED.scraped_at
            RETURNING id, created_at, updated_at, categorie, titre, artiste,
                editeur, certification, date_sortie, date_constat,
                duree_obtention, source_url, dedup_key, label_id, scraped_at
            "#
        )
        .bind(&cert.categorie)
        .bind(&cert.titre)
        .bind(&cert.artiste)
        .bind(&cert.editeur)
        .bind(&cert.certification)
        .bind(cert.date_sortie)
        .bind(cert.date_constat)
        .bind(&cert.duree_obtention)
        .bind(&cert.source_url)
        .bind(&cert.dedup_key)
        .bind(label_id)
        .bind(cert.scraped_at)
        .fetch_one(&mut *tx)
        .await?;
        
        // Insert artist associations
        for (artist_name, role) in artist_names {
            let artist = Self::get_or_create_artist(&mut *tx, artist_name).await?;
            
            query(
                r#"
                INSERT INTO certification_artists (certification_id, artist_id, role)
                VALUES ($1, $2, $3)
                ON CONFLICT (certification_id, artist_id, role) DO NOTHING
                "#
            )
            .bind(certification.id)
            .bind(artist.id)
            .bind(role.to_string())
            .execute(&mut *tx)
            .await?;
        }
        
        tx.commit().await?;
        
        Ok(certification)
    }
    
    /// Check if certification exists by dedup key
    pub async fn exists_by_dedup_key(pool: &DbPool, dedup_key: &str) -> ApiResult<bool> {
        let exists: bool = query("SELECT EXISTS(SELECT 1 FROM certifications WHERE dedup_key = $1)")
            .bind(dedup_key)
            .fetch_one(pool)
            .await?
            .get(0);
        Ok(exists)
    }
    
    /// Bulk insert certifications (for scraper)
    pub async fn bulk_insert(pool: &DbPool, certs: &[CertificationInsert]) -> ApiResult<u64> {
        if certs.is_empty() {
            return Ok(0);
        }
        
        let mut inserted = 0u64;
        
        // Process in batches
        for chunk in certs.chunks(100) {
            let mut tx = pool.begin().await?;
            
            for cert in chunk {
                // Get or create label
                let label_id = if let Some(editeur) = &cert.editeur {
                    if !editeur.trim().is_empty() {
                        let label = Self::get_or_create_label(&mut *tx, editeur).await?;
                        Some(label.id)
                    } else {
                        cert.label_id
                    }
                } else {
                    cert.label_id
                };
                
                // Insert certification (simple upsert)
                let result = query(
                    r#"
                    INSERT INTO certifications (
                        categorie, titre, artiste, editeur, certification,
                        date_sortie, date_constat, duree_obtention, source_url,
                        dedup_key, label_id, scraped_at
                    )
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                    ON CONFLICT (dedup_key) DO NOTHING
                    "#
                )
                .bind(&cert.categorie)
                .bind(&cert.titre)
                .bind(&cert.artiste)
                .bind(&cert.editeur)
                .bind(&cert.certification)
                .bind(cert.date_sortie)
                .bind(cert.date_constat)
                .bind(&cert.duree_obtention)
                .bind(&cert.source_url)
                .bind(&cert.dedup_key)
                .bind(label_id)
                .bind(cert.scraped_at)
                .execute(&mut *tx)
                .await?;
                
                if result.rows_affected() > 0 {
                    inserted += 1;
                }
            }
            
            tx.commit().await?;
        }
        
        Ok(inserted)
    }
}

/// Repository for artists
pub struct ArtistRepository;

impl ArtistRepository {
    pub async fn list(pool: &DbPool, limit: i64, offset: i64) -> ApiResult<Vec<ArtistResponse>> {
        let artists = query_as::<_, ArtistResponse>(
            "SELECT id, name, created_at FROM artists ORDER BY name LIMIT $1 OFFSET $2"
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?;
        
        Ok(artists)
    }
    
    pub async fn get_by_id(pool: &DbPool, id: Uuid) -> ApiResult<ArtistResponse> {
        let artist = query_as::<_, ArtistResponse>(
            "SELECT id, name, created_at FROM artists WHERE id = $1"
        )
        .bind(id)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| crate::errors::ApiError::NotFound(format!("Artist {} not found", id)))?;
        
        Ok(artist)
    }
    
    pub async fn search(pool: &DbPool, query_str: &str, limit: i64) -> ApiResult<Vec<ArtistResponse>> {
        let pattern = format!("%{}%", query_str);
        let artists = query_as::<_, ArtistResponse>(
            "SELECT id, name, created_at FROM artists WHERE name ILIKE $1 ORDER BY name LIMIT $2"
        )
        .bind(&pattern)
        .bind(limit)
        .fetch_all(pool)
        .await?;
        
        Ok(artists)
    }
}

/// Repository for labels
pub struct LabelRepository;

impl LabelRepository {
    pub async fn list(pool: &DbPool, limit: i64, offset: i64) -> ApiResult<Vec<LabelResponse>> {
        let labels = query_as::<_, LabelResponse>(
            "SELECT id, name, created_at FROM labels ORDER BY name LIMIT $1 OFFSET $2"
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await?;
        
        Ok(labels)
    }
    
    pub async fn get_by_id(pool: &DbPool, id: Uuid) -> ApiResult<LabelResponse> {
        let label = query_as::<_, LabelResponse>(
            "SELECT id, name, created_at FROM labels WHERE id = $1"
        )
        .bind(id)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| crate::errors::ApiError::NotFound(format!("Label {} not found", id)))?;
        
        Ok(label)
    }
}