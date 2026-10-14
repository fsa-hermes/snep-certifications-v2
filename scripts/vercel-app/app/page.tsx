'use client'

import { useState, useEffect, useCallback, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Filters from './Filters'
import CertificationsTable from './CertificationsTable'
import { getStats, getFilterOptions } from '../lib/api'

export const dynamic = 'force-dynamic'

interface Stats {
  total: number
  byCert: Record<string, number>
  byCat: Record<string, number>
}

interface FiltersData {
  certifications: string[]
  categories: string[]
  artistes: string[]
}

function StatsHeader({ stats }: { stats: Stats }) {
  return (
    <header className="header">
      <h1>SNEP Certifications</h1>
      <div className="stats">
        <div className="stat">
          <div className="stat-value">{stats.total.toLocaleString()}</div>
          <div className="stat-label">Total</div>
        </div>
        <div className="stat">
          <div className="stat-value">{Object.keys(stats.byCert).length}</div>
          <div className="stat-label">Niveaux</div>
        </div>
        <div className="stat">
          <div className="stat-value">{Object.keys(stats.byCat).length}</div>
          <div className="stat-label">Catégories</div>
        </div>
      </div>
    </header>
  )
}

function LoadingStats() {
  return (
    <header className="header">
      <h1>SNEP Certifications</h1>
      <div className="stats">
        <div className="stat">
          <div className="stat-value">—</div>
          <div className="stat-label">Total</div>
        </div>
        <div className="stat">
          <div className="stat-value">—</div>
          <div className="stat-label">Niveaux</div>
        </div>
        <div className="stat">
          <div className="stat-value">—</div>
          <div className="stat-label">Catégories</div>
        </div>
      </div>
    </header>
  )
}

function FiltersWrapper({ initialFilters }: { initialFilters: FiltersData }) {
  const router = useRouter()
  const searchParams = useSearchParams()

  // Initialize state from URL params
  const [search, setSearch] = useState(searchParams.get('search') || '')
  const [certification, setCertification] = useState(searchParams.get('certification') || '')
  const [categorie, setCategorie] = useState(searchParams.get('categorie') || '')
  const [artiste, setArtiste] = useState(searchParams.get('artiste') || '')
  const [dateFrom, setDateFrom] = useState(searchParams.get('dateFrom') || '')
  const [dateTo, setDateTo] = useState(searchParams.get('dateTo') || '')
  const [sortBy, setSortBy] = useState(searchParams.get('sortBy') || 'date_constat')
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>(() =>
    (searchParams.get('sortOrder') as 'asc' | 'desc') || 'desc'
  )
  const [page, setPage] = useState(() => parseInt(searchParams.get('page') || '1', 10))
  const [limit] = useState(50)

  const updateUrl = useCallback(() => {
    const params = new URLSearchParams()
    if (search) params.set('search', search)
    if (certification) params.set('certification', certification)
    if (categorie) params.set('categorie', categorie)
    if (artiste) params.set('artiste', artiste)
    if (dateFrom) params.set('dateFrom', dateFrom)
    if (dateTo) params.set('dateTo', dateTo)
    if (sortBy !== 'date_constat') params.set('sortBy', sortBy)
    if (sortOrder !== 'desc') params.set('sortOrder', sortOrder)
    if (page > 1) params.set('page', page.toString())
    router.replace(`/?${params.toString()}`, { scroll: false })
  }, [search, certification, categorie, artiste, dateFrom, dateTo, sortBy, sortOrder, page, router])

  useEffect(() => {
    updateUrl()
  }, [updateUrl])

  const clearFilters = () => {
    setSearch('')
    setCertification('')
    setCategorie('')
    setArtiste('')
    setDateFrom('')
    setDateTo('')
    setPage(1)
  }

  const hasFilters = !!(search || certification || categorie || artiste || dateFrom || dateTo)

  return (
    <Filters
      initialFilters={initialFilters}
      search={search}
      setSearch={setSearch}
      certification={certification}
      setCertification={setCertification}
      categorie={categorie}
      setCategorie={setCategorie}
      artiste={artiste}
      setArtiste={setArtiste}
      dateFrom={dateFrom}
      setDateFrom={setDateFrom}
      dateTo={dateTo}
      setDateTo={setDateTo}
      sortBy={sortBy}
      setSortBy={setSortBy}
      sortOrder={sortOrder}
      setSortOrder={setSortOrder}
      page={page}
      setPage={setPage}
      clearFilters={clearFilters}
      hasFilters={hasFilters}
    />
  )
}

export default function HomePage() {
  const [stats, setStats] = useState<Stats | null>(null)
  const [filters, setFilters] = useState<FiltersData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function loadData() {
      try {
        const [statsData, filtersData] = await Promise.all([
          getStats(),
          getFilterOptions(),
        ])
        setStats(statsData)
        setFilters(filtersData)
      } catch (err) {
        console.error('Failed to load data:', err)
      } finally {
        setLoading(false)
      }
    }
    loadData()
  }, [])

  if (loading) {
    return (
      <div className="container">
        <LoadingStats />
        <div className="loading">Chargement des données...</div>
      </div>
    )
  }

  if (!stats || !filters) {
    return (
      <div className="container">
        <LoadingStats />
        <div className="empty">Erreur lors du chargement des données</div>
      </div>
    )
  }

  return (
    <div className="container">
      <StatsHeader stats={stats} />

      <Suspense fallback={<div className="loading">Chargement des filtres...</div>}>
        <FiltersWrapper initialFilters={filters} />
      </Suspense>

      <Suspense fallback={<div className="loading">Chargement des certifications...</div>}>
        <CertificationsTable initialStats={stats} />
      </Suspense>
    </div>
  )
}