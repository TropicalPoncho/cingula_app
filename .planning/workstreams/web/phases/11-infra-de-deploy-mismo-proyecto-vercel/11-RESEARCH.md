# Phase 11: Infra de deploy (mismo proyecto Vercel) - Research

**Researched:** 2026-09-25
**Domain:** Vercel monorepo routing (Root Directory / `vercel.json` `functions` discovery), Neon↔Vercel Preview branching
**Confidence:** MEDIUM-HIGH (platform docs fetched directly 2026-08/09; some claims cross-verified with a GitHub maintainer discussion; no live spike run yet — that is this phase's own Success Criterion 1)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None locked — the user delegated all 4 discussed areas to research/planning discretion (see below). The phase boundary itself is locked (from ROADMAP, restated in CONTEXT.md `<domain>`):
- La web y el backend se sirven desde el mismo proyecto Vercel.
- `/sync/*` sigue llegando a las funciones sin cambios de comportamiento (celular real sincroniza contra producción hoy).
- Un deploy Preview usa una rama de Neon dev, nunca la `DATABASE_URL` de producción.
- `web/` queda libre de restos de Flutter web para alojar la SPA de la Fase 12.
- Fuera de esta fase: la SPA en sí (Fase 12), pantalla de acceso/AUTH-02 (Fase 12), storage de audio (Fase 13), cualquier escritura desde la web.

### Claude's Discretion
- **Riesgo del cutover a producción:** no hace falta ventana especial ni rollback formal más allá de lo que el ROADMAP ya exige (smoke test de `GET /sync/state` en Preview + confirmar push real del celular, ambos antes de mergear a `main`). Si el smoke test pasa, aplicar; si no, no mergear. No coordinar con "sin grabación de campo en curso" (RNF-03 tolera intermitencia, outbox reintenta).
- **Rama Neon dev:** verificar primero si ya existe (Neon console / `vercel env ls` / integración); si no existe, esta fase la crea (INFRA-02). Sin preferencia de nombre.
- **Mecanismo de ruteo:** sin preferencia previa entre shims de re-export, `functions` glob, o mover `backend/api/` a la raíz — el spike de `vercel dev` decide objetivamente. Preferir el que mueva menos archivos si dos opciones empatan en viabilidad (ADR-005: no reestructurar `backend/` sin necesidad).
- **Limpieza de `web/`:** borrado total de los restos de Flutter web, sin conservar nada.

### Deferred Ideas (OUT OF SCOPE)
None — la discusión se mantuvo dentro del alcance de la fase.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | La web y el backend se sirven desde el mismo proyecto Vercel; `/sync/*` sigue llegando a las funciones sin cambios de comportamiento | See "Routing Mechanisms" — **mechanism (b) is a dead end per official docs** (see below); only (a) shims and (c) move-to-root are actually viable, which narrows the spike Success Criterion 1 must run |
| INFRA-02 | Deploys Preview usan una rama de Neon dev, nunca `DATABASE_URL` de Production (verificado) | See "Neon↔Vercel Preview Branching" — a native integration exists that does this automatically per-branch; verification method given (cannot rely on docs claim alone per ADR-005 risk) |
| INFRA-03 | Restos de Flutter web eliminados, `web/` lista para la SPA | Trivial file deletion — see "web/ Cleanup", no library needed |
</phase_requirements>

## Summary

This phase is a **platform-configuration** problem, not an application-code problem — no new library, no new runtime. The three routing mechanisms named in CONTEXT.md are **not equally viable**: official Vercel docs and a maintainer response on GitHub confirm that Vercel Functions are **only auto-discovered from a literal `api/` directory located at the Vercel project's Root Directory** (or `pages/api`/`app/api` under a detected framework). The `functions` property in `vercel.json` **cannot point function discovery at an arbitrary directory** (e.g. `backend/api/**`) — it can only customize (`runtime`, `memory`, `maxDuration`, `regions`, `includeFiles`) functions that were already discovered by the `api/` convention. This means **mechanism (b), "functions glob pointing at `backend/api/**` from a root Root Directory," does not work as described and should be ruled out before the spike**, not discovered as a spike failure — the spike (Success Criterion 1) should test only (a) shims-at-root and (c) move-to-root, plus a variant discovered during this research: (d) Root Directory = `web/` with shim files at `web/api/*.js`.

A second load-bearing discovery not in the original open questions: **this repo's root directory is the Flutter app itself** (`lib/`, `android/`, `ios/`, `pubspec.yaml`, etc. all live at repo root alongside `backend/` and `web/`). Changing the Vercel project's Root Directory to the repo root — required by mechanisms (a) and (c) — pulls the *entire* Flutter source tree into the Vercel project's scope unless explicitly excluded. This needs a `.vercelignore` (or equivalent ignore config) regardless of which mechanism wins, and is a concrete risk to flag in the plan, not just the spike.

For Neon Preview isolation (INFRA-02), Neon's **native Vercel integration** (Storage tab → Connect → Neon, "Create a database branch for deployment" → Preview) creates a Neon branch **per preview deployment automatically** and injects `DATABASE_URL` (plus `DATABASE_URL_UNPOOLED`, `PGHOST`, etc.) scoped to that environment only — existing code (`getSql()` reading `process.env.DATABASE_URL`) needs zero changes if this integration is used instead of manually running `vercel env add DATABASE_URL preview <branch>`. This is very likely the fastest path to satisfy INFRA-02, but the phase's own success criterion (3) demands verifying the actual injected value on a real Preview deploy, not trusting Neon's docs — this matches the ADR-005 risk already flagged in PROJECT.md and CONTEXT.md.

**Primary recommendation:** Run the spike against only 2-3 real candidates (shims-at-repo-root, move-to-root, and optionally shims-at-`web/`), each requiring a `.vercelignore` for the Flutter tree; enable Neon's native Vercel Preview-branch integration for INFRA-02 instead of hand-rolling `vercel env add`; verify the live Preview `DATABASE_URL` value with `vercel env pull --environment=preview` (not by reading dashboard-masked values or trusting integration docs).

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Vercel CLI | 60.1.3 (current on npm registry as of 2026-09-25) | `vercel dev`, `vercel link`, `vercel env`, running the spike | Not currently installed on this machine — install via `npm i -g vercel@latest` or use `npx vercel@latest` for the spike, no need to add as a project dependency |
| Neon "Neon for Vercel" native integration (Vercel Marketplace) | current (2026) | Auto-create/attach a Neon branch per Preview deployment, inject scoped env vars | Already the project's chosen backend (ADR-001); this is the first-party glue between Neon and Vercel Preview environments — confirmed to exist and do exactly what INFRA-02 needs |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `.vercelignore` | n/a (plain ignore-file syntax, same as `.gitignore`) | Exclude `lib/`, `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `assets/`, `test/`, `pubspec.*` from the Vercel project once Root Directory becomes the repo root | Needed regardless of which routing mechanism wins, the moment Root Directory stops being `backend/` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Neon native Vercel integration (branch-per-preview) | Manual `vercel env add DATABASE_URL preview <branch-name>` pointing at one pre-created Neon dev branch | Manual is simpler to reason about (one static dev branch, matches CONTEXT.md's "verificar primero si ya existe una... si no existe, esta fase la crea" wording) but does NOT give per-PR isolation and requires remembering to keep pointing at a non-prod branch forever; the native integration does this automatically and is the standard/recommended approach per Neon's own docs — recommend using the integration unless it's already been rejected for cost/complexity reasons (it is free-tier compatible, same Neon project/branches already in use) |

