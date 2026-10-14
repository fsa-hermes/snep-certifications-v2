# SNEP Certifications API - Dockerfile
# Multi-stage build for production deployment

# =============================================================================
# Builder stage - compile the Rust application
# =============================================================================
FROM rust:1.79-slim-bookworm AS builder

# Install system dependencies for building
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    libpq-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -m -u 1000 -s /bin/bash appuser

WORKDIR /app

# Copy Cargo files first for better caching
COPY Cargo.toml Cargo.lock ./
COPY migrations ./migrations

# Create a dummy main.rs to build dependencies
RUN mkdir -p src && echo "fn main() {}" > src/main.rs
RUN cargo build --release --bin snep-api 2>/dev/null || true
RUN rm -rf src

# Now copy actual source code
COPY src ./src

# Build the application
RUN cargo build --release --bin snep-api

# =============================================================================
# Scraper builder stage
# =============================================================================
FROM rust:1.79-slim-bookworm AS scraper-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    libpq-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY migrations ./migrations

RUN mkdir -p src && echo "fn main() {}" > src/main.rs
RUN cargo build --release --bin snep-scraper 2>/dev/null || true
RUN rm -rf src

COPY src ./src

RUN cargo build --release --bin snep-scraper

# =============================================================================
# Migrate builder stage
# =============================================================================
FROM rust:1.79-slim-bookworm AS migrate-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    libpq-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY migrations ./migrations

RUN mkdir -p src && echo "fn main() {}" > src/main.rs
RUN cargo build --release --bin snep-migrate 2>/dev/null || true
RUN rm -rf src

COPY src ./src

RUN cargo build --release --bin snep-migrate

# =============================================================================
# Runtime stage - minimal image with just the binary
# =============================================================================
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -m -u 1000 -s /bin/bash appuser

WORKDIR /app

# Copy binaries from builder stages
COPY --from=builder /app/target/release/snep-api /usr/local/bin/snep-api
COPY --from=scraper-builder /app/target/release/snep-scraper /usr/local/bin/snep-scraper
COPY --from=migrate-builder /app/target/release/snep-migrate /usr/local/bin/snep-migrate

# Copy migrations
COPY --from=builder /app/migrations ./migrations

# Set ownership
RUN chown -R appuser:appuser /app

USER appuser

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Default command
CMD ["snep-api"]

# =============================================================================
# Development stage - for local development with hot reload
# =============================================================================
FROM rust:1.79-slim-bookworm AS dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    libpq-dev \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install cargo-watch for hot reload
RUN cargo install cargo-watch

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY migrations ./migrations

# Pre-fetch dependencies
RUN mkdir -p src && echo "fn main() {}" > src/main.rs
RUN cargo build --bin snep-api 2>/dev/null || true
RUN rm -rf src

COPY src ./src

EXPOSE 3000

CMD ["cargo", "watch", "-x", "run --bin snep-api"]