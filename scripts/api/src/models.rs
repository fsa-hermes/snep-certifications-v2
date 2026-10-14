use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;
use utoipa::ToSchema;
use validator::Validate;

/// Artist model
#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct Artist {
    pub id: Uuid,
    pub name: String,
    pub normalized_name: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Artist response (for API)
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ArtistResponse {
    pub id: Uuid,
    pub name: String,
    pub created_at: DateTime<Utc>,
}

impl From<Artist> for ArtistResponse {
    fn from(artist: Artist) -> Self {
        Self {
            id: artist.id,
            name: artist.name,
            created_at: artist.created_at,
        }
    }
}

/// Label model
#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct Label {
    pub id: Uuid,
    pub name: String,
    pub normalized_name: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Label response (for API)
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct LabelResponse {
    pub id: Uuid,
    pub name: String,
    pub created_at: DateTime<Utc>,
}

impl From<Label> for LabelResponse {
    fn from(label: Label) -> Self {
        Self {
            id: label.id,
            name: label.name,
            created_at: label.created_at,
        }
    }
}

/// Artist role in a certification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema, sqlx::Type)]
#[sqlx(type_name = "text", rename_all = "lowercase")]
pub enum ArtistRole {
    Singer,
    Composer,
    Both,
}

impl std::fmt::Display for ArtistRole {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ArtistRole::Singer => write!(f, "singer"),
            ArtistRole::Composer => write!(f, "composer"),
            ArtistRole::Both => write!(f, "both"),
        }
    }
}

/// Certification-Artist junction
#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct CertificationArtist {
    pub certification_id: Uuid,
    pub artist_id: Uuid,
    pub role: ArtistRole,
    pub created_at: DateTime<Utc>,
}

/// Certification-Artist with artist details (for API)
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct CertificationArtistWithDetails {
    pub id: Uuid,
    pub name: String,
    pub role: ArtistRole,
}

/// Certification model
#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct Certification {
    pub id: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub categorie: Option<String>,
    pub titre: String,
    pub artiste: String,
    pub editeur: Option<String>,
    pub certification: String,
    pub date_sortie: Option<NaiveDate>,
    pub date_constat: Option<NaiveDate>,
    pub duree_obtention: Option<String>,
    pub source_url: Option<String>,
    pub dedup_key: String,
    pub label_id: Option<Uuid>,
    pub scraped_at: DateTime<Utc>,
}

/// Certification with artist and label details (for API)
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct CertificationResponse {
    pub id: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub categorie: Option<String>,
    pub titre: String,
    pub artiste: String,
    pub editeur: Option<String>,
    pub certification: String,
    pub date_sortie: Option<NaiveDate>,
    pub date_constat: Option<NaiveDate>,
    pub duree_obtention: Option<String>,
    pub source_url: Option<String>,
    pub dedup_key: String,
    pub label_id: Option<Uuid>,
    pub label_name: Option<String>,
    pub artists: Vec<CertificationArtistWithDetails>,
    pub scraped_at: DateTime<Utc>,
}

/// Paginated response wrapper
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct PaginatedResponse<T> {
    pub data: Vec<T>,
    pub total: i64,
    pub page: u32,
    pub limit: u32,
    pub total_pages: u32,
}

/// Query parameters for certifications list
#[derive(Debug, Clone, Deserialize, ToSchema, Validate)]
pub struct CertificationQueryParams {
    #[schema(example = 1)]
    #[validate(range(min = 1))]
    pub page: Option<u32>,
    
    #[schema(example = 50)]
    #[validate(range(min = 1, max = 200))]
    pub limit: Option<u32>,
    
    #[schema(example = "diamant")]
    pub search: Option<String>,
    
    #[schema(example = "Diamant")]
    pub certification: Option<String>,
    
    #[schema(example = "Singles")]
    pub categorie: Option<String>,
    
    #[schema(example = "Mylène Farmer")]
    pub artiste: Option<String>,
    
    #[schema(example = "2020-01-01")]
    pub date_from: Option<NaiveDate>,
    
    #[schema(example = "2020-12-31")]
    pub date_to: Option<NaiveDate>,
    
    #[schema(example = "date_constat")]
    pub sort_by: Option<String>,
    
    #[schema(example = "desc")]
    pub sort_order: Option<String>,
}

