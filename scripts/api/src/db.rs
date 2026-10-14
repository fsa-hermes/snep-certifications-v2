use sqlx::{postgres::PgPoolOptions, Pool, Postgres};
use std::time::Duration;

pub type DbPool = Pool<Postgres>;

/// Create a new database connection pool
pub async fn create_pool(database_url: &str, max_connections: u32) -> anyhow::Result<DbPool> {
    let pool = PgPoolOptions::new()
        .max_connections(max_connections)
        .acquire_timeout(Duration::from_secs(30))
        .idle_timeout(Duration::from_secs(600))
        .max_lifetime(Duration::from_secs(1800))
        .connect(database_url)
        .await?;
    
    // Run migrations
    sqlx::migrate!("./migrations").run(&pool).await?;
    
    tracing::info!("Database pool created and migrations applied");
    Ok(pool)
}

/// Health check for the database connection
pub async fn health_check(pool: &DbPool) -> anyhow::Result<()> {
    sqlx::query("SELECT 1").execute(pool).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    #[ignore] // Requires running database
    async fn test_create_pool() {
        let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL not set");
        let pool = create_pool(&database_url, 5).await.expect("Failed to create pool");
        health_check(&pool).await.expect("Health check failed");
    }
}