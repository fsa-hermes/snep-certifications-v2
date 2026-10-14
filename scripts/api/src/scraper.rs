use crate::models::ScrapedCertification;
use crate::errors::ApiResult;
use chrono::{DateTime, Utc};
use regex::Regex;
use reqwest::{Client, ClientBuilder};
use scraper::{Html, Selector};
use select::document::Document;
use select::predicate::{Attr, Class, Name, Predicate};
use std::time::Duration;
use tracing::{info, warn, error};
use url::Url;

/// SNEP Scraper - ported from Python
pub struct SnepScraper {
    client: Client,
    base_url: String,
    delay_between_pages: Duration,
    max_retries: u32,
    timeout: Duration,
}

impl SnepScraper {
    pub fn new() -> ApiResult<Self> {
        let client = ClientBuilder::new()
            .user_agent("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
            .timeout(Duration::from_secs(30))
            .gzip(true)
            .brotli(true)
            .cookie_store(true)
            .build()?;
        
        Ok(Self {
            client,
            base_url: "https://snepmusique.com/les-certifications/".to_string(),
            delay_between_pages: Duration::from_secs(1),
            max_retries: 3,
            timeout: Duration::from_secs(30),
        })
    }
    
    pub fn with_config(
        base_url: String,
        delay_seconds: u64,
        max_retries: u32,
        timeout_seconds: u64,
    ) -> ApiResult<Self> {
        let client = ClientBuilder::new()
            .user_agent("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
            .timeout(Duration::from_secs(timeout_seconds))
            .gzip(true)
            .brotli(true)
            .cookie_store(true)
            .build()?;
        
        Ok(Self {
            client,
            base_url,
            delay_between_pages: Duration::from_secs(delay_seconds),
            max_retries,
            timeout: Duration::from_secs(timeout_seconds),
        })
    }
    
    /// Fetch a single page of certifications
    pub async fn fetch_page(&self, page: u32) -> ApiResult<String> {
        let url = if page == 1 {
            self.base_url.clone()
        } else {
            format!("{}page/{}/", self.base_url.trim_end_matches('/'))
        };
        
        for attempt in 0..self.max_retries {
            match self.client.get(&url).send().await {
                Ok(resp) => {
                    if resp.status().is_success() {
                        return Ok(resp.text().await?);
                    } else {
                        warn!("Page {} attempt {} failed with status: {}", page, attempt + 1, resp.status());
                    }
                }
                Err(e) => {
                    warn!("Page {} attempt {}/{} failed: {}", page, attempt + 1, self.max_retries, e);
                }
            }
            
            if attempt < self.max_retries - 1 {
                let delay = Duration::from_secs(2_u64.pow(attempt as u32));
                tokio::time::sleep(delay).await;
            }
        }
        
        Err(crate::errors::ApiError::Scraper(format!(
            "Failed to fetch page {} after {} attempts", page, self.max_retries
        )))
    }
    
    /// Parse certifications from page HTML
    pub fn parse_page(&self, html: &str, page: u32) -> Vec<ScrapedCertification> {
        let document = Document::from(html);
        let mut certs = Vec::new();
        
        // Find all certification divs
        for cert_node in document.find(Class("certification")) {
            if let Some(cert) = self.parse_certification(&cert_node, page) {
                certs.push(cert);
            }
        }
        
        certs
    }
    
    /// Parse a single certification from HTML node
    fn parse_certification(&self, cert_node: &select::node::Node, page: u32) -> Option<ScrapedCertification> {
        // Find description div
        let desc_node = cert_node.find(Class("description")).next()?;
        
        // Extract fields
        let categorie = desc_node.find(Class("categorie")).next()
            .map(|n| n.text().trim().to_string())
            .unwrap_or_default();
        
        let titre = desc_node.find(Class("titre")).next()
            .map(|n| n.text().trim().to_string())?;
        
        let artiste = desc_node.find(Class("artiste")).next()
            .map(|n| n.text().trim().to_string())?;
        
        let editeur = desc_node.find(Class("editeur")).next()
            .map(|n| n.text().trim().to_string())
            .unwrap_or_default();
        
        let certification = cert_node.find(Class("certif")).next()
            .map(|n| n.text().trim().to_string())?;
        
        // Parse dates
        let mut date_sortie = String::new();
        let mut date_constat = String::new();
        let mut duree_obtention = String::new();
        
        if let Some(dates_node) = cert_node.find(Class("block_dates")).next() {
            for date_node in dates_node.find(Class("date")) {
                if let Some(span) = date_node.find(Name("span")).next() {
                    let label = span.text().trim().to_string();
                    let val = date_node.text().replace(&label, "").trim().to_string();
                    
                    if label.contains("Date de sortie") {
                        date_sortie = val;
                    } else if label.contains("Date de constat") {
                        date_constat = val;
                    } else if label.contains("Durée") {
                        duree_obtention = val;
                    }
                }
            }
        }
        
        // Validate required fields
        if titre.is_empty() || artiste.is_empty() || certification.is_empty() {
            return None;
        }
        
        let source_url = if page > 1 {
            format!("{}page/{}/", self.base_url.trim_end_matches('/'), page)
        } else {
            self.base_url.clone()
        };
        
        Some(ScrapedCertification {
            categorie,
            titre,
            artiste,
            editeur,
            certification,
            date_sortie,
            date_constat,
            duree_obtention,
            source_url,
            scraped_at: Utc::now(),
        })
    }
    
    /// Check if there's a next page
    fn has_next_page(&self, html: &str, current_page: u32) -> bool {
        let document = Document::from(html);
        
        // Look for pager with "Suivante" link
        if let Some(pager) = document.find(Class("pager")).next() {
            // Check for "Suivante" or "Next" link
            for link in pager.find(Name("a")) {
                let text = link.text().to_lowercase();
                if text.contains("suivante") || text.contains("next") {
                    return true;
                }
            }
            
            // If on page 1, check for "Dernière" link
            if current_page == 1 {
                for link in pager.find(Name("a")) {
                    let text = link.text().to_lowercase();
                    if text.contains("dernière") || text.contains("last") {
                        return true;
                    }
                }
            }
        }
        
        false
    }
    
    /// Scrape multiple pages
    pub async fn scrape_pages(&self, max_pages: Option<u32>) -> ApiResult<Vec<ScrapedCertification>> {
        let mut all_certs = Vec::new();
        let mut page = 1u32;
        
        loop {
            if let Some(max) = max_pages {
                if page > max {
                    break;
                }
            }
            
            info!("Fetching page {}...", page);
            let html = self.fetch_page(page).await?;
            
            let certs = self.parse_page(&html, page);
            if certs.is_empty() {
                info!("No certifications on page {}, stopping", page);
                break;
            }
            
            info!("Page {}: {} certifications", page, certs.len());
            all_certs.extend(certs);
            
            // Check for next page
            if !self.has_next_page(&html, page) {
                info!("No next page found, stopping");
                break;
            }
            
            page += 1;
            tokio::time::sleep(self.delay_between_pages).await;
        }
        
        info!("Total scraped: {}", all_certs.len());
        Ok(all_certs)
    }
    
    /// Scrape all pages (convenience method)
    pub async fn scrape_all(&self) -> ApiResult<Vec<ScrapedCertification>> {
        self.scrape_pages(None).await
    }
}

impl Default for SnepScraper {
    fn default() -> Self {
        Self::new().expect("Failed to create SnepScraper")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    #[ignore] // Requires network
    async fn test_scrape_first_page() {
        let scraper = SnepScraper::new().unwrap();
        let certs = scraper.scrape_pages(Some(1)).await.unwrap();
        assert!(!certs.is_empty());
        println!("Scraped {} certifications", certs.len());
        for cert in &certs[..3.min(certs.len())] {
            println!("  {} - {} ({})", cert.artiste, cert.titre, cert.certification);
        }
    }
    
    #[test]
    fn test_dedup_key() {
        let cert = ScrapedCertification {
            categorie: "Singles".to_string(),
            titre: "Test Song".to_string(),
            artiste: "Test Artist".to_string(),
            editeur: "Test Label".to_string(),
            certification: "Or".to_string(),
            date_sortie: "01/01/2020".to_string(),
            date_constat: "15/02/2020".to_string(),
            duree_obtention: "45 jours".to_string(),
            source_url: "https://example.com".to_string(),
            scraped_at: Utc::now(),
        };
        
        let key = cert.dedup_key();
        assert_eq!(key.len(), 16);
        
        // Same data should produce same key
        let cert2 = cert.clone();
        assert_eq!(cert.dedup_key(), cert2.dedup_key());
        
        // Different artist should produce different key
        let mut cert3 = cert.clone();
        cert3.artiste = "Different Artist".to_string();
        assert_ne!(cert.dedup_key(), cert3.dedup_key());
    }
    
    #[test]
    fn test_parse_date() {
        assert_eq!(
            ScrapedCertification::parse_date("01/01/2020"),
            Some(chrono::NaiveDate::from_ymd_opt(2020, 1, 1).unwrap())
        );
        assert_eq!(
            ScrapedCertification::parse_date("31/12/2023"),
            Some(chrono::NaiveDate::from_ymd_opt(2023, 12, 31).unwrap())
        );
        assert_eq!(ScrapedCertification::parse_date("invalid"), None);
        assert_eq!(ScrapedCertification::parse_date(""), None);
    }
}