**Installation:**
```bash
npm install -g vercel@latest    # or: npx vercel@latest <command>
```

**Version verification:** confirmed via `npm view vercel version` → `60.1.3` (2026-09-25). Vercel CLI ≥20.1.0 required for `vercel link --repo`/monorepo linking; ≥21.0.1 required for branch-specific Preview env vars via CLI (`vercel env add VAR preview <git-branch>`) — both comfortably satisfied by current CLI.

## Architecture Patterns

### Recommended Project Structure (repo layout, unaffected by this phase's mechanism choice)
```
/ (repo root — currently the Flutter app's own root: lib/, android/, ios/, pubspec.yaml, etc.)
├── backend/            # self-contained Node/Vercel-functions workstream (ADR-005 unit)
│   ├── api/
│   │   ├── _lib/       # auth.js, db.js, spec.js, etc. — shared helpers, NOT functions (underscore-prefixed dirs are never auto-turned into functions)
│   │   └── sync/        # push.js, pull.js, state.js — the 3 existing functions
│   ├── package.json
│   └── vercel.json      # today: { rewrites: [/sync/:path* -> /api/sync/:path*] }, implies Root Directory = backend/
├── web/                 # today: Flutter-web leftovers (to be deleted, INFRA-03); after Phase 12: the SPA
├── lib/, android/, ios/, ... # Flutter app source — NOT part of the Vercel project's concern, must be excluded once Root Directory changes
```

