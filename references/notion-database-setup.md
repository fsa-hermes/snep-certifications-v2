# Notion Database Setup for SNEP Certifications

## Create the Database

1. In Notion, create a new **Database - Table** on a page
2. Share the page with your integration: page menu `...` → `Connect to` → your integration name
3. Copy the database ID from the URL: `https://notion.so/workspace/DB_ID?v=...`

## Required Properties

| Property Name | Type | Options / Notes |
|---|---|---|
| **Titre** | Title | Primary title field |
| **Artiste** | Rich text | |
| **Catégorie** | Select | Singles, Albums |
| **Certification** | Select | Or, Platine, Diamant, Double Platine, Triple Platine, Double Diamant, Triple Diamant, Quadruple Diamant |
| **Éditeur** | Rich text | |
| **Date de sortie** | Date | Format: DD/MM/YYYY input |
| **Date de constat** | Date | Format: DD/MM/YYYY input |
| **Durée d'obtention** | Rich text | e.g. "2 ans 4 mois" |
| **URL SNEP** | URL | Source page link |
| **ID Unique** | Rich text | **Critical for deduplication** — stores SHA256 hash |
| **Date d'ajout** | Date | Auto-filled by script |

## Select Options for Certification

The SNEP site uses these certification levels (singles):
- Or (15M streams)
- Platine (30M streams)
- Diamant (50M streams)

And for albums:
- Or (50k equiv. sales)
- Platine (100k)
- Double Platine (200k)
- Triple Platine (300k)
- Diamant (500k)
- Double Diamant (1M)
- Triple Diamant (1.5M)
- Quadruple Diamant (2M)

Add all as select options in the Certification property.

## Get Database ID

The database ID is the 32-char UUID in the URL:
```
https://notion.so/your-workspace/abcdef1234567890abcdef1234567890?v=...
                                                 ^^^^^^^^^^^^^^^^^^^^ 32 chars
```

Use this with `--database-id abcdef1234567890abcdef1234567890` (with or without dashes).

## Integration Token

Create at https://notion.so/my-integrations:
1. New integration → name it → submit
2. Copy the `Internal Integration Token` (starts with `ntn_` or `secret_`)
3. Add to environment: `export NOTION_API_KEY=ntn_xxx`
4. **Must share the database page with the integration** or API returns 404

## Troubleshooting

| Error | Fix |
|---|---|
| 401 Unauthorized | Check NOTION_API_KEY is set and valid |
| 404 Not Found | Share the database/page with the integration |
| 400 Bad Request | Property name mismatch — check exact spelling (case-sensitive) |
| Select option not found | Add the certification value to the Select options in Notion |
| Rate limited | Script has 0.3s delay; increase if needed |

## Property Name Matching

The script uses **exact French property names** as column headers. Do not rename them in Notion, or update the script's `to_notion_properties()` method to match.

Key mappings in code:
```python
"Titre" → title
"Artiste" → rich_text
"Catégorie" → select
"Certification" → select
"Éditeur" → rich_text
"Date de sortie" → date
"Date de constat" → date
"Durée d'obtention" → rich_text
"URL SNEP" → url
"ID Unique" → rich_text
"Date d'ajout" → date
```