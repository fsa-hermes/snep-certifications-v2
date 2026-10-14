---
name: snep-certifications-agent
version: 1.0.0
description: "Scrape SNEP music certifications to Supabase with deduplication and Vercel UI."
author: Florent Salettes
license: MIT
platforms: [linux]
prerequisites:
  env_vars: [SUPABASE_PAT, SUPABASE_PROJECT_REF]
  commands: [python3, curl, npm]
metadata:
  hermes:
    tags: [SNEP, certifications, music, Supabase, scraper, automation, Vercel]
---

## When to Use

Use when you need to automatically fetch new French music certifications from SNEP (snepmusique.com/les-certifications/) and store them in Supabase, with built-in deduplication to avoid re-adding existing certifications on subsequent runs. Includes a Vercel/Next.js UI for browsing.

# SNEP Certifications Agent

Automated agent to fetch new French music certifications from SNEP and store them in Supabase, avoiding duplicates. Includes a dark-themed Next.js UI for browsing with search, filters, sorting, and pagination.

## Architecture

- **Scraper**: Fetches paginated HTML from SNEP, parses certification entries
- **Deduplication**: Uses composite key (artiste + titre + certification + date_constat) to avoid re-adding
- **Supabase sync**: Creates project via Management API, creates table via SQL, inserts via Management API batch upserts
- **State tracking**: Stores last sync timestamp and processed IDs locally (state.json)
- **Vercel UI**: Next.js 14 App Router, client-side filtering/sorting/pagination, URL state persistence

## Data Model

Each certification has:
- `categorie`: Singles / Albums
- `titre`: Song/album title
- `artiste`: Artist name
- `editeur`: Label/publisher
- `certification`: Or, Platine, Diamant, etc.
- `date_sortie`: Release date (DD/MM/YYYY)
- `date_constat`: Certification date (DD/MM/YYYY)
- `duree_obtention`: Time to certification
- `source_url`: SNEP page URL
- `scraped_at`: Timestamp when fetched
- `dedup_key`: SHA256(artiste|titre|certification|date_constat)[:16]

## Supabase Schema

```sql
CREATE TABLE certifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  categorie TEXT,
  titre TEXT NOT NULL,
  artiste TEXT NOT NULL,
  editeur TEXT,
  certification TEXT NOT NULL,
  date_sortie DATE,
  date_constat DATE,
  duree_obtention TEXT,
  source_url TEXT,
  dedup_key TEXT UNIQUE NOT NULL
);
CREATE INDEX idx_certifications_dedup ON certifications(dedup_key);
CREATE INDEX idx_certifications_artiste ON certifications(artiste);
CREATE INDEX idx_certifications_date_constat ON certifications(date_constat);
```

## Usage

```bash
# Set up Supabase PAT (Personal Access Token)
export SUPABASE_PAT=sbp_xxx

# Test scrape only
python3 scripts/snep_sync_supabase.py --test-scrape --pages 3

# Incremental sync (last N pages)
python3 scripts/snep_sync_supabase.py --project-ref <ref> --pat $SUPABASE_PAT --pages 10

# Full sync (all ~394 pages)
python3 scripts/snep_sync_supabase.py --project-ref <ref> --pat $SUPABASE_PAT --full

# Local Vercel UI dev
cd scripts/vercel-app && npm run dev
```

## Deduplication Logic

A certification is considered a duplicate if all four match:
- Artiste (normalized, lowercase, trimmed)
- Titre (normalized, lowercase, trimmed)
- Certification level (normalized, lowercase, trimmed)
- Date de constat (exact match)

This handles re-certifications (same track getting higher certification later = different certification level = new row).

## Files

- `scripts/snep_sync.py` — Original Notion sync (deprecated)
- `scripts/snep_sync_supabase.py` — Main Supabase sync script
- `scripts/requirements.txt` — Python dependencies (requests, beautifulsoup4)
- `scripts/vercel-app/` — Next.js 14 Vercel UI
- `scripts/api/` — Rust Axum backend (planned, subagent)

## References

