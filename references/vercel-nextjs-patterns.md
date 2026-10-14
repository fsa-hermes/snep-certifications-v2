# Vercel/Next.js 14 App Router Patterns

Learned from building the SNEP certifications UI.

## useSearchParams() in Server Components

**Problem**: `useSearchParams()` cannot be used in statically generated pages.

**Fix 1**: Force dynamic rendering
```tsx
export const dynamic = 'force-dynamic'
```

**Fix 2**: Wrap in Suspense boundary
```tsx
<Suspense fallback={<Loading />}>
  <ComponentUsingSearchParams />
</Suspense>
```

## TypeScript Set Spread

**Error**: `Type 'Set<any>' can only be iterated through when using the '--downlevelIteration' flag`

**Fix**: Add target to tsconfig.json
```json
{"compilerOptions": {"target": "ES2015", ...}}
```

## next.config.js Format

**Use CommonJS** (not ESM):
```js
/** @type {import('next').NextConfig} */
const nextConfig = { output: 'standalone' }
module.exports = nextConfig
```

## Path Aliases in App Router

`@/*` imports work in client components but **fail in server components** during static generation.

**Use relative imports** for shared libs:
```tsx
// Instead of: import { x } from '@/lib/supabase'
import { x } from '../lib/supabase'
```

## Git Ignore for Next.js

**Must exclude** to avoid GitHub 100MB file limit:
```
node_modules/
.next/
out/
build/
dist/
.env*.local
.env
.vercel
*.tsbuildinfo
```

**If already tracked**:
```bash
git rm -r --cached node_modules .next
git commit -m "Remove build artifacts from tracking"
```

## Vercel Deployment

### Temporary (no auth)
```bash
npx vercel deploy --temporary
```
- URL expires in ~60 minutes
- Claim: `vercel.com/claim-deployment?code=...`

### Permanent
```bash
npx vercel login
npx vercel --prod
```

### Environment Variables in Vercel Dashboard

Project Settings → Environment Variables:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_API_URL` (for Rust backend)

## Client-Side Data Fetching

Pattern for filterable/paginated tables:
```tsx
'use client'

useEffect(() => {
  fetch(`/api/data?${new URLSearchParams(params)}`)
    .then(r => r.json())
    .then(setData)
}, [params])

// URL sync
const updateUrl = () => {
  router.replace(`/?${new URLSearchParams(params).toString()}`, { scroll: false })
}
```

## Dark Theme CSS Variables

```css
:root {
  --bg: #0a0a0b;
  --bg-elevated: #141416;
  --border: #2a2a2e;
  --text: #fafafa;
  --text-muted: #a1a1aa;
  --accent: #eab308;  /* yellow/gold for Or */
  --accent-hover: #facc15;
}
```

## Certification Badge Colors

```css
.cert-or { background: rgba(234, 179, 8, 0.2); color: var(--accent); }
.cert-platine { background: rgba(163, 163, 163, 0.2); color: #a3a3a3; }
.cert-diamant { background: rgba(56, 189, 248, 0.2); color: #38bdf8; }
.cert-double-platine { background: rgba(163, 163, 163, 0.3); color: #d4d4d4; }
.cert-triple-platine { background: rgba(163, 163, 163, 0.4); color: #fff; }
```