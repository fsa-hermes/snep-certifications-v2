use snep_certifications_api::{
    db::DbPool,
    errors::ApiResult,
    models::*,
    repositories::*,
};
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
};
use std::sync::Arc;
use utoipa::OpenApi;
use uuid::Uuid;

/// Application state
#[derive(Clone)]
pub struct AppState {
    pub pool: DbPool,
}

/// OpenAPI documentation
#[derive(OpenApi)]
#[openapi(
    paths(
        health_check,
        list_certifications,
        get_certification,
        get_certification_history,
        list_artists,
        get_artist,
        list_labels,
        get_label,
        get_stats,
        get_filter_options,
    ),
    components(schemas(
        CertificationResponse,
        PaginatedResponse<CertificationResponse>,
        CertificationQueryParams,
        CertificationHistory,
        ArtistResponse,
        LabelResponse,
        StatsResponse,
        FilterOptionsResponse,
        ErrorResponse,
    )),
    tags(
        (name = "certifications", description = "Certification endpoints"),
        (name = "artists", description = "Artist endpoints"),
        (name = "labels", description = "Label endpoints"),
        (name = "stats", description = "Statistics endpoints"),
    ),
    info(
        title = "SNEP Certifications API",
        version = "0.1.0",
        description = "API for French music certifications from SNEP",
        contact(
            name = "SNEP Certifications",
            url = "https://snepmusique.com/les-certifications/"
        ),
        license(
            name = "MIT",
            url = "https://opensource.org/licenses/MIT"
        )
    ),
    servers(
        (url = "http://localhost:3000", description = "Local development server"),
    )
)]
pub struct ApiDoc;

/// Health check endpoint
#[utoipa::path(
    get,
    path = "/health",
    tag = "health",
    responses(
        (status = 200, description = "Service is healthy", body = String),
        (status = 503, description = "Service unavailable")
    )
)]
pub async fn health_check(State(state): State<Arc<AppState>>) -> ApiResult<Json<serde_json::Value>> {
    crate::db::health_check(&state.pool).await?;
    Ok(Json(serde_json::json!({
        "status": "healthy",
        "service": "snep-certifications-api",
        "version": env!("CARGO_PKG_VERSION"),
    })))
}

