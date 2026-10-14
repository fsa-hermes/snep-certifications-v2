//! SNEP Certifications API
//! 
//! A Rust API for French music certifications from SNEP (Syndicat National de l'Édition Phonographique)
//! Built with Axum, SQLx, and PostgreSQL/Supabase.

pub mod db;
pub mod errors;
pub mod handlers;
pub mod models;
pub mod repositories;
pub mod scraper;

// Re-export commonly used types
pub use crate::db::{create_pool, health_check, DbPool};
pub use crate::errors::{ApiError, ApiResult};
pub use crate::models::*;
pub use crate::repositories::{ArtistRepository, CertificationRepository, LabelRepository};
pub use crate::scraper::SnepScraper;