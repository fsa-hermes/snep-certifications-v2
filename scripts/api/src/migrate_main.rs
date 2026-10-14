//! Migration runner binary
//! 
//! Runs database migrations using SQLx.

use snep_certifications_api::create_pool;
use clap::Parser;
use tracing::{info, Level};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Parser, Debug)]
#[command(name = "snep-migrate", version, about = "SNEP Database Migration Runner")]
struct Args {
    /// Database URL
    #[arg(long, env = "DATABASE_URL", default_value = "postgresql://postgres:postgres@localhost:5432/snep")]
    database_url: String,
    
    /// Max database connections
    #[arg(long, env = "DB_MAX_CONNECTIONS", default_value = "5")]
    max_connections: u32,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "snep_migrate=info,sqlx=warn".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();
    
    let args = Args::parse();
    
    info!("Running database migrations...");
    let pool = create_pool(&args.database_url, args.max_connections).await?;
    
    info!("Migrations completed successfully");
    Ok(())
}