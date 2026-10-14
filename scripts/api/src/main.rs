use snep_certifications_api::{
    create_pool, handlers::{
        get_artist, get_certification, get_certification_history, get_filter_options, get_label,
        get_stats, health_check, list_artists, list_certifications, list_labels, ApiDoc, AppState,
    },
    repositories::CertificationRepository,
    scraper::SnepScraper,
};
use axum::{
    routing::get,
    Router,
};
use clap::Parser;
use std::net::SocketAddr;
use std::sync::Arc;
use tower::ServiceBuilder;
use tower_http::{
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing::{info, Level};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Parser, Debug)]
#[command(name = "snep-certifications-api", version, about = "SNEP Certifications API")]
struct Args {
    /// Database URL
    #[arg(long, env = "DATABASE_URL", default_value = "postgresql://postgres:postgres@localhost:5432/snep")]
    database_url: String,
    
    /// Max database connections
    #[arg(long, env = "DB_MAX_CONNECTIONS", default_value = "10")]
    max_connections: u32,
    
    /// Server host
    #[arg(long, env = "HOST", default_value = "0.0.0.0")]
    host: String,
    
    /// Server port
    #[arg(long, env = "PORT", default_value = "3000")]
    port: u16,
    
    /// Enable CORS for all origins
    #[arg(long, env = "ENABLE_CORS", default_value = "true")]
    enable_cors: bool,
    
    /// Run scraper and exit
    #[arg(long)]
    scrape: bool,
    
    /// Max pages to scrape (0 = all)
    #[arg(long, default_value = "0")]
    max_pages: u32,
    
    /// Run migrations only
    #[arg(long)]
    migrate_only: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "snep_certifications_api=info,tower_http=info,sqlx=warn".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();
    
    let args = Args::parse();
    
    // Create database pool
    let pool = create_pool(&args.database_url, args.max_connections).await?;
    
    // Run migrations only if requested
    if args.migrate_only {
        info!("Migrations completed successfully");
        return Ok(());
    }
    
    // Run scraper if requested
    if args.scrape {
        info!("Running SNEP scraper...");
        let scraper = SnepScraper::new()?;
        let max_pages = if args.max_pages > 0 { Some(args.max_pages) } else { None };
        let certs = scraper.scrape_pages(max_pages).await?;
        info!("Scraped {} certifications", certs.len());
        
        // Insert into database
        let inserts: Vec<_> = certs.iter().map(|c| c.to_certification(None)).collect();
        let inserted = CertificationRepository::bulk_insert(&pool, &inserts).await?;
        info!("Inserted {} new certifications", inserted);
        
        return Ok(());
    }
    
    // Create app state
    let state = Arc::new(AppState { pool });
    
    // Build router
    let mut app = Router::new()
        .route("/health", get(health_check))
        .route("/certifications", get(list_certifications))
        .route("/certifications/:id", get(get_certification))
        .route("/certifications/:id/history", get(get_certification_history))
        .route("/artists", get(list_artists))
        .route("/artists/:id", get(get_artist))
        .route("/labels", get(list_labels))
        .route("/labels/:id", get(get_label))
        .route("/stats", get(get_stats))
        .route("/filters", get(get_filter_options))
        .with_state(state);
    
    // Add Swagger UI
    app = app.merge(utoipa_swagger_ui::SwaggerUi::new("/swagger-ui")
        .url("/api-docs/openapi.json", ApiDoc::openapi()));
    
    // Add middleware
    let cors = if args.enable_cors {
        CorsLayer::new()
            .allow_origin(Any)
            .allow_methods(Any)
            .allow_headers(Any)
    } else {
        CorsLayer::new()
    };
    
    app = app.layer(
        ServiceBuilder::new()
            .layer(TraceLayer::new_for_http())
            .layer(cors)
    );
    
    // Start server
    let addr: SocketAddr = format!("{}:{}", args.host, args.port).parse()?;
    info!("Starting server on {}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum_test::TestServer;
    
    async fn create_test_app() -> TestServer {
        let database_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgresql://postgres:postgres@localhost:5432/snep_test".to_string());
        let pool = create_pool(&database_url, 5).await.expect("Failed to create pool");
        let state = Arc::new(AppState { pool });
        
        let app = Router::new()
            .route("/health", get(health_check))
            .route("/certifications", get(list_certifications))
            .route("/certifications/:id", get(get_certification))
            .route("/certifications/:id/history", get(get_certification_history))
            .route("/artists", get(list_artists))
            .route("/artists/:id", get(get_artist))
            .route("/labels", get(list_labels))
            .route("/labels/:id", get(get_label))
            .route("/stats", get(get_stats))
            .route("/filters", get(get_filter_options))
            .with_state(state);
        
        TestServer::new(app).unwrap()
    }
    
    #[tokio::test]
    #[ignore]
    async fn test_health_check() {
        let server = create_test_app().await;
        let response = server.get("/health").await;
        assert_eq!(response.status_code(), 200);
    }
    
    #[tokio::test]
    #[ignore]
    async fn test_list_certifications() {
        let server = create_test_app().await;
        let response = server.get("/certifications").await;
        assert_eq!(response.status_code(), 200);
        
        let body: PaginatedResponse<CertificationResponse> = response.json();
        assert!(body.total >= 0);
    }
}