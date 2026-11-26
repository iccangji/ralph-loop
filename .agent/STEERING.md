# Critical Steering Work

TASK-11 (Configure Production Build & Express BFF Server) — follow this exact pattern.

## Required Implementation Pattern

Based on PRD and existing integration worktree state:

### 1. Dependencies to add to package.json
```json
"dependencies": {
  "express": "^4.18.2",
  "http-proxy-middleware": "^3.0.0",
  ...
}
```
Add `start` script: `"start": "node server.js"`

### 2. server.js at project root (ES module, not CommonJS)
- Uses `import`/`export` syntax — project has `"type": "module"` in package.json
- Serves static files from `dist/`
- Proxies `/api/*` to `INTERFACES_URL` (default `http://kuponku-interfaces:3521`)
- Injects `Authorization: Bearer <INTERFACES_TOKEN>` header via `onProxyReq` option
- SPA fallback: `dist/index.html` for non-API routes
- Port from `process.env.PORT || 3020`

### 3. server.check.js — self-terminating verification script
```js
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const PORT = 3099; // isolated test port
const server = spawn('node', ['server.js'], { env: { ...process.env, PORT: String(PORT) }, stdio: ['ignore', 'pipe', 'pipe'] });

const waited = new Promise((resolve) => setTimeout(resolve, 1500));
await waited;

async function check(url, expectHtml = true) {
  const res = await fetch(`http://localhost:${PORT}${url}`);
  const text = await res.text();
  if (expectHtml && !text.includes('id="root"')) throw new Error(`${url}: missing SPA root div`);
  if (!expectHtml && text.includes('id="root"')) throw new Error(`${url}: got SPA fallback instead of API response`);
  return res.status;
}

try {
  await check('/');                    // serves index.html (SPA root)
  await check('/coupon/abc');          // SPA fallback works for client routes
  await check('/api/v1/mytelkomsel/catalog', false); // proxy path handled (not SPA fallback)
  console.log('✅ server.check.js passed');
} finally {
  server.kill();
}
```
Run with `node server.check.js`. Exits 0 on success, non-zero on failure.

### 4. vite.config.ts additions
```ts
build: {
  outDir: 'dist',
  sourcemap: false,
  minify: 'esbuild',
}
```
Keep `base: '/'` for static hosting.

### 5. .env.example (both VITE_* and server env)
```
VITE_API_BASE=/api
VITE_USE_MOCK=false
PORT=3020
INTERFACES_URL=http://kuponku-interfaces:3521
INTERFACES_TOKEN=your-token-here
```

### 6. Verification must pass
```bash
npm run build        # outputs to dist/
node server.check.js # deterministic, no sleep/pkill
```

## Common Failure Modes
- Missing `express` / `http-proxy-middleware` in deps
- `server.js` uses CommonJS `require` — must use ES module `import`
- Proxy not injecting Authorization header (`onProxyReq` missing)
- SPA fallback not working (404 on refresh) — fallback must be *after* static + proxy routes
- vite build not outputting to dist/
- .env.example missing server env vars
- Server crashes on start (syntax, missing import)

Follow this exactly. No creative variations.