use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;
use utoipa::ToSchema;

#[derive(Error, Debug, ToSchema)]
pub enum ApiError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
    
    #[error("Not found: {0}")]
    NotFound(String),
    
    #[error("Validation error: {0}")]
    Validation(String),
    
    #[error("Internal server error: {0}")]
    Internal(String),
    
    #[error("Scraper error: {0}")]
    Scraper(String),
    
    #[error("Configuration error: {0}")]
    Config(String),
}

#[derive(Serialize, ToSchema)]
pub struct ErrorResponse {
    pub error: String,
    pub message: String,
    #[schema(nullable = true)]
    pub details: Option<serde_json::Value>,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_code, message) = match &self {
            ApiError::Database(e) => {
                tracing::error!("Database error: {}", e);
                (StatusCode::INTERNAL_SERVER_ERROR, "DATABASE_ERROR", "Internal server error")
            }
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, "NOT_FOUND", msg.as_str()),
            ApiError::Validation(msg) => (StatusCode::BAD_REQUEST, "VALIDATION_ERROR", msg.as_str()),
            ApiError::Internal(msg) => {
                tracing::error!("Internal error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "Internal server error")
            }
            ApiError::Scraper(msg) => {
                tracing::error!("Scraper error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, "SCRAPER_ERROR", "Scraper error")
            }
            ApiError::Config(msg) => {
                tracing::error!("Config error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, "CONFIG_ERROR", "Configuration error")
            }
        };
        
        let body = Json(json!({
            "error": error_code,
            "message": message,
            "details": null::<serde_json::Value>
        }));
        
        (status, body).into_response()
    }
}

pub type ApiResult<T> = Result<T, ApiError>;

/// Extension trait for converting validator errors
impl From<validator::ValidationErrors> for ApiError {
    fn from(err: validator::ValidationErrors) -> Self {
        let messages: Vec<String> = err
            .field_errors()
            .iter()
            .flat_map(|(field, errors)| {
                errors.iter().map(move |e| {
                    let msg = e.message.as_deref().unwrap_or("invalid value");
                    format!("{}: {}", field, msg)
                })
            })
            .collect();
        ApiError::Validation(messages.join(", "))
    }
}