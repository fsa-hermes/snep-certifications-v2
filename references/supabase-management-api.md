# Supabase Management API Reference

Used for server-side operations (DDL, project management, batch inserts) via PAT.

## Authentication

```bash
Authorization: Bearer <PAT>
# PAT format: sbp_xxx (Personal Access Token from https://supabase.com/dashboard/account/tokens)
```

## Project Management

### Create Project
```bash
POST /v1/projects
{name, organization_id, region, db_pass}
```
Response: `{id, ref, status, database: {host}}`

### Pause Project (free tier limit)
```bash
POST /v1/projects/{ref}/pause
```

### List Projects
```bash
GET /v1/projects
```

### Get API Keys
```bash
GET /v1/projects/{ref}/api-keys
```
Returns: `anon`, `service_role`, `publishable`, `secret` keys.

## Database Operations

### Execute SQL (DDL/DML)
```bash
POST /v1/projects/{ref}/database/query
{query: "SQL statement"}
```
- DDL (CREATE TABLE, CREATE INDEX): Returns `[]` on success
- DML (SELECT): Returns array of rows
- DML (INSERT/UPDATE/DELETE): Returns `[]` on success

### Batch Upsert Pattern
```sql
INSERT INTO certifications (col1, col2, ...) VALUES (...), (...), ... ON CONFLICT (dedup_key) DO NOTHING
```
- Batch size: 100 rows per request
- Use Management API (not REST) for bulk operations

## Client-Side (Vercel UI)

Use anon key with `@supabase/supabase-js` or direct REST:
```bash
GET /rest/v1/certifications?select=*
apikey: <anon_key>
Authorization: Bearer <anon_key>
```

## Key Differences

| Operation | API | Key |
|---|---|---|
| Create project | Management | PAT |
| Pause project | Management | PAT |
| CREATE TABLE | Management | PAT |
| Batch INSERT | Management | PAT |
| SELECT (UI) | REST | anon |
| Real-time | Realtime | anon |

## Common Patterns

### Create Table via Management API
```bash
curl -X POST https://api.supabase.com/v1/projects/{ref}/database/query \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{"query": "CREATE TABLE ..."}'
```

### Query with Pagination
```bash
curl -X POST https://api.supabase.com/v1/projects/{ref}/database/query \
  -H "Authorization: Bearer $PAT" \
  -d '{"query": "SELECT * FROM certifications LIMIT 100 OFFSET 0"}'
```

### Get Distinct Values for Filters
```bash
curl -X POST ... -d '{"query": "SELECT DISTINCT certification FROM certifications ORDER BY certification"}'
```

## Error Handling

- Invalid PAT: `{"message":"Invalid API key"}`
- SQL syntax error: `{"message":"syntax error at or near..."}`
- Duplicate key: `{"message":"duplicate key value violates unique constraint"}` (use ON CONFLICT)

## Rate Limits

Management API: ~60 req/min (not officially documented, be respectful)
REST API: Standard PostgREST limits