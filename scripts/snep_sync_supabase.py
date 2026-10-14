#!/usr/bin/env python3
"""
SNEP Certifications Scraper & Supabase Sync

Fetches French music certifications from snepmusique.com and stores them in Supabase.
"""

import os
import re
import json
import time
import logging
import hashlib
from datetime import datetime
from typing import Optional, Set
from dataclasses import dataclass
from pathlib import Path

import requests
from bs4 import BeautifulSoup

# ─── Config ───
BASE_URL = "https://snepmusique.com/les-certifications/"
STATE_FILE = Path(__file__).parent / "state.json"
LOG_FILE = Path(__file__).parent / "snep_sync.log"
DELAY_BETWEEN_PAGES = 1.0  # seconds
MAX_RETRIES = 3
TIMEOUT = 30

# Supabase config (set via env or edit here)
SUPABASE_PROJECT_REF = os.getenv("SUPABASE_PROJECT_REF", "qxgareduswbtrmfsfhek")
SUPABASE_PAT = os.getenv("SUPABASE_PAT")  # Personal Access Token

# ─── Logging ───
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# ─── Data Model ───
@dataclass
class Certification:
    categorie: str
    titre: str
    artiste: str
    editeur: str
    certification: str
    date_sortie: str
    date_constat: str
    duree_obtention: str
    source_url: str
    scraped_at: str
    
    def dedup_key(self) -> str:
        """Composite key for deduplication."""
        parts = [
            self.artiste.strip().lower(),
            self.titre.strip().lower(),
            self.certification.strip().lower(),
            self.date_constat.strip()
        ]
        return hashlib.sha256("|".join(parts).encode()).hexdigest()[:16]
    
    def to_supabase_row(self) -> dict:
        """Convert to Supabase row dict."""
        def parse_date(d: str) -> Optional[str]:
            try:
                return datetime.strptime(d.strip(), "%d/%m/%Y").date().isoformat()
            except:
                return None
        
        return {
            "categorie": self.categorie.strip() or None,
            "titre": self.titre.strip(),
            "artiste": self.artiste.strip(),
            "editeur": self.editeur.strip() or None,
            "certification": self.certification.strip(),
            "date_sortie": parse_date(self.date_sortie),
            "date_constat": parse_date(self.date_constat),
            "duree_obtention": self.duree_obtention.strip() or None,
            "source_url": self.source_url,
            "dedup_key": self.dedup_key(),
            "created_at": self.scraped_at,
        }

# ─── State Management ───
def load_state() -> dict:
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"processed_keys": [], "last_sync": None, "last_page": 1}

def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

# ─── SNEP Scraper ───
class SNEPScraper:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        })
    
    def fetch_page(self, page: int) -> Optional[str]:
        """Fetch a single page of certifications."""
        url = BASE_URL if page == 1 else f"{BASE_URL}page/{page}/"
        for attempt in range(MAX_RETRIES):
            try:
                resp = self.session.get(url, timeout=TIMEOUT)
                resp.raise_for_status()
                return resp.text
            except Exception as e:
                log.warning(f"Page {page} attempt {attempt+1}/{MAX_RETRIES} failed: {e}")
                if attempt < MAX_RETRIES - 1:
                    time.sleep(2 ** attempt)
        log.error(f"Failed to fetch page {page} after {MAX_RETRIES} attempts")
        return None
    
    def parse_page(self, html: str, page: int) -> list[Certification]:
        """Parse certifications from page HTML."""
        soup = BeautifulSoup(html, 'html.parser')
        certs = []
        
        for cert_div in soup.find_all('div', class_='certification'):
            try:
                desc = cert_div.find('div', class_='description')
                if not desc:
                    continue
                
                cat = desc.find('div', class_='categorie')
                titre = desc.find('div', class_='titre')
                artiste = desc.find('div', class_='artiste')
                editeur = desc.find('div', class_='editeur')
                
                certif = cert_div.find('div', class_='certif')
                
                dates = cert_div.find('div', class_='block_dates')
                date_sortie = date_constat = duree = ""
                if dates:
                    for d in dates.find_all('div', class_='date'):
                        span = d.find('span')
                        if not span:
                            continue
                        label = span.get_text(strip=True)
                        val = d.get_text(strip=True).replace(label, '').strip()
                        if 'Date de sortie' in label:
                            date_sortie = val
                        elif 'Date de constat' in label:
                            date_constat = val
                        elif 'Durée' in label:
                            duree = val
                
                if not (titre and artiste and certif):
                    continue
                
                certs.append(Certification(
                    categorie=cat.get_text(strip=True) if cat else "",
                    titre=titre.get_text(strip=True),
                    artiste=artiste.get_text(strip=True),
                    editeur=editeur.get_text(strip=True) if editeur else "",
                    certification=certif.get_text(strip=True),
                    date_sortie=date_sortie,
                    date_constat=date_constat,
                    duree_obtention=duree,
                    source_url=f"{BASE_URL}page/{page}/" if page > 1 else BASE_URL,
                    scraped_at=datetime.utcnow().isoformat()
                ))
            except Exception as e:
                log.warning(f"Failed to parse certification on page {page}: {e}")
        
        return certs
    
    def scrape_pages(self, max_pages: Optional[int] = None) -> list[Certification]:
        """Scrape certifications from multiple pages."""
        all_certs = []
        page = 1
        
        while True:
            if max_pages and page > max_pages:
                break
            
            log.info(f"Fetching page {page}...")
            html = self.fetch_page(page)
            if not html:
                break
            
            certs = self.parse_page(html, page)
            if not certs:
                log.info(f"No certifications on page {page}, stopping")
                break
            
            all_certs.extend(certs)
            log.info(f"Page {page}: {len(certs)} certifications")
            
            # Check for next page link
            soup = BeautifulSoup(html, 'html.parser')
            pager = soup.find('div', class_='pager')
            if not pager:
                break
            next_link = pager.find('a', string=re.compile(r'Suivante|Next', re.I))
            if not next_link:
                last_link = pager.find('a', string=re.compile(r'Dernière|Last', re.I))
                if last_link and page == 1:
                    break
            
            page += 1
            time.sleep(DELAY_BETWEEN_PAGES)
        
        return all_certs

