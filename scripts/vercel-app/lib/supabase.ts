import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const supabase = createClient(supabaseUrl, supabaseAnonKey)

// Types matching enhanced schema
export interface Artist {
  id: string
  name: string
  slug: string
  normalized_name: string
  created_at: string
}

export interface Label {
  id: string
  name: string
  slug: string
  normalized_name: string
  parent_label_id: string | null
  created_at: string
}

export interface CertificationArtist {
  certification_id: string
  artist_id: string
  role: 'primary' | 'featured' | 'with' | 'remixer' | 'producer' | 'original'
  position: number
  artist: Artist
}

export interface CertificationHistory {
  id: string
  certification_id: string
  old_level: 'Argent' | 'Or' | 'Platine' | 'Diamant' | null
  new_level: 'Argent' | 'Or' | 'Platine' | 'Diamant'
  changed_at: string
  source: string
  is_current: boolean
}

export interface Certification {
  id: string
  created_at: string
  updated_at: string
  categorie: string | null
  titre: string
  editeur: string | null
  certification: 'Argent' | 'Or' | 'Platine' | 'Diamant'
  date_sortie: string | null
  date_constat: string | null
  duree_obtention: string | null
  source_url: string | null
  dedup_key: string
  label: Label | null
  artists: CertificationArtist[]
  history: CertificationHistory[]
  current_level: string
  highest_level: string
}

export interface CertificationsResponse {
  data: Certification[]
  count: number
  error: string | null
}

export interface StatsResponse {
  total: number
  byCert: Record<string, number>
  byCat: Record<string, number>
  byArtist: Record<string, number>
}

export interface FiltersResponse {
  certifications: string[]
  categories: string[]
  artists: string[]
  labels: string[]
}

// Fetch certifications with filters using the search_certifications function
export async function fetchCertifications(params: {
  page?: number
  limit?: number
  search?: string
  certification?: string
  categorie?: string
  artiste?: string
  label?: string
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
    label,
    dateFrom,
    dateTo,
    sortBy = 'date_constat',
    sortOrder = 'desc',
  } = params

  const from = (page - 1) * limit
  const to = from + limit - 1

  // Use the search_certifications RPC function if search provided, otherwise query certifications_with_history view
  if (search) {
    const { data, error } = await supabase
      .rpc('search_certifications', {
        search_query: search,
        cert_level: certification || null,
        cat: categorie || null,
        art_name: artiste || null,
        lbl_name: label || null,
        date_from: dateFrom || null,
        date_to: dateTo || null,
        sort_by: sortBy,
        sort_desc: sortOrder === 'desc',
        page_limit: limit,
        page_offset: from,
      })

    if (error) return { data: [], count: 0, error: error.message }

    // Get total count for pagination
    const { count } = await supabase
      .rpc('search_certifications', {
        search_query: search,
        cert_level: certification || null,
        cat: categorie || null,
        art_name: artiste || null,
        lbl_name: label || null,
        date_from: dateFrom || null,
        date_to: dateTo || null,
        sort_by: sortBy,
        sort_desc: sortOrder === 'desc',
        page_limit: 1,
        page_offset: 0,
      })

    return { data: data || [], count: count || 0, error: null }
  }

  // Query certifications_with_history view directly
  let query = supabase
    .from('certifications_with_history')
    .select('*', { count: 'exact' })

  if (certification) query = query.eq('certification', certification)
  if (categorie) query = query.eq('categorie', categorie)
  if (artiste) query = query.ilike('artists', `%${artiste}%`)
  if (label) query = query.ilike('label->>name', `%${label}%`)
  if (dateFrom) query = query.gte('date_constat', dateFrom)
  if (dateTo) query = query.lte('date_constat', dateTo)

  const validSortColumns = ['date_constat', 'date_sortie', 'titre', 'categorie', 'certification', 'created_at', 'highest_level']
  const sortColumn = validSortColumns.includes(sortBy) ? sortBy : 'date_constat'
  query = query.order(sortColumn, { ascending: sortOrder === 'asc' })

  query = query.range(from, to)

  const { data, error, count } = await query

  if (error) return { data: [], count: 0, error: error.message }

  return { data: data || [], count: count || 0, error: null }
}

// Get stats
export async function getStats(): Promise<StatsResponse> {
  const { data, error } = await supabase
    .from('certifications_with_history')
    .select('certification, categorie, artists')

  if (error || !data) return { total: 0, byCert: {}, byCat: {}, byArtist: {} }

  const byCert: Record<string, number> = {}
  const byCat: Record<string, number> = {}
  const byArtist: Record<string, number> = {}

  data.forEach(r => {
    byCert[r.certification] = (byCert[r.certification] || 0) + 1
    if (r.categorie) byCat[r.categorie] = (byCat[r.categorie] || 0) + 1
    if (r.artists) {
      r.artists.forEach((a: any) => {
        byArtist[a.artist.name] = (byArtist[a.artist.name] || 0) + 1
      })
    }
  })

  return { total: data.length, byCert, byCat, byArtist }
}

// Get filter options
export async function getFilterOptions(): Promise<FiltersResponse> {
  const [certs, cats, artists, labels] = await Promise.all([
    supabase.from('certifications_with_history').select('certification'),
    supabase.from('certifications_with_history').select('categorie'),
    supabase.from('artists').select('name').order('name').limit(500),
    supabase.from('labels').select('name').order('name').limit(200),
  ])

  return {
    certifications: [...new Set(certs.data?.map(r => r.certification).filter(Boolean) || [])],
    categories: [...new Set(cats.data?.map(r => r.categorie).filter(Boolean) || [])],
    artists: artists.data?.map(r => r.name) || [],
    labels: labels.data?.map(r => r.name) || [],
  }
}

// Get single certification with full relations
export async function getCertification(id: string) {
  const { data, error } = await supabase
    .from('certifications_with_history')
    .select('*')
    .eq('id', id)
    .single()

  return { data, error }
}

// Get certification history
export async function getCertificationHistory(certificationId: string) {
  const { data, error } = await supabase
    .from('certification_history')
    .select('*')
    .eq('certification_id', certificationId)
    .order('changed_at', { ascending: true })

  return { data: data || [], error }
}