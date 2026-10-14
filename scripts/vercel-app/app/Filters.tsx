'use client'

import { ChangeEvent } from 'react'

interface FiltersProps {
  initialFilters: {
    certifications: string[]
    categories: string[]
    artistes: string[]
  }
  search: string
  setSearch: (value: string) => void
  certification: string
  setCertification: (value: string) => void
  categorie: string
  setCategorie: (value: string) => void
  artiste: string
  setArtiste: (value: string) => void
  dateFrom: string
  setDateFrom: (value: string) => void
  dateTo: string
  setDateTo: (value: string) => void
  sortBy: string
  setSortBy: (value: string) => void
  sortOrder: 'asc' | 'desc'
  setSortOrder: (value: 'asc' | 'desc') => void
  page: number
  setPage: (value: number) => void
  clearFilters: () => void
  hasFilters: boolean
}

export default function Filters({
  initialFilters,
  search,
  setSearch,
  certification,
  setCertification,
  categorie,
  setCategorie,
  artiste,
  setArtiste,
  dateFrom,
  setDateFrom,
  dateTo,
  setDateTo,
  sortBy,
  setSortBy,
  sortOrder,
  setSortOrder,
  page,
  setPage,
  clearFilters,
  hasFilters,
}: FiltersProps) {
  const handleSearchChange = (e: ChangeEvent<HTMLInputElement>) => {
    setSearch(e.target.value)
    setPage(1)
  }

  const handleCertificationChange = (e: ChangeEvent<HTMLSelectElement>) => {
    setCertification(e.target.value)
    setPage(1)
  }

  const handleCategorieChange = (e: ChangeEvent<HTMLSelectElement>) => {
    setCategorie(e.target.value)
    setPage(1)
  }

  const handleArtisteChange = (e: ChangeEvent<HTMLSelectElement>) => {
    setArtiste(e.target.value)
    setPage(1)
  }

  const handleDateFromChange = (e: ChangeEvent<HTMLInputElement>) => {
    setDateFrom(e.target.value)
    setPage(1)
  }

  const handleDateToChange = (e: ChangeEvent<HTMLInputElement>) => {
    setDateTo(e.target.value)
    setPage(1)
  }

  const handleSort = (column: string) => {
    if (sortBy === column) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')
    } else {
      setSortBy(column)
      setSortOrder('desc')
    }
    setPage(1)
  }

  return (
    <div className="filters">
      <div className="filter-group">
        <label>Recherche</label>
        <input
          type="text"
          className="search-input"
          placeholder="Titre, artiste, éditeur..."
          value={search}
          onChange={handleSearchChange}
        />
      </div>

      <div className="filter-group">
        <label>Certification</label>
        <select value={certification} onChange={handleCertificationChange}>
          <option value="">Toutes</option>
          {initialFilters.certifications.map(c => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>
      </div>

      <div className="filter-group">
        <label>Catégorie</label>
        <select value={categorie} onChange={handleCategorieChange}>
          <option value="">Toutes</option>
          {initialFilters.categories.map(c => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>
      </div>

      <div className="filter-group">
        <label>Artiste</label>
        <select value={artiste} onChange={handleArtisteChange}>
          <option value="">Tous</option>
          {initialFilters.artistes.map(a => (
            <option key={a} value={a}>{a}</option>
          ))}
        </select>
      </div>

      <div className="filter-group">
        <label>Date constat (de)</label>
        <input type="date" value={dateFrom} onChange={handleDateFromChange} />
      </div>

      <div className="filter-group">
        <label>Date constat (à)</label>
        <input type="date" value={dateTo} onChange={handleDateToChange} />
      </div>

      {hasFilters && (
        <div className="filter-group" style={{ alignSelf: 'flex-end' }}>
          <label>&nbsp;</label>
          <button
            onClick={clearFilters}
            style={{
              background: 'var(--bg)',
              border: '1px solid var(--border)',
              color: 'var(--text-muted)',
              padding: '8px 16px',
              borderRadius: '6px',
              cursor: 'pointer',
            }}
          >
            Effacer filtres
          </button>
        </div>
      )}
    </div>
  )
}