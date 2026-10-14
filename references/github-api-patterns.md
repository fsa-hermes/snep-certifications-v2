# GitHub API Patterns (via curl + PAT)

Used for repo creation, pushing, and automation.

## Authentication

```bash
Authorization: token <PAT>
# or
Authorization: Bearer <PAT>
```

## Create Repository

```bash
curl -X POST https://api.github.com/user/repos \
  -H "Authorization: token $PAT" \
  -H "Accept: application/vnd.github+json" \
  -d '{"name":"repo-name","description":"...","private":false,"has_issues":true,"has_wiki":false}'
```

Response includes: `full_name` ("owner/repo"), `clone_url`, `ssh_url`.

## Push with Token

```bash
git push https://$PAT@github.com/owner/repo.git main
```

**Note**: Token in URL works for HTTPS; SSH requires key setup.

## Common Endpoints

| Operation | Method | Endpoint |
|---|---|---|
| Create repo | POST | /user/repos |
| List repos | GET | /user/repos |
| Get repo | GET | /repos/{owner}/{repo} |
| Delete repo | DELETE | /repos/{owner}/{repo} (admin only) |
| Create issue | POST | /repos/{owner}/{repo}/issues |
| Create PR | POST | /repos/{owner}/{repo}/pulls |
| Get workflow runs | GET | /repos/{owner}/{repo}/actions/runs |

## PAT Scopes Needed

- `repo` (full control of private repos)
- `public_repo` (public repos only)
- `workflow` (GitHub Actions)
- `admin:repo_hook` (webhooks)

## Error Handling

- 401: Bad credentials / token expired
- 403: Insufficient scope / rate limited / private repo without access
- 422: Validation failed (e.g., repo name exists)

## Rate Limits

- 5000 req/hour for authenticated requests
- Check `X-RateLimit-Remaining` header

## Example: Full Repo Setup Flow

```bash
# 1. Create repo
RESPONSE=$(curl -s -X POST https://api.github.com/user/repos \
  -H "Authorization: token $PAT" \
  -d '{"name":"my-repo","private":false}')

# 2. Extract clone URL
CLONE_URL=$(echo $RESPONSE | jq -r .clone_url)
# Replace https:// with https://$PAT@ for authenticated push
AUTH_URL=${CLONE_URL/https:\/\//https:\/\/$PAT@}

# 3. Push
cd my-project
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin $AUTH_URL
git push -u origin main
```

## Delete Repository (requires admin)

```bash
curl -X DELETE https://api.github.com/repos/owner/repo \
  -H "Authorization: token $PAT"
```

**Note**: Token must have `delete_repo` scope or be owner with admin rights.