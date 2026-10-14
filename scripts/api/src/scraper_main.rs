//! SNEP Scraper binary
//! 
//! Standalone scraper that can be run independently to fetch certifications from SNEP
//! and store them in the database.

use snep_certifications_api::{
    create_pool, repositories::CertificationRepository, scraper::SnepScraper,
};
use clap::Parser;
use std::sync::Arc;
use tracing::{info, Level};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Parser, Debug)]
#[command(name = "snep-scraper", version, about = "SNEP Certifications Scraper")]
struct Args {
    /// Database URL
    #[arg(long, env = "DATABASE_URL", default_value = "postgresql://postgres:postgres@localhost:5432/snep")]
    database_url: String,
    
    /// Max database connections
    #[arg(long, env = "DB_MAX_CONNECTIONS", default_value = "5")]
    max_connections: u32,
    
    /// Max pages to scrape (0 = all)
    #[arg(long, default_value = "0")]
    max_pages: u32,
    
    /// Delay between pages in seconds
    #[arg(long, default_value = "1")]
    delay: u64,
    
    /// Max retries per page
    #[arg(long, default_value = "3")]
    max_retries: u32,
    
    /// Timeout per request in seconds
    #[arg(long, default_value = "30")]
    timeout: u64,
    
    /// Test scrape only (no database writes)
    #[arg(long)]
    test_only: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "snep_scraper=info,sqlx=warn".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();
    
    let args = Args::parse();
    
    // Create scraper
    let scraper = SnepScraper::with_config(
        "https://snepmusique.com/les-certifications/".to_string(),
        args.delay,
        args.max_retries,
        args.timeout,
    )?;
    
    let max_pages = if args.max_pages > 0 { Some(args.max_pages) } else { None };
    
    info!("Starting SNEP scrape (max_pages={:?})...", max_pages);
    let certs = scraper.scrape_pages(max_pages).await?;
    info!("Total scraped: {}", certs.len());
    
    if args.test_only {
        info!("Test mode - showing first 10 certifications:");
        for cert in certs.iter().take(10) {
            println!("  {} | {} | {} | {} | key={}", 
                cert.artiste, cert.titre, cert.certification, cert.date_constat, cert.dedup_key());
        }
        return Ok(());
    }
    
    // Create database pool
    let pool = create_pool(&args.database_url, args.max_connections).await?;
    
    // Convert to insert format
    let inserts: Vec<_> = certs.iter().map(|c| c.to_certification(None)).collect();
    
    // Bulk insert
    let inserted = CertificationRepository::bulk_insert(&pool, &inserts).await?;
    info!("Inserted {} new certifications", inserted);
    
    Ok(())
}