/// List certifications with filters and pagination
#[utoipa::path(
    get,
    path = "/certifications",
    tag = "certifications",
    params(CertificationQueryParams),
    responses(
        (status = 200, description = "List of certifications", body = PaginatedResponse<CertificationResponse>),
        (status = 400, description = "Invalid query parameters", body = ErrorResponse),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn list_certifications(
    State(state): State<Arc<AppState>>,
    Query(params): Query<CertificationQueryParams>,
) -> ApiResult<Json<PaginatedResponse<CertificationResponse>>> {
    // Validate params
    params.validate()?;
    
    let result = CertificationRepository::list(&state.pool, &params).await?;
    Ok(Json(result))
}

/// Get certification by ID
#[utoipa::path(
    get,
    path = "/certifications/{id}",
    tag = "certifications",
    params(
        ("id" = Uuid, Path, description = "Certification UUID")
    ),
    responses(
        (status = 200, description = "Certification details", body = CertificationResponse),
        (status = 404, description = "Certification not found", body = ErrorResponse),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn get_certification(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<CertificationResponse>> {
    let cert = CertificationRepository::get_by_id(&state.pool, id).await?;
    Ok(Json(cert))
}

/// Get certification history
#[utoipa::path(
    get,
    path = "/certifications/{id}/history",
    tag = "certifications",
    params(
        ("id" = Uuid, Path, description = "Certification UUID")
    ),
    responses(
        (status = 200, description = "Certification history", body = Vec<CertificationHistory>),
        (status = 404, description = "Certification not found", body = ErrorResponse),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn get_certification_history(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<CertificationHistory>>> {
    // First verify certification exists
    CertificationRepository::get_by_id(&state.pool, id).await?;
    
    let history = CertificationRepository::get_history(&state.pool, id).await?;
    Ok(Json(history))
}

/// List artists
#[utoipa::path(
    get,
    path = "/artists",
    tag = "artists",
    params(
        ("page" = Option<u32>, Query, description = "Page number"),
        ("limit" = Option<u32>, Query, description = "Items per page"),
        ("search" = Option<String>, Query, description = "Search query"),
    ),
    responses(
        (status = 200, description = "List of artists", body = Vec<ArtistResponse>),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn list_artists(
    State(state): State<Arc<AppState>>,
    Query(params): Query<ArtistQueryParams>,
) -> ApiResult<Json<Vec<ArtistResponse>>> {
    let page = params.page.unwrap_or(1).max(1);
    let limit = params.limit.unwrap_or(50).clamp(1, 200) as i64;
    let offset = ((page - 1) * limit as u32) as i64;
    
    let artists = if let Some(search) = params.search {
        ArtistRepository::search(&state.pool, &search, limit).await?
    } else {
        ArtistRepository::list(&state.pool, limit, offset).await?
    };
    
    Ok(Json(artists))
}

/// Get artist by ID
#[utoipa::path(
    get,
    path = "/artists/{id}",
    tag = "artists",
    params(
        ("id" = Uuid, Path, description = "Artist UUID")
    ),
    responses(
        (status = 200, description = "Artist details", body = ArtistResponse),
        (status = 404, description = "Artist not found", body = ErrorResponse),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn get_artist(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<ArtistResponse>> {
    let artist = ArtistRepository::get_by_id(&state.pool, id).await?;
    Ok(Json(artist))
}

/// List labels
#[utoipa::path(
    get,
    path = "/labels",
    tag = "labels",
    params(
        ("page" = Option<u32>, Query, description = "Page number"),
        ("limit" = Option<u32>, Query, description = "Items per page"),
    ),
    responses(
        (status = 200, description = "List of labels", body = Vec<LabelResponse>),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn list_labels(
    State(state): State<Arc<AppState>>,
    Query(params): Query<LabelQueryParams>,
) -> ApiResult<Json<Vec<LabelResponse>>> {
    let page = params.page.unwrap_or(1).max(1);
    let limit = params.limit.unwrap_or(50).clamp(1, 200) as i64;
    let offset = ((page - 1) * limit as u32) as i64;
    
    let labels = LabelRepository::list(&state.pool, limit, offset).await?;
    Ok(Json(labels))
}

/// Get label by ID
#[utoipa::path(
    get,
    path = "/labels/{id}",
    tag = "labels",
    params(
        ("id" = Uuid, Path, description = "Label UUID")
    ),
    responses(
        (status = 200, description = "Label details", body = LabelResponse),
        (status = 404, description = "Label not found", body = ErrorResponse),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn get_label(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<LabelResponse>> {
    let label = LabelRepository::get_by_id(&state.pool, id).await?;
    Ok(Json(label))
}

/// Get statistics
#[utoipa::path(
    get,
    path = "/stats",
    tag = "stats",
    responses(
        (status = 200, description = "Statistics", body = StatsResponse),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn get_stats(
    State(state): State<Arc<AppState>>,
) -> ApiResult<Json<StatsResponse>> {
    let stats = CertificationRepository::get_stats(&state.pool).await?;
    Ok(Json(stats))
}

/// Get filter options
#[utoipa::path(
    get,
    path = "/filters",
    tag = "stats",
    responses(
        (status = 200, description = "Filter options", body = FilterOptionsResponse),
        (status = 500, description = "Internal server error", body = ErrorResponse)
    )
)]
pub async fn get_filter_options(
    State(state): State<Arc<AppState>>,
) -> ApiResult<Json<FilterOptionsResponse>> {
    let options = CertificationRepository::get_filter_options(&state.pool).await?;
    Ok(Json(options))
}

/// Query parameters for artists list
#[derive(Debug, Clone, Deserialize, utoipa::IntoParams)]
pub struct ArtistQueryParams {
    pub page: Option<u32>,
    pub limit: Option<u32>,
    pub search: Option<String>,
}

/// Query parameters for labels list
#[derive(Debug, Clone, Deserialize, utoipa::IntoParams)]
pub struct LabelQueryParams {
    pub page: Option<u32>,
    pub limit: Option<u32>,
}