- `references/supabase-management-api.md` — Management API patterns (PAT, DDL, batch inserts)
- `references/vercel-nextjs-patterns.md` — Next.js 14 App Router pitfalls (useSearchParams, TS config, git ignore)
- `references/github-api-patterns.md` — GitHub API via curl (repo create, token push, PAT scopes)

## Pitfalls & Lessons

### SNEP Scraping
- **Pagination detection**: Check for `.pager` div with "Suivante" link; stop when absent. Last page link "Dernière" only appears on page 1.
- **Rate limiting**: 1s delay between pages; 3 retries with exponential backoff.
- **HTML structure**: Each certification in `.certification` div → `.description` contains `.categorie`, `.titre`, `.artiste`, `.editeur`; `.certif` has level; `.block_dates` has three `.date` divs with `<span>` labels.
- **User-Agent required**: SNEP blocks requests without browser UA.

### Supabase Integration
- **Management API for DDL**: Use `POST /v1/projects/{ref}/database/query` with PAT for CREATE TABLE (REST API requires anon key but can't do DDL).
- **Batch inserts**: Use `INSERT ... ON CONFLICT (dedup_key) DO NOTHING` in batches of 100 via Management API.
- **PAT vs anon key**: PAT (sbp_*) for Management API; anon key for client-side Vercel UI.
- **Free tier limit**: 2 projects per org; pause unused projects via `POST /v1/projects/{ref}/pause` before creating new.
- **Project creation**: `POST /v1/projects` with `{name, organization_id, region, db_pass}` returns project ref; then fetch API keys via `GET /v1/projects/{ref}/api-keys`.

### Vercel/Next.js UI
- **useSearchParams() in App Router**: Must add `export const dynamic = 'force-dynamic'` to page.tsx OR wrap in Suspense boundary — otherwise static generation fails with "useSearchParams() should be wrapped in a suspense boundary".
- **TypeScript Set spread**: Needs `"target": "ES2015"` in tsconfig.json, otherwise `Type 'Set<any>' can only be iterated through when using the '--downlevelIteration' flag`.
- **next.config.js**: Use CommonJS `module.exports` not ESM `export default` — Next.js 14 doesn't support ESM config by default.
- **Standalone output**: Add `output: 'standalone'` for Vercel deployment.
- **Path aliases**: `@/*` paths don't work in App Router server components without proper tsconfig; use relative imports (`../lib/supabase`) instead.
- **Git push**: `.gitignore` MUST exclude `node_modules/` and `.next/` — otherwise GitHub rejects push (file size limit 100MB, SWC binary is 110MB). Use `git rm -r --cached node_modules .next` if already tracked.
- **Temporary deployment**: `npx vercel deploy --temporary` works without auth; gives URL valid ~60 min. Claim via `vercel.com/claim-deployment?code=...` or `npx vercel login && npx vercel --prod` for permanent.

### GitHub Integration
- **Token auth**: Push with `git push https://$GITHUB_TOKEN@github.com/owner/repo.git main` — token must have repo scope.
- **Repo creation**: `POST /user/repos` with `Authorization: token $TOKEN` creates repo; `full_name` in response gives `owner/repo` for remote URL.

### Enhanced Schema (Planned)
- **Artists with roles**: Many-to-many via `certification_artists` junction table with `role` enum ('singer', 'composer', 'both') — same track can have multiple artists (feat., &), each certified for different roles.
- **Labels**: Separate `labels` table linked via `label_id` FK on certifications; parse from `editeur` field (e.g., "D'OR ET DE PLATINE / BELIEVE" → two labels).
- **Certification history**: Track evolution (Or → Platine → Diamant) via `certification_history` table with `old_certification`, `new_certification`, `changed_at`; keyed by certification + date_constat changes.

## Notes

- SNEP has ~394 pages; full sync takes several minutes
- Respectful scraping: 1s delay between pages
- Handles network errors with retry (3 attempts, exponential backoff)
- Logs to stdout and `snep_sync.log`
- Vercel UI: dark theme, colored badges (Or=yellow, Platine=gray, Diamant=blue), responsive table, URL-persisted filters