# ─── Supabase Client (via Management API) ───
class SupabaseClient:
    def __init__(self, project_ref: str, pat: str):
        self.project_ref = project_ref
        self.pat = pat
        self.base_url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"
        self.headers = {
            "Authorization": f"Bearer {pat}",
            "Content-Type": "application/json"
        }
    
    def query_existing_keys(self) -> Set[str]:
        """Fetch all existing dedup keys from Supabase."""
        keys = set()
        offset = 0
        limit = 1000
        
        while True:
            try:
                resp = requests.post(
                    self.base_url,
                    headers=self.headers,
                    json={"query": f"SELECT dedup_key FROM certifications LIMIT {limit} OFFSET {offset}"},
                    timeout=TIMEOUT
                )
                resp.raise_for_status()
                data = resp.json()
                
                if not data:
                    break
                
                for row in data:
                    keys.add(row["dedup_key"])
                
                if len(data) < limit:
                    break
                offset += limit
            except Exception as e:
                log.error(f"Failed to query Supabase: {e}")
                break
        
        log.info(f"Found {len(keys)} existing certifications in Supabase")
        return keys
    
    def insert_certifications(self, certs: list[Certification]) -> int:
        """Insert multiple certifications in batches."""
        if not certs:
            return 0
        
        batch_size = 100
        inserted = 0
        
        for i in range(0, len(certs), batch_size):
            batch = certs[i:i + batch_size]
            rows = [c.to_supabase_row() for c in batch]
            
            # Build INSERT with ON CONFLICT DO NOTHING
            columns = list(rows[0].keys())
            col_str = ", ".join(columns)
            
            values_list = []
            for row in rows:
                vals = []
                for col in columns:
                    v = row[col]
                    if isinstance(v, str):
                        # Escape single quotes
                        v = v.replace("'", "''")
                        vals.append(f"'{v}'")
                    elif v is None:
                        vals.append("NULL")
                    else:
                        vals.append(str(v))
                values_list.append(f"({', '.join(vals)})")
            
            values_str = ", ".join(values_list)
            query = f"INSERT INTO certifications ({col_str}) VALUES {values_str} ON CONFLICT (dedup_key) DO NOTHING"
            
            try:
                resp = requests.post(
                    self.base_url,
                    headers=self.headers,
                    json={"query": query},
                    timeout=TIMEOUT
                )
                resp.raise_for_status()
                # Management API returns empty array on success for DML
                inserted += len(batch)
                log.info(f"Inserted batch {i//batch_size + 1}: {len(batch)} certifications")
            except Exception as e:
                log.error(f"Failed to insert batch {i//batch_size + 1}: {e}")
                if hasattr(e, 'response') and e.response is not None:
                    log.error(f"Response: {e.response.text}")
            
            time.sleep(0.2)
        
        return inserted

# ─── Main Sync Logic ───
def run_sync(project_ref: str, pat: str, max_pages: Optional[int] = None, test_only: bool = False):
    """Run the full sync process."""
    if not pat and not test_only:
        log.error("SUPABASE_PAT not set")
        return
    
    state = load_state()
    processed_keys = set(state.get("processed_keys", []))
    
    scraper = SNEPScraper()
    log.info(f"Starting scrape (max_pages={max_pages or 'all'})")
    certifications = scraper.scrape_pages(max_pages)
    log.info(f"Total scraped: {len(certifications)}")
    
    if test_only:
        for c in certifications[:10]:
            print(f"  {c.artiste} | {c.titre} | {c.certification} | {c.date_constat} | key={c.dedup_key()}")
        return
    
    supabase = SupabaseClient(project_ref, pat)
    existing_keys = supabase.query_existing_keys()
    
    all_known_keys = processed_keys | existing_keys
    
    new_certs = [c for c in certifications if c.dedup_key() not in all_known_keys]
    log.info(f"New certifications to add: {len(new_certs)}")
    
    inserted = supabase.insert_certifications(new_certs)
    
    # Update local state with all known keys
    for c in new_certs:
        processed_keys.add(c.dedup_key())
    
    state["processed_keys"] = list(processed_keys)
    state["last_sync"] = datetime.utcnow().isoformat()
    state["last_page"] = max_pages or 1
    save_state(state)
    
    log.info(f"Sync complete. Inserted {inserted}/{len(new_certs)} new certifications.")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="SNEP → Supabase sync")
    parser.add_argument("--project-ref", default=SUPABASE_PROJECT_REF, help="Supabase project ref")
    parser.add_argument("--pat", default=SUPABASE_PAT, help="Supabase Personal Access Token")
    parser.add_argument("--pages", type=int, help="Max pages to scrape")
    parser.add_argument("--full", action="store_true", help="Scrape all pages")
    parser.add_argument("--test-scrape", action="store_true", help="Test scrape only, no Supabase")
    args = parser.parse_args()
    
    if args.test_scrape:
        run_sync(args.project_ref, args.pat, max_pages=args.pages, test_only=True)
    else:
        if not args.pat:
            parser.error("--pat required for Supabase sync (or set SUPABASE_PAT env)")
        run_sync(args.project_ref, args.pat, max_pages=None if args.full else args.pages)
