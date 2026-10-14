'use client'

import { useState, useEffect } from 'react'
import { useSearchParams } from 'next/navigation'
import { fetchCertifications, type Certification } from '../lib/api'

interface CertificationsTableProps {
  initialStats: {
    total: number
    byCert: Record<string, number>
    byCat: Record<string, number>
  }
}

export default function CertificationsTable({ initialStats }: CertificationsTableProps) {
  const searchParams = useSearchParams()
  const [data, setData] = useState<Certification[]>([])
  const [count, setCount] = useState(initialStats.total)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Extract params from URL
  const params = {
    page: parseInt(searchParams.get('page') || '1', 10),
    limit: 50,
    search: searchParams.get('search') || undefined,
    certification: searchParams.get('certification') || undefined,
    categorie: searchParams.get('categorie') || undefined,
    artiste: searchParams.get('artiste') || undefined,
    dateFrom: searchParams.get('dateFrom') || undefined,
    dateTo: searchParams.get('dateTo') || undefined,
    sortBy: searchParams.get('sortBy') || 'date_constat',
    sortOrder: (searchParams.get('sortOrder') as 'asc' | 'desc') || 'desc',
  }

  useEffect(() => {
    let mounted = true
    setLoading(true)
    setError(null)

    fetchCertifications(params)
      .then(({ data, count, error }) => {
        if (mounted) {
          setData(data)
          setCount(count)
          if (error) setError(error)
        }
      })
      .catch(err => {
        if (mounted) setError(err.message)
      })
      .finally(() => {
        if (mounted) setLoading(false)
      })

    return () => { mounted = false }
  }, [params])

  if (loading && data.length === 0) {
    return <div className="loading">Chargement des certifications...</div>
  }

  if (error && data.length === 0) {
    return (
      <div className="empty">
        Erreur: {error}
        <button onClick={() => window.location.reload()} style={{ marginLeft: 16, padding: '8px 16px' }}>Réessayer</button>
      </div>
    )
  }

  const totalPages = Math.ceil(count / params.limit)
  const currentPage = params.page

  const getCertClass = (cert: string) => {
    const c = cert.toLowerCase()
    if (c.includes('diamant')) return 'cert-diamant'
    if (c.includes('triple')) return 'cert-triple-platine'
    if (c.includes('double')) return 'cert-double-platine'
    if (c.includes('platine')) return 'cert-platine'
    return 'cert-or'
  }

  const sortIcons: Record<string, string> = {}
  if (params.sortBy) {
    sortIcons[params.sortBy] = params.sortOrder === 'asc' ? ' ▲' : ' ▼'
  }

  const buildUrl = (newParams: Record<string, string>) => {
    const sp = new URLSearchParams()
    Object.entries(searchParams).forEach(([k, v]) => sp.set(k, v))
    Object.entries(newParams).forEach(([k, v]) => sp.set(k, v))
    return `?${sp.toString()}`
  }

  return (
    <>
      <div className="table-container">
        <table>
          <thead>
            <tr>
              <th onClick={() => window.location.href = buildUrl({ sortBy: 'titre', sortOrder: params.sortBy === 'titre' && params.sortOrder === 'asc' ? 'desc' : 'asc', page: '1' })}
                style={{cursor: 'pointer'}}>
                Titre {sortIcons.titre}
              </th>
              <th onClick={() => window.location.href = buildUrl({ sortBy: 'artiste', sortOrder: params.sortBy === 'artiste' && params.sortOrder === 'asc' ? 'desc' : 'asc', page: '1' })}
                style={{cursor: 'pointer'}}>
                Artiste {sortIcons.artiste}
              </th>
              <th onClick={() => window.location.href = buildUrl({ sortBy: 'certification', sortOrder: params.sortBy === 'certification' && params.sortOrder === 'asc' ? 'desc' : 'asc', page: '1' })}
                style={{cursor: 'pointer'}}>
                Certification {sortIcons.certification}
              </th>
              <th onClick={() => window.location.href = buildUrl({ sortBy: 'categorie', sortOrder: params.sortBy === 'categorie' && params.sortOrder === 'asc' ? 'desc' : 'asc', page: '1' })}
                style={{cursor: 'pointer'}}>
                Catégorie {sortIcons.categorie}
              </th>
              <th>Éditeur</th>
              <th onClick={() => window.location.href = buildUrl({ sortBy: 'date_constat', sortOrder: params.sortBy === 'date_constat' && params.sortOrder === 'asc' ? 'desc' : 'asc', page: '1' })}
                style={{cursor: 'pointer'}}>
                Date constat {sortIcons.date_constat}
              </th>
              <th onClick={() => window.location.href = buildUrl({ sortBy: 'date_sortie', sortOrder: params.sortBy === 'date_sortie' && params.sortOrder === 'asc' ? 'desc' : 'asc', page: '1' })}
                style={{cursor: 'pointer'}}>
                Date sortie {sortIcons.date_sortie}
              </th>
              <th>Durée</th>
            </tr>
          </thead>
          <tbody>
            {data.length === 0 ? (
              <tr>
                <td colSpan={9} className="empty">Aucune certification trouvée</td>
              </tr>
            ) : (
              data.map(cert => (
                <tr key={cert.id}>
                  <td className="cell-titre" title={cert.titre}>{cert.titre}</td>
                  <td className="cell-artiste" title={cert.artiste}>{cert.artiste}</td>
                  <td>
                    <span className={`cert-badge ${getCertClass(cert.certification)}`}>
                      {cert.certification}
                    </span>
                  </td>
                  <td>
                    {cert.categorie && (
                      <span className="cat-badge">{cert.categorie}</span>
                    )}
                  </td>
                  <td className="cell-editeur" title={cert.editeur || ''}>{cert.editeur || '—'}</td>
                  <td className="cell-date">{cert.date_constat || '—'}</td>
                  <td className="cell-date">{cert.date_sortie || '—'}</td>
                  <td className="cell-date">{cert.duree_obtention || '—'}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <nav className="pagination" aria-label="Pagination">
          <button
            onClick={() => window.location.href = buildUrl({ page: '1' })}
            disabled={currentPage === 1}
            aria-label="Première page"
          >
            ««
          </button>
          <button
            onClick={() => window.location.href = buildUrl({ page: (currentPage - 1).toString() })}
            disabled={currentPage === 1}
            aria-label="Page précédente"
          >
            «
          </button>

          <span className="pagination-info">
            Page {currentPage} / {totalPages} ({count.toLocaleString()} résultats)
          </span>

          <button
            onClick={() => window.location.href = buildUrl({ page: (currentPage + 1).toString() })}
            disabled={currentPage === totalPages}
            aria-label="Page suivante"
          >
            »
          </button>
          <button
            onClick={() => window.location.href = buildUrl({ page: totalPages.toString() })}
            disabled={currentPage === totalPages}
            aria-label="Dernière page"
          >
            »»
          </button>
        </nav>
      )}
    </>
  )
}