### Vercel Function Discovery Rule (HIGH confidence — official docs, cross-verified with GitHub maintainer response)
**What:** Vercel auto-detects serverless functions **only** from a literal `api/` directory located at the project's **Root Directory** (or framework-specific conventions like Next.js `pages/api`/`app/api`). The `functions` property in `vercel.json` is a glob **over already-discovered function files** used to set `runtime`, `memory`, `maxDuration`, `regions`, `includeFiles`/`excludeFiles` — it is NOT a mechanism to point function discovery at an arbitrary directory outside the conventional `api/` location.
**Source:** [Static Configuration with vercel.json — `functions`](https://vercel.com/docs/project-configuration/vercel-json#functions) ("the only requirement is to create an `api` directory at the root of your project directory, placing your Vercel functions inside"); confirmed by a Vercel team member in [vercel/vercel#7591](https://github.com/vercel/vercel/discussions/7591): "there is not currently a way to configure a custom directory for serverless functions outside of `/api`... you would still need to put the serverless functions in `/pages/api` or `/api`."
**Implication for this phase:** Mechanism (b) as literally described in CONTEXT.md/ROADMAP ("`functions` glob pointing at `backend/api/**` from a root Root Directory") **cannot work** — there is no `api/` directory at the repo root for it to match against, and the `functions` property can't invent one. Rule this out analytically; don't burn spike time on it. The real candidates for Success Criterion 1's spike are:
- **(a) Shims at repo root:** create `api/sync/push.js`, `api/sync/pull.js`, `api/sync/state.js` at the repo root, each a one-line re-export (`export { default } from '../../backend/api/sync/push.js'` or equivalent), with Root Directory = repo root. Root Directory's "Include source files outside of the Root Directory in the Build Step" is enabled by default for projects created after 2020-08-27 (this project is newer), so the shim can require/import `backend/api/_lib/*` without extra config. Moves the fewest files (ADR-005-aligned) but adds a layer of indirection files that must be kept in sync if a 4th function is ever added.
- **(c) Move `backend/api/` (and `_lib/`) to repo-root `/api/`:** zero indirection, matches the framework's actual convention exactly, but is a bigger diff and means `backend/` is no longer self-contained (contradicts the "backend/ es una unidad autocontenida" pattern noted in CONTEXT.md `<code_context>`) — `backend/package.json`, `backend/.env.example`, and `backend/README.md`'s `cd backend && vercel dev` instructions would all need to move or be rewritten.
- **(d) Not named in CONTEXT.md, found during this research — Root Directory = `web/` with shims at `web/api/*.js`:** since Root Directory just needs an `api/` directory as a direct child, pointing Root Directory at `web/` (the folder that already needs to become the SPA's home in Phase 12) instead of the repo root means the Flutter tree is *not* implicitly included at all (Root Directory itself scopes the project; "include files outside Root Directory" only traces files actually `require`d/`import`ed, it does not pull in the whole repo). This avoids the `.vercelignore`-for-Flutter problem entirely. Tradeoff: puts backend shim files inside `web/`, which CONTEXT.md says should be "queda libre" for the SPA — likely still fine since it's shim glue, not app code, but worth the spike explicitly testing this as a candidate since it sidesteps the biggest new risk found in this research.

### Root Directory Change Also Changes the Install/Build Scope (MEDIUM confidence — inferred from Vercel monorepo docs + repo layout observed directly)
**What:** This repo's root is the Flutter app's own root (`pubspec.yaml`, `lib/`, `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `assets/`, `test/` all live there). There is **no root `package.json`** today. If Root Directory moves from `backend/` to the repo root (mechanisms a/c), Vercel's install/build step now operates over a directory containing an entire unrelated Flutter/Dart project.
**When it matters:** Any of the spike's routing mechanisms that change Root Directory to the repo root.
**Mitigation:** Add a `.vercelignore` (same glob syntax as `.gitignore`) excluding at minimum `lib/`, `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `assets/`, `test/`, `pubspec.yaml`, `pubspec.lock`, `*.iml`; add a root `package.json` (or reuse/relocate `backend/package.json` to root) so `npm install` has something to install against; verify `backend/.gitignore`'s `.vercel/` entry gets mirrored at repo root too (today only `backend/.gitignore` ignores `.vercel/` — a new root-level `.vercel/` folder from `vercel link` would otherwise get committed by accident).
**Not needed if:** mechanism (d) is chosen (Root Directory = `web/`), since Root Directory itself already excludes the Flutter tree without an ignore file.

### Anti-Patterns to Avoid
- **Don't use `builds` (legacy) alongside `functions`:** the two are mutually exclusive in `vercel.json`; the existing `backend/vercel.json` only uses `rewrites`, so this isn't a live risk, but don't reach for `builds` while iterating on the spike.
- **Don't assume the Neon integration's Preview env var injection is visible in the dashboard's Environment Variables settings:** per Neon's own docs, Preview-deployment env vars from the native integration are injected via webhook at deployment time and are *not* listed in the project's static Environment Variables page — inspect them with `vercel env pull --environment=preview` or by having the deployed function log/return which host it connected to, not by eyeballing the dashboard.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-Preview isolated Postgres branch + env var wiring | A custom GitHub Action or Vercel deploy hook that calls the Neon API to create/destroy a branch per PR and calls `vercel env add` | Neon's native "Neon for Vercel" Marketplace integration (Storage tab → Connect) | It's a first-party integration built for exactly this; battle-tested webhook-based branch lifecycle (create on preview deploy, presumably reusable/cleaned up per Neon's own retention rules), free-tier compatible, zero code |
| Verifying "Preview never touches Production DATABASE_URL" | Trusting documentation or a one-time manual check that's never repeated | An automated check as part of the smoke test in Success Criterion 2 (e.g., have `GET /sync/state` return which Neon branch/host it's connected to, or diff `vercel env pull --environment=preview` output against `--environment=production` before merging) | ADR-005 already flags this as "sin verificar todavía" — a repeatable, scriptable check belongs in the plan's verification step, not a one-off manual glance |

**Key insight:** everything in this phase is Vercel/Neon platform configuration. There is no code to write for INFRA-01/02 beyond thin shim files (if mechanism a/d wins) and a `.vercelignore`; resist the temptation to build tooling around this — it's a config change plus a manual dashboard click (Neon integration) plus a verification script.

## Common Pitfalls

### Pitfall 1: Assuming `functions` glob can point at `backend/api/**`
**What goes wrong:** Spending spike time trying `"functions": { "backend/api/**/*.js": {...} }` from a root-level `vercel.json` and getting silent 404s on `/sync/*` in Preview.
**Why it happens:** The `functions` property looks like a generic "point at these files" config, but it only configures functions already found via the `api/` convention — it can't discover functions elsewhere.
**How to avoid:** Rule this mechanism out before the spike (this research already does); only test (a), (c), (d).
**Warning signs:** `vercel dev` output shows 0 functions detected, or deployed Preview returns HTML (SPA fallback / 404 page) instead of JSON for `GET /sync/state` — this is exactly the failure mode Success Criterion 2 is designed to catch.

### Pitfall 2: Root Directory change silently drags in the Flutter app
**What goes wrong:** Vercel build step becomes slow, upload size balloons, or `npm install`/build command fails because it's now running in a directory that also contains `pubspec.yaml`/`android/`/`ios/`/etc. with no relevant Node tooling.
**Why it happens:** This repo mixes a Flutter app and a Node/Vercel backend at the same repo root — not visible from `backend/vercel.json` alone, only from looking at the actual repo tree.
**How to avoid:** Add `.vercelignore` (mechanisms a/c) or use Root Directory = `web/` (mechanism d) which avoids the problem structurally.
**Warning signs:** `vercel dev`/`vercel build` output mentions scanning/uploading unrelated files (`.dart`, `android/`, `ios/`); build time much longer than the previous `backend/`-scoped deploys.

### Pitfall 3: Trusting "the rewrite still says `/sync/:path* -> /api/sync/:path*`" without re-checking after Root Directory changes
**What goes wrong:** The existing rewrite in `backend/vercel.json` assumes `/api/sync/*` resolves relative to Root Directory = `backend/`. If Root Directory moves and/or the `vercel.json` itself moves (it must live at the *new* Root Directory, or at repo root if using per-directory `vercel.json` in newer monorepo configs), the same rewrite text might now point at a path that doesn't exist, breaking `/sync/*` silently (filesystem takes precedence over rewrites per the docs — "The `source` property should NOT be a file because precedence is given to the filesystem prior to rewrites being applied").
**Why it happens:** `vercel.json`'s `rewrites` config is one file per project (with the new Root Directory potentially being a *different* directory than where `backend/vercel.json` sits today) — the file needs to move or be recreated at the new location, not just left in place.
**How to avoid:** Whichever mechanism wins, explicitly re-verify the final `vercel.json` location matches the final Root Directory, and re-test the rewrite with the spike's own `vercel dev` run (this is literally what Success Criterion 1 asks for).
**Warning signs:** `/sync/state` returns a 404 or the SPA's `index.html` (rewritten by a catch-all SPA rewrite) instead of JSON.

## Runtime State Inventory

> Included because this phase moves/restructures deploy configuration and deletes files (`web/index.html`, `manifest.json`, `icons/`, `favicon.png`), which touches "OS/platform-registered state" (the live Vercel project's Root Directory setting) even though it's not a data-migration phase in the traditional sense.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — this phase does not touch Postgres data, only which `DATABASE_URL` a deploy connects to. | None |
| Live service config | **The Vercel project's Root Directory setting** currently = `backend/` (inferred from `backend/vercel.json` + `backend/README.md`'s `cd backend && vercel dev` / `vercel link` instructions) — this lives in the Vercel dashboard/project settings, NOT in git. Changing routing mechanism requires an explicit Root Directory change in Vercel project settings (or via `vercel.json` `outputDirectory`/build settings if using newer config-as-code). Also: **whether the Neon↔Vercel native integration is already connected** to this project is unknown — must check the Vercel dashboard's Storage tab before assuming it needs to be set up from scratch. | Manual: change Root Directory in Vercel dashboard (or `vercel.json` if using programmatic config) to match chosen mechanism; manual: check/enable Neon integration's Preview branch option in Storage tab |
| OS-registered state | None found — no Task Scheduler/pm2/launchd/systemd artifacts relevant to a Vercel-hosted deploy. | None |
| Secrets/env vars | `SYNC_API_KEY`, `WEB_API_KEY`, `DATABASE_URL` already exist as Vercel project env vars (Production scope, per Phase 2/10 work) — this phase does not rename any of them; it either lets the Neon integration inject a Preview-scoped `DATABASE_URL` override, or manually adds one via `vercel env add DATABASE_URL preview <branch>`. No key renames, only scope additions. | Code edit: none. Config: add Preview-scoped env var or enable Neon integration. |
| Build artifacts | `backend/.vercel/` (gitignored) may exist locally on whichever machine last ran `vercel link` — not found in this worktree (`no backend/.vercel`), so nothing stale to clean here, but a NEW `.vercel/` directory will appear at whatever the new Root Directory is once `vercel link`/`vercel dev` runs there; root `.gitignore` does not yet have a `.vercel/` entry (only `backend/.gitignore` does) — must add one at the new location to avoid accidentally committing project linkage. | Code edit: add `.vercel/` to the relevant `.gitignore` (root, or `web/.gitignore` if mechanism d). |

**Nothing found in category "Stored data" and "OS-registered state"** — verified by reading `backend/api/_lib/db.js`, `backend/vercel.json`, and the repo's top-level directory listing directly; this phase is purely deploy/routing configuration, no data model touched.

## Code Examples

### Existing rewrite to preserve (verified by direct read, `backend/vercel.json`)
```json
{
  "rewrites": [
    { "source": "/sync/:path*", "destination": "/api/sync/:path*" }
  ]
}
```
Whichever mechanism wins, this exact rule (or its Root-Directory-adjusted equivalent) must still resolve `/sync/push`, `/sync/pull`, `/sync/state` to the 3 existing function files without changing their request/response contract — Success Criterion 2 is the executable check for this.

### Shim pattern (mechanisms a/d) — illustrative, not yet verified against a real `vercel dev` run
```js
// api/sync/push.js  (repo-root or web/ root, depending on mechanism)
export { default } from '../../backend/api/sync/push.js';
```
Source: standard ESM re-export syntax (`backend/package.json` already declares `"type": "module"`); the actual relative path depends on the final chosen Root Directory and must be verified by the spike, not assumed.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Manually running `vercel env add DATABASE_URL preview <branch>` and remembering to keep it a non-prod branch forever | Neon's native Vercel Marketplace integration with per-Preview-deployment branch creation | Documented as available in 2026 Neon docs (exact GA date not confirmed by this research — flagged LOW confidence on when it went GA, HIGH confidence that it exists and works as described today) | Removes an entire class of "did someone forget to point Preview at dev" mistakes — directly addresses the exact risk ADR-005 flags |
| `vercel.json` `builds` + `routes` (legacy) | `functions` + `rewrites`/`redirects`/`headers` (current) | `builds`/`routes` are explicitly marked deprecated/legacy in current docs, `functions` is what's documented now | Not directly relevant here since `backend/vercel.json` already uses the current `rewrites` style, but worth confirming the eventual new `vercel.json` also stays on `functions`/`rewrites`, not `builds`/`routes` |

## Open Questions

1. **Is the Neon↔Vercel native integration already connected to this Vercel project?**
   - What we know: The integration is the recommended, zero-code way to satisfy INFRA-02.
   - What's unclear: Whether it's already set up (Phase 2/10 didn't mention it) or needs to be connected from scratch this phase.
   - Recommendation: First task of the phase's plan should be checking the Vercel dashboard's Storage tab (or `vercel env ls` for a `DATABASE_URL` entry scoped only to Preview, distinct from Production) before deciding whether to "enable" or "verify" the integration.

2. **Which of (a) shims-at-root, (c) move-to-root, (d) shims-at-`web/` does the spike actually confirm works, and does it change the `.vercelignore` requirement?**
   - What we know: (b) is ruled out analytically (see Routing Mechanisms section) — HIGH confidence, sourced from official docs + a Vercel maintainer's direct GitHub answer.
   - What's unclear: Whether (a)/(c)/(d) all pass `vercel dev` cleanly, and whether "Include source files outside Root Directory" (needed by a/d to reach `backend/api/_lib/*`) behaves identically for `vercel dev` (local) vs. a real deployed Preview — this local/deployed parity is exactly what Success Criterion 1's spike must establish before committing.
   - Recommendation: The spike should test (a), (c), and (d) in that order, stopping at the first that (i) serves `/sync/state` as JSON via `vercel dev` and (ii) moves the fewest files per ADR-005 tie-break rule already stated in CONTEXT.md.

3. **Does changing `backend/`'s Root Directory (or moving its `api/` contents) break `backend/`'s existing test suite (`npm test`, `node --test`) or its `.env.example`/CI workflow?**
   - What we know: `backend/package.json` has its own `test` script and `.env.example`; `.github/` exists in the repo (workflows not read in this research pass).
   - What's unclear: Whether any GitHub Actions workflow assumes `cd backend && npm test` — a Root Directory/location change to `backend/api` could break CI silently.
   - Recommendation: The plan should include reading `.github/workflows/*.yml` before finalizing which mechanism to implement, and update the workflow's working directory / paths if `backend/api` moves.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Vercel CLI | Running the `vercel dev` spike locally | ✗ (not installed globally in this environment) | — (npm registry latest: 60.1.3) | `npx vercel@latest <command>` — no global install needed |
| Node.js | Running Vercel CLI, backend tests | ✓ | v22.14.0 | — (matches `backend/package.json`'s `"engines": { "node": ">=22" }`) |
| Vercel account/project access + `vercel link` | Confirming which mechanism deploys correctly on a real Preview (not just local `vercel dev`) | Unknown — not verifiable from this filesystem-only research pass; no `backend/.vercel/project.json` present in this worktree | — | If not yet linked in this worktree, the plan's first task must run `vercel link` (interactive, requires human running it, not automatable by an agent without credentials) |
| Neon dashboard / API access | Verifying whether a Neon dev branch already exists, and confirming Preview's actual `DATABASE_URL` value (Success Criterion 3) | Unknown — not verifiable from this filesystem-only research pass | — | None — this is a hard requirement; must be done by whoever has Neon/Vercel dashboard access (likely the user, not the agent) |

**Missing dependencies with no fallback:**
- Vercel project/dashboard access and Neon dashboard access to actually connect the integration and inspect real Preview env values — this is inherently a human-in-the-loop or credentialed-CLI step, not something researchable further from the filesystem.

**Missing dependencies with fallback:**
- Vercel CLI itself — use `npx vercel@latest` instead of a global install.

## Validation Architecture

> `workflow.nyquist_validation` not found as an explicit key in `.planning/config.json` at time of this research check — treating as enabled per the instructions' default.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node's built-in `node --test` (no external test framework) — `backend/package.json`: `"test": "node --test"` |
| Config file | none — plain `node --test` convention, picks up `*.test.js` files under `backend/api/` |
| Quick run command | `cd backend && npm test` (integration tests against `push.js`/`pull.js`/`state.js` skip cleanly without `DATABASE_URL` set, per `backend/README.md`) |
| Full suite command | `cd backend && DATABASE_URL=<neon-dev-branch-url> npm test` (runs the integration tests for real, including the PULL-03 concurrency test per STATE.md) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | `/sync/*` still reaches the 3 functions unchanged after the routing mechanism change | smoke (manual/scripted HTTP, not a `node --test` file) | `curl -s https://<preview-url>/sync/state -H "Authorization: Bearer $WEB_API_KEY"` — must return valid JSON, not HTML | ❌ — no existing automated smoke test for "same deploy serves both web and `/sync/*`"; Wave 0 should add a tiny script (`backend/scripts/smoke-preview.sh` or similar) rather than rely on ad hoc curl, so this check is repeatable at every future Preview deploy |
| INFRA-02 | Preview never uses Production's `DATABASE_URL` | manual/scripted inspection, not a code-level unit test | `vercel env pull --environment=preview .env.preview.local && grep DATABASE_URL .env.preview.local` compared against the known Production value (never print Production's value in CI logs) | ❌ — this is inherently an environment-inspection check, not something `node --test` can verify from inside the function's own runtime unless the function itself exposes a non-sensitive "which branch am I on" debug field (existing functions don't have this) |
| INFRA-03 | `web/` Flutter leftovers removed | trivial file-existence check | `test ! -f web/index.html && test ! -f web/manifest.json && test ! -d web/icons && test ! -f web/favicon.png && echo OK` | ❌ (trivial — one-liner, no dedicated test file needed per ponytail "YAGNI applies to tests too" for one-liners) |

### Sampling Rate
- **Per task commit:** re-run `cd backend && npm test` (fast, skips integration tests without `DATABASE_URL`) to make sure the 3 functions' unit-level behavior (auth, spec validation) is untouched by the routing change.
- **Per wave merge:** run the full suite with `DATABASE_URL` pointed at the Neon dev branch, plus the manual/scripted Preview smoke check (INFRA-01/02 above) against a real Preview deployment — this is the one MUST-NOT-SKIP step given the phase's explicit "smoke test before merge to main" requirement.
- **Phase gate:** both smoke checks (INFRA-01 JSON response, INFRA-02 env var inspection) green on a real Preview URL, plus the real phone still syncing against Production untouched, before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] A small smoke-test script (e.g. `backend/scripts/smoke-preview.sh`) that curls `/sync/state` on a given Preview URL and asserts JSON content-type — currently this check would otherwise be done ad hoc and not remembered for the next deploy.
- [ ] A documented (not necessarily scripted) procedure for INFRA-02's env var inspection (`vercel env pull --environment=preview`) — since this touches real secrets, a full automated test isn't appropriate, but the exact command sequence should be written down in the plan so it's repeatable and not "assumed."
- [ ] `.github/workflows/*.yml` review (see Open Question 3) — not a test gap per se, but a CI-breakage risk that should be checked before or during Wave 0.

