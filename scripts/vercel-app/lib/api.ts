const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080'

export interface Certification {
  id: string
  created_at: string
  categorie: string | null
  titre: string
  artiste: string
  editeur: string | null
  certification: string
  date_sortie: string | null
  date_constat: string | null
  duree_obtention: string | null
  source_url: string | null
  dedup_key: string
}

export interface CertificationsResponse {
  data: Certification[]
  count: number
  error: string | null
  page: number
  limit: number
  totalPages: number
}

export interface StatsResponse {
  total: number
  byCert: Record<string, number>
  byCat: Record<string, number>
}

export interface FiltersResponse {
  certifications: string[]
  categories: string[]
  artistes: string[]
}

export interface HistoryEntry {
  id: string
  certification_id: string
  field: string
  old_value: string | null
  new_value: string | null
  changed_at: string
  changed_by: string | null
}

async function fetchApi<T>(endpoint: string, params?: Record<string, string | number | undefined>): Promise<T> {
  const url = new URL(`${API_BASE_URL}${endpoint}`)
  
  if (params) {
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== '') {
        url.searchParams.append(key, String(value))
      }
    })
  }

  const response = await fetch(url.toString(), {
    headers: {
      'Content-Type': 'application/json',
    },
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ message: 'Unknown error' }))
    throw new Error(error.message || `HTTP ${response.status}`)
  }

  return response.json()
}

// Fetch certifications with filters
export async function fetchCertifications(params: {
  page?: number
  limit?: number
  search?: string
  certification?: string
  categorie?: string
  artiste?: string
  dateFrom?: string
  dateTo?: string
  sortBy?: string
  sortOrder?: 'asc' | 'desc'
}): Promise<CertificationsResponse> {
  const {
    page = 1,
    limit = 50,
    search,
    certification,
    categorie,
    artiste,
    dateFrom,
    dateTo,
    sortBy = 'date_constat',
    sortOrder = 'desc',
  } = params

  return fetchApi<CertificationsResponse>('/api/certifications', {
    page,
    limit,
    search,
    certification,
    categorie,
    artiste,
    dateFrom,
    dateTo,
    sortBy,
    sortOrder,
  })
}

// Get distinct values for filters
export async function getFilterOptions(): Promise<FiltersResponse> {
  return fetchApi<FiltersResponse>('/api/filters')
}

// Get stats
export async function getStats(): Promise<StatsResponse> {
  return fetchApi<StatsResponse>('/api/stats')
}

// Get certification history
export async function getCertificationHistory(id: string): Promise<HistoryEntry[]> {
  return fetchApi<HistoryEntry[]>(`/api/certifications/${id}/history`)
}