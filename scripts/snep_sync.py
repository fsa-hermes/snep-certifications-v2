#!/usr/bin/env python3
"""
SNEP Certifications Scraper & Notion Sync

Fetches French music certifications from snepmusique.com and stores them in Notion.
"""

import os
import re
import json
import time
import logging
import hashlib
from datetime import datetime
from typing import Optional
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
    
    def to_notion_properties(self, database_id: str) -> dict:
        """Convert to Notion page properties."""
        def parse_date(d: str) -> Optional[str]:
            try:
                return datetime.strptime(d.strip(), "%d/%m/%Y").date().isoformat()
            except:
                return None
        
        props = {
            "Titre": {"title": [{"text": {"content": self.titre.strip()}}]},
            "Artiste": {"rich_text": [{"text": {"content": self.artiste.strip()}}]},
            "Catégorie": {"select": {"name": self.categorie.strip()}},
            "Certification": {"select": {"name": self.certification.strip()}},
            "Éditeur": {"rich_text": [{"text": {"content": self.editeur.strip()}}]},
            "ID Unique": {"rich_text": [{"text": {"content": self.dedup_key()}}]},
            "URL SNEP": {"url": self.source_url},
            "Date d'ajout": {"date": {"start": self.scraped_at[:10]}},
        }
        
        d_sortie = parse_date(self.date_sortie)
        if d_sortie:
            props["Date de sortie"] = {"date": {"start": d_sortie}}
        
        d_constat = parse_date(self.date_constat)
        if d_constat:
            props["Date de constat"] = {"date": {"start": d_constat}}
        
        if self.duree_obtention.strip():
            props["Durée d'obtention"] = {"rich_text": [{"text": {"content": self.duree_obtention.strip()}}]}
        
        return {
            "parent": {"database_id": database_id},
            "properties": props
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

# ─── Notion Client ───
class NotionClient:
    def __init__(self, api_key: str, database_id: str):
        self.api_key = api_key
        self.database_id = database_id
        self.base_url = "https://api.notion.com/v1"
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Notion-Version": "2025-09-03",
            "Content-Type": "application/json"
        }
    
    def query_existing_keys(self) -> set[str]:
        """Fetch all existing dedup keys from Notion."""
        keys = set()
        has_more = True
        start_cursor = None
        
        while has_more:
            payload = {"page_size": 100}
            if start_cursor:
                payload["start_cursor"] = start_cursor
            
            try:
                resp = requests.post(
                    f"{self.base_url}/data_sources/{self.database_id}/query",
                    headers=self.headers,
                    json=payload,
                    timeout=TIMEOUT
                )
                resp.raise_for_status()
                data = resp.json()
                
                for page in data.get("results", []):
                    props = page.get("properties", {})
                    id_prop = props.get("ID Unique", {})
                    if id_prop.get("rich_text"):
                        keys.add(id_prop["rich_text"][0]["text"]["content"])
                
                has_more = data.get("has_more", False)
                start_cursor = data.get("next_cursor")
            except Exception as e:
                log.error(f"Failed to query Notion: {e}")
                break
        
        log.info(f"Found {len(keys)} existing certifications in Notion")
        return keys
    
    def create_certification(self, cert: Certification) -> bool:
        """Create a new certification page in Notion."""
        payload = cert.to_notion_properties(self.database_id)
        try:
            resp = requests.post(
                f"{self.base_url}/pages",
                headers=self.headers,
                json=payload,
                timeout=TIMEOUT
            )
            resp.raise_for_status()
            log.info(f"Created: {cert.artiste} - {cert.titre} ({cert.certification})")
            return True
        except Exception as e:
            log.error(f"Failed to create {cert.artiste} - {cert.titre}: {e}")
            if hasattr(e, 'response') and e.response is not None:
                log.error(f"Response: {e.response.text}")
            return False

# ─── Main Sync Logic ───
def run_sync(database_id: str, max_pages: Optional[int] = None, test_only: bool = False):
    """Run the full sync process."""
    api_key = os.getenv("NOTION_API_KEY")
    if not api_key and not test_only:
        log.error("NOTION_API_KEY not set")
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
    
    notion = NotionClient(api_key, database_id)
    existing_keys = notion.query_existing_keys()
    
    all_known_keys = processed_keys | existing_keys
    
    new_certs = [c for c in certifications if c.dedup_key() not in all_known_keys]
    log.info(f"New certifications to add: {len(new_certs)}")
    
    added = 0
    for cert in new_certs:
        if notion.create_certification(cert):
            added += 1
            processed_keys.add(cert.dedup_key())
        time.sleep(0.3)  # Rate limiting
    
    state["processed_keys"] = list(processed_keys)
    state["last_sync"] = datetime.utcnow().isoformat()
    state["last_page"] = max_pages or 1
    save_state(state)
    
    log.info(f"Sync complete. Added {added}/{len(new_certs)} new certifications.")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="SNEP → Notion sync")
    parser.add_argument("--database-id", required=False, help="Notion database ID")
    parser.add_argument("--pages", type=int, help="Max pages to scrape")
    parser.add_argument("--full", action="store_true", help="Scrape all pages")
    parser.add_argument("--test-scrape", action="store_true", help="Test scrape only, no Notion")
    args = parser.parse_args()
    
    if args.test_scrape:
        run_sync("", max_pages=args.pages, test_only=True)
    else:
        if not args.database_id:
            parser.error("--database-id required for Notion sync")
        run_sync(args.database_id, max_pages=None if args.full else args.pages)