## Sources

### Primary (HIGH confidence)
- [Vercel — Static Configuration with vercel.json, `functions` section](https://vercel.com/docs/project-configuration/vercel-json#functions) — fetched directly 2026-09-25, confirms `api/` directory convention and that `functions` only configures already-discovered functions
- [Vercel — Advanced Configuration (Functions)](https://vercel.com/docs/functions/configuring-functions/advanced-configuration) — fetched directly, confirms underscore/`.`-prefixed files in `/api` are never turned into functions (already followed by `backend/api/_lib/`)
- [Vercel — Using Monorepos](https://vercel.com/docs/monorepos) — fetched directly, confirms Root Directory model, "Include source files outside Root Directory" default-on behavior, and Related Projects feature
- [Vercel — Monorepos FAQ](https://vercel.com/docs/monorepos/monorepo-faq) — fetched directly, confirms multi-domain proxying pattern and the "Include source files outside Root Directory" default for projects created after 2020-08-27
- [Vercel CLI `env` docs](https://vercel.com/docs/cli/env) and [Environments Variables per Git branch changelog](https://vercel.com/changelog/environments-variables-per-git-branch) — via WebSearch snippet, confirms `vercel env add VAR preview <branch>` and `vercel pull --environment=preview --git-branch=<branch>` syntax, CLI ≥21.0.1 requirement
- Direct repo reads: `backend/vercel.json`, `backend/README.md`, `backend/package.json`, `backend/api/_lib/{auth,db}.js`, repo root `ls`, `.gitignore`/`backend/.gitignore` — establishes current state, the Flutter-tree-at-root discovery, and absence of a root `package.json`/`.vercel/`

### Secondary (MEDIUM confidence)
- [Neon — Vercel Native Integration: Create a Neon Branch Per Preview](https://neon.com/blog/neon-vercel-native-integration) (via WebFetch summary) — confirms per-preview branch automation, setup steps via Storage tab, and that selecting only "Preview" scope keeps Production isolated
- Neon docs (`neon.com/docs/guides/vercel-native-integration`, fetched via WebFetch) — confirms injected env var names (`DATABASE_URL`, `DATABASE_URL_UNPOOLED`, `PG*`, `POSTGRES_*`) and explicitly notes Preview env vars are injected via webhook and not visible in the dashboard's static Environment Variables list
- [vercel/vercel GitHub Discussion #7591](https://github.com/vercel/vercel/discussions/7591) — a Vercel team member's direct answer that custom function directories outside `/api` are not supported, used to cross-verify the official docs' wording

### Tertiary (LOW confidence)
- Exact GA date of the Neon native integration, and whether it's already connected to this specific Vercel project — not verifiable from this research pass; flagged as Open Question 1 for the plan's first task to check directly against the live dashboard.

## Metadata

**Confidence breakdown:**
- Standard stack (Vercel CLI, Neon integration existence): HIGH — official docs fetched directly, cross-verified
- Routing mechanism analysis (ruling out mechanism b): HIGH — official docs + maintainer GitHub answer agree
- Flutter-tree-at-root risk and `.vercelignore` need: MEDIUM — inferred from direct repo inspection + general Vercel monorepo docs, not from a page that discusses this exact scenario
- Neon env var names / Preview injection behavior: MEDIUM — single official-docs fetch, not independently cross-verified with a second source
- Whether the Neon integration is already connected to this project: LOW/unknown — requires live dashboard check, not filesystem-verifiable

**Research date:** 2026-09-25
**Valid until:** ~30 days (Vercel platform docs and Neon integration behavior can shift; the routing-mechanism finding, being about a stable platform primitive, is likely to remain valid much longer than that)