impl Default for CertificationQueryParams {
    fn default() -> Self {
        Self {
            page: Some(1),
            limit: Some(50),
            search: None,
            certification: None,
            categorie: None,
            artiste: None,
            date_from: None,
            date_to: None,
            sort_by: Some("date_constat".to_string()),
            sort_order: Some("desc".to_string()),
        }
    }
}

/// Certification history model
#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct CertificationHistory {
    pub id: Uuid,
    pub certification_id: Uuid,
    pub old_certification: Option<String>,
    pub new_certification: String,
    pub old_categorie: Option<String>,
    pub new_categorie: Option<String>,
    pub old_titre: Option<String>,
    pub new_titre: Option<String>,
    pub old_artiste: Option<String>,
    pub new_artiste: Option<String>,
    pub old_editeur: Option<String>,
    pub new_editeur: Option<String>,
    pub old_date_sortie: Option<NaiveDate>,
    pub new_date_sortie: Option<NaiveDate>,
    pub old_date_constat: Option<NaiveDate>,
    pub new_date_constat: Option<NaiveDate>,
    pub old_duree_obtention: Option<String>,
    pub new_duree_obtention: Option<String>,
    pub old_label_id: Option<Uuid>,
    pub new_label_id: Option<Uuid>,
    pub changed_at: DateTime<Utc>,
    pub change_reason: String,
}

/// Stats response
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct StatsResponse {
    pub total: i64,
    pub by_certification: std::collections::HashMap<String, i64>,
    pub by_category: std::collections::HashMap<String, i64>,
}

/// Filter options response
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct FilterOptionsResponse {
    pub certifications: Vec<String>,
    pub categories: Vec<String>,
    pub artistes: Vec<String>,
}

/// Scraped certification data (from SNEP)
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ScrapedCertification {
    pub categorie: String,
    pub titre: String,
    pub artiste: String,
    pub editeur: String,
    pub certification: String,
    pub date_sortie: String,
    pub date_constat: String,
    pub duree_obtention: String,
    pub source_url: String,
    pub scraped_at: DateTime<Utc>,
}

impl ScrapedCertification {
    /// Generate deduplication key (matches Python logic)
    pub fn dedup_key(&self) -> String {
        use sha2::{Digest, Sha256};
        let parts = [
            self.artiste.trim().to_lowercase(),
            self.titre.trim().to_lowercase(),
            self.certification.trim().to_lowercase(),
            self.date_constat.trim(),
        ];
        let joined = parts.join("|");
        let hash = Sha256::digest(joined.as_bytes());
        hex::encode(hash)[..16].to_string()
    }
    
    /// Parse date from DD/MM/YYYY format
    pub fn parse_date(date_str: &str) -> Option<NaiveDate> {
        NaiveDate::parse_from_str(date_str.trim(), "%d/%m/%Y").ok()
    }
    
    /// Convert to database model
    pub fn to_certification(&self, label_id: Option<Uuid>) -> CertificationInsert {
        CertificationInsert {
            categorie: if self.categorie.trim().is_empty() { None } else { Some(self.categorie.trim().to_string()) },
            titre: self.titre.trim().to_string(),
            artiste: self.artiste.trim().to_string(),
            editeur: if self.editeur.trim().is_empty() { None } else { Some(self.editeur.trim().to_string()) },
            certification: self.certification.trim().to_string(),
            date_sortie: Self::parse_date(&self.date_sortie),
            date_constat: Self::parse_date(&self.date_constat),
            duree_obtention: if self.duree_obtention.trim().is_empty() { None } else { Some(self.duree_obtention.trim().to_string()) },
            source_url: Some(self.source_url.clone()),
            dedup_key: self.dedup_key(),
            label_id,
            scraped_at: self.scraped_at,
        }
    }
}

/// Certification insert model (for database)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificationInsert {
    pub categorie: Option<String>,
    pub titre: String,
    pub artiste: String,
    pub editeur: Option<String>,
    pub certification: String,
    pub date_sortie: Option<NaiveDate>,
    pub date_constat: Option<NaiveDate>,
    pub duree_obtention: Option<String>,
    pub source_url: Option<String>,
    pub dedup_key: String,
    pub label_id: Option<Uuid>,
    pub scraped_at: DateTime<Utc>,
}