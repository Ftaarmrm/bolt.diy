# Bolt.DIY Production-Safe Deployment for Coolify + Groq

## Summary of Changes

This refactor makes **Bolt.DIY production-safe for deployment on Coolify behind Traefik with Groq API**, addressing:

1. **Secret leakage via Docker build args** ✅ Fixed
2. **404 routing issues** ✅ Resolved via runtime host config
3. **SharedArrayBuffer/WebContainer isolation** ✅ Headers added
4. **Groq context window safety** ✅ Safe defaults (8192 tokens)
5. **COOLIFY_FQDN handling** ✅ Runtime-safe parsing

---

## Files Modified

### 1. **Dockerfile** (Production & Dev stages)
**Why:** Enforce secrets-only-at-runtime policy; never pass API keys as build args
- ❌ Removed all secret keys from `ARG` declarations
- ✅ Added critical comment documenting runtime-only secret requirements
- ✅ Increased default `DEFAULT_NUM_CTX` to 8192 (safe for Groq)
- ✅ Copy `docker-startup.sh` for safe diagnostics
- ✅ Added healthcheck for Coolify/deployment platforms
- ✅ Both production and development stages follow same secret policy

### 2. **docker-compose.yaml**
**Why:** Separate build args from secrets; add safe defaults; support Coolify override
- ❌ Changed `DEFAULT_NUM_CTX` default from 32768 → 8192
- ✅ Build args now only contain public config:
  - `VITE_LOG_LEVEL`
  - `DEFAULT_NUM_CTX`
- ✅ All secrets passed as `environment` variables (runtime, never build args):
  - `GROQ_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.
  - Default to empty `${VAR:-}` to prevent docker-compose errors
- ✅ Added `COOLIFY_FQDN` and `VITE_PUBLIC_APP_URL` for runtime host config
- ✅ Separate services: `app-prod`, `app-dev`, `app-prebuild`
- ✅ Healthcheck configured for Coolify

### 3. **docker-startup.sh** (New)
**Why:** Safe, secret-aware startup diagnostics for production
- ✅ Logs deployment config (host, port, context window) **without** secrets
- ✅ Parses `COOLIFY_FQDN` and `VITE_PUBLIC_APP_URL` to resolve allowed hosts
- ✅ Falls back to localhost if neither is set
- ✅ Check each provider key **presence only** (logs key length, never the value):
  ```
  ✓ Groq: configured (key length: 97 chars)
  ✗ OpenAI: not configured
  ```
- ✅ Logs cross-origin isolation header status
- ✅ Warns if context window > 16000 tokens (Groq rate limit risk)
- ✅ Executes bindings script + starts app with safe flags
- ✅ Respects `DEFAULT_NUM_CTX` runtime config

### 4. **app/entry.server.tsx**
**Why:** Add complete cross-origin isolation headers for WebContainer support
- ✅ Added `Cross-Origin-Resource-Policy: cross-origin` header (was missing)
- ✅ Full trio now present:
  - `Cross-Origin-Embedder-Policy: require-corp`
  - `Cross-Origin-Opener-Policy: same-origin`
  - `Cross-Origin-Resource-Policy: cross-origin`
- ✅ Resolves SharedArrayBuffer errors in browser

### 5. **app/root.tsx**
**Why:** Match server headers at the Remix route level
- ✅ Updated `headers()` export to include all three isolation headers
- ✅ Ensures consistency across SSR and client

### 6. **vite.config.ts**
**Why:** Dev server must also set cross-origin headers
- ✅ Added full trio of headers to Vite dev server config
- ✅ `server.headers` now includes `Cross-Origin-Resource-Policy`
- ✅ Local development will use same headers as production

---

## Configuration & Deployment

### Runtime Environment Variables (SET IN COOLIFY)

#### Required for Groq:
```
GROQ_API_KEY=sk_live_...  # Only pass at runtime, NEVER as build arg
```

#### Optional for other providers:
```
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OPEN_ROUTER_API_KEY=sk-or-...
GOOGLE_GENERATIVE_AI_API_KEY=...
XAI_API_KEY=...
TOGETHER_API_KEY=...
DEEPSEEK_API_KEY=...
MISTRAL_API_KEY=...
PERPLEXITY_API_KEY=...
HuggingFace_API_KEY=...
```

#### Deployment config:
```
COOLIFY_FQDN=my-app.example.com          # For host validation
VITE_PUBLIC_APP_URL=https://my-app.example.com  # Public URL
DEFAULT_NUM_CTX=8192                     # Context window (safe default)
NODE_ENV=production
```

#### Optional custom provider URLs:
```
OLLAMA_API_BASE_URL=http://127.0.0.1:11434
OPENAI_LIKE_API_BASE_URL=...
OPENAI_LIKE_API_KEY=...
OPENAI_LIKE_API_MODELS=...
TOGETHER_API_BASE_URL=...
LMSTUDIO_API_BASE_URL=...
AWS_BEDROCK_CONFIG={"region":"us-east-1",...}
```

### Build Arguments (REMOVE from Coolify)

❌ **Remove these from Coolify "Build Args" section:**
- `GROQ_API_KEY`
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `OPEN_ROUTER_API_KEY`
- `GOOGLE_GENERATIVE_AI_API_KEY`
- `XAI_API_KEY`
- `TOGETHER_API_KEY`
- `DEEPSEEK_API_KEY`
- `MISTRAL_API_KEY`
- `PERPLEXITY_API_KEY`
- `HuggingFace_API_KEY`
- `AWS_BEDROCK_CONFIG`
- Any other API key or secret

✅ **Keep in Build Args (if needed):**
- `VITE_LOG_LEVEL=debug`
- `DEFAULT_NUM_CTX=8192`

---

## Verification Checklist

### Before deployment:
- [ ] Confirm Coolify "Build Arguments" section is **empty** (no secrets)
- [ ] Confirm Coolify "Environment Variables" contains all secrets
- [ ] Set `COOLIFY_FQDN` or `VITE_PUBLIC_APP_URL` in environment

### After deployment:
- [ ] App opens without 404 errors
- [ ] Docker build logs show **no API keys** (grep for `sk-`, `sk_live`, etc.)
- [ ] App startup logs show safe diagnostics:
  ```
  ✓ Groq: configured (key length: 97 chars)
  ✓ Cross-Origin Isolation: enabled
  ✓ WebContainer/SharedArrayBuffer support enabled
  ```
- [ ] Groq API calls work (app responds to LLM prompts)
- [ ] Browser console shows **no** `SharedArrayBuffer transfer requires self.crossOriginIsolated` errors
- [ ] WebContainer terminal works (if used)

---

## Why These Changes

### A) Secrets as Runtime-Only
**Problem:** If API keys are Docker `ARG` values, they appear in:
- Build logs (viewable by anyone with build history access)
- Image layers (readable via Docker inspection)
- Environment during build (leaked to intermediate images)

**Solution:** Pass secrets only as runtime environment variables:
- Not visible in image history
- Injected by orchestrator (Coolify) at startup
- Never touched during build

### B) COOLIFY_FQDN Support
**Problem:** App routing breaks when deployed behind reverse proxy with different domain
**Solution:** 
- Parse `COOLIFY_FQDN` at startup in `docker-startup.sh`
- Set `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS` for Wrangler
- Falls back to localhost if not set

### C) Cross-Origin Isolation
**Problem:** WebContainers / SharedArrayBuffer requires:
```
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: cross-origin
```
Missing headers cause:
- SharedArrayBuffer disabled
- WebContainer terminal fails
- Worker threads fail

**Solution:** Add headers in 3 places:
1. Remix server (`app/entry.server.tsx`)
2. Remix route (`app/root.tsx`)
3. Vite dev server (`vite.config.ts`)

### D) Groq Safe Defaults
**Problem:** Large context windows (32768) hit Groq rate limits quickly
**Solution:** Default to 8192 tokens, override with `DEFAULT_NUM_CTX` env var

---

## Local Development

### Start dev container:
```bash
docker-compose -f docker-compose.yaml -p bolt up app-dev
```

### Set secrets locally (.env.local):
```
GROQ_API_KEY=sk_live_...
NODE_ENV=development
```

### Build & run production locally:
```bash
docker-compose -f docker-compose.yaml -p bolt up app-prod
```

---

## Deployment Flow (Coolify)

1. **User configures Coolify:**
   - Repository: `Ftaarmrm/bolt.diy`
   - Dockerfile: `Dockerfile`
   - Build context: `.`
   - Build args: **(empty or only public values)**
   - Environment: All secrets + deployment config

2. **Coolify builds:**
   - Dockerfile stages executed (no secrets in ARG)
   - `docker-startup.sh` copied into image

3. **Coolify runs container:**
   - Environment variables injected at runtime
   - `docker-startup.sh` executes, logs safe diagnostics
   - App starts with `pnpm run start:unix`
   - Listens on `0.0.0.0:5173`

4. **Traefik reverse proxy:**
   - Routes requests to container port 5173
   - Sets `Host` header to actual domain
   - `docker-startup.sh` uses `COOLIFY_FQDN` to validate

---

## Troubleshooting

### "404 in browser"
→ Check `COOLIFY_FQDN` or `VITE_PUBLIC_APP_URL` is set  
→ Verify `docker-startup.sh` logs show resolved hosts

### "SharedArrayBuffer not available"
→ Check response headers: `Cross-Origin-Embedder-Policy: require-corp`  
→ If missing, ensure `app/entry.server.tsx` has all 3 headers

### "Groq requests slow / rate limited"
→ Check logs for `DEFAULT_NUM_CTX` value  
→ If > 16000, reduce via `DEFAULT_NUM_CTX=8192` environment var

### "API key appeared in build logs"
→ Check Coolify "Build Arguments" — remove any secrets  
→ Move to "Environment Variables"

---

## Future Improvements

- [ ] Add `.env.coolify` example file with template
- [ ] Document Coolify GUI steps (screenshots)
- [ ] Add GitHub Actions workflow for safe docker build
- [ ] Add secret scanning to prevent accidental commits
- [ ] Support encrypted environment variables in Coolify

