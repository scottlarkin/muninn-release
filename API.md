# muninn HTTP API (`/v1`)

The `muninn serve` process exposes a JSON API over HTTP. The CLI client
mode (`[server].url`) and any other harness talk to it through these
endpoints. This document is the human-readable contract for the release
binary; it ships as **`API.md`** in the download tarball and on the public
release repo. In the source tree the same file lives at `docs/API.md`.

For a compact offline endpoint table (method, path, scope, one-line
summary), run **`muninn api`** — no server or config required (always matches
this binary). Operator flags: **`muninn serve -h`**. Host service recipes
(Linux systemd / macOS launchd): README § *HTTP server (optional)*.

**Embed model / dim migration** is a local operator tool, not an HTTP route:
`muninn reembed` (bolt only; unset `[server].url`). Serve may log a warning if
config drifts from the graph fingerprint; it does not re-embed automatically.

- Base path: `/v1`
- Content type: `application/json` (request and response)
- One binary: `docker run <image> serve`. `serve.addr` defaults to
  `127.0.0.1:8080` (loopback); a non-loopback bind under `auth_mode=none` is
  refused unless `--allow-insecure-bind` is passed. The container image sets
  `MUNINN_SERVE__ADDR=0.0.0.0:8080` so the published port can reach it.

## Authentication

Auth is selected by `serve.auth_mode`:

| Mode | When | Behaviour |
|---|---|---|
| `none` (default) | self-host, single trusted operator | Every request maps to tenant `default` with full scope. No token. **Admin endpoints are unauthenticated.** |
| `api_key` | managed / multi-tenant | `Authorization: Bearer mn_<token>` required; the token resolves to a tenant + scopes. |

> **`auth_mode=none` must never be exposed to an untrusted network.** In that
> mode the middleware grants every request `read`+`write`+`admin`, so anyone
> who can reach the port can mint keys and create tenants. Bind it to
> loopback / a private network only. Managed deployments use `api_key`.

### API keys

- Format: `mn_<base64url 32 bytes>`. Minted via `POST /v1/admin/keys` and
  **shown exactly once** — store it then; it is not recoverable (only its
  sha256 is persisted, as an `:ApiKey` node).
- Scopes, checked per route group:
  - `read` — queries: recall, code similar/impact/risky, view, forget preview.
  - `write` — hooks, index push, `forget/confirm`.
  - `admin` — everything under `/v1/admin/`.
  - A key carrying a higher scope does not implicitly carry lower ones; grant
    the full set you need (default on mint: `read`+`write`).
- `GET /v1/health` and `GET /v1/version` are exempt in both modes — they
  expose no tenant data and back the load-balancer / container probe.
- The management UI under `/ui/` (and the `/ui` → `/ui/` redirect) is
  auth-exempt too: the static SPA bundle is public, and the app itself calls
  `/v1` with the user's key. Static requests are never charged against either
  rate limiter. See [Management UI](#management-ui-ui).

### Tenancy

Every node is stamped with a `tenant` property; id-keyed lookups scope by
prefix and scan/ANN queries filter `AND n.tenant = $tenant`. The tenant is
resolved from the key (`api_key`) or is `default` (`none`) — a request can
never address another tenant's data.

## Transport assumptions

- **TLS is terminated upstream** (load balancer / Caddy / nginx). The server
  speaks plain HTTP; run it behind a TLS proxy for any non-loopback exposure.
  The client warns if it sends a bearer token over `http://`.
- Request bodies are capped at `serve.max_body_bytes` (default 5 MB); over the
  cap returns `413` with code `too_large`.

## Rate limiting

Two independent limiters run in `api_key` mode (both `auth_mode=none` and the
two health endpoints are never limited). Each `429` carries code `rate_limited`
and a `Retry-After` header (seconds).

### Per-key limiter (post-auth)

Active only when `serve.rate_rps > 0` (default 20 rps, burst 60), keyed by the
resolved API key — it shapes per-tenant fairness after authentication.

### Pre-auth limiter (cache-miss only)

Guards the credential-free bearer-resolution path against unauthenticated
floods: an unknown/uncached key drives a neo4j lookup, so a request is charged
against a per-client-IP bucket and a global backstop **only when its key is not
in the auth cache** — i.e. on a cache miss, before that lookup. A request whose
key is cached (a legitimate client after its first request) touches no graph and
is **never charged**, so it is never throttled here even when it shares one
RemoteAddr with every other client behind a proxy. A malformed token is rejected
before any graph hit and is likewise never charged.

Configurable via `serve.*` (defaults sized well above any real single-client
rate, so a normal deploy needs no tuning); either rps `<= 0` disables the
matching limiter:

| Knob | Default | Meaning |
|---|---|---|
| `serve.preauth_rps` | 50 | sustained req/s per client IP |
| `serve.preauth_burst` | 100 | burst allowance per client IP |
| `serve.preauth_global_rps` | 500 | sustained req/s across all IPs |
| `serve.preauth_global_burst` | 1000 | burst allowance across all IPs |

### Trusted-proxy client-IP resolution

By default the per-IP pre-auth bucket keys on `RemoteAddr` and ignores any
`X-Forwarded-For` (attacker-controlled). Behind a TLS proxy that terminates TLS
(see *Transport assumptions*), `RemoteAddr` is the **proxy's** IP, so without
configuration every client shares one bucket. Set `serve.trusted_proxy = true`
to key on the real client IP taken from `serve.client_ip_header` (default
`X-Forwarded-For`; `X-Real-IP` also works). The limiter reads the **rightmost**
entry of that header — with a single trusted proxy that is the hop the proxy
itself appended (the peer that connected to it, i.e. the real client), whereas
leftmost entries are client-supplied and spoofable. Enable this **only** behind
a proxy you control that sets/appends the header; leave it off (default)
otherwise.

**Multi-replica caveat:** both token buckets are **per instance, in-memory**. N
replicas behind a load balancer allow up to N× the configured rate in
aggregate. Size the per-instance limits accordingly, or terminate rate
limiting at the LB. (See the `rateLimiter` comment in `auth.go`.)

## Error envelope

Every non-2xx response is:

```json
{ "error": { "code": "bad_request", "message": "human-readable detail" } }
```

Codes: `bad_request` (400), `unauthorized` (401),
`forbidden` (403), `not_found` (404), `too_large` (413), `rate_limited`
(429), `internal` (500). Unknown routes return `404` `not_found` in the same
envelope.

---

## Endpoints

### Health & version

`GET /v1/health` → `200`

```json
{ "ok": true, "deps": { "neo4j": true, "embed": true } }
```

`ok` is the AND of all dependency probes. Results are served from an
in-process TTL cache (never probed inline per request).

`GET /v1/version` → `200` `{ "version": "1.2.3" }`

### Hooks (scope: `write`)

Transcripts are never shipped raw — the client extracts structured turns /
Stop fields locally, which keeps the server harness-agnostic and payloads
small (<50 KB typical).

`POST /v1/hooks/prompt` → `200`
```json
{ "session_id": "...", "prompt": "...", "repo": "myrepo",
  "cwd_rel": "sub/dir",
  "turns": [ { "role": "user", "text": "..." }, { "role": "assistant", "text": "..." } ] }
```
→ `{ "additional_context": "## Agent memory …" }` (`""` = inject nothing).

`POST /v1/hooks/stop` → `204`
```json
{ "session_id": "...",
  "extract": { "prompt": "...", "assistant_text": "...", "has_tool_error": false,
    "task_notifications": [ { "tool_use_id": "...", "task_id": "...", "status": "..." } ],
    "footprint": "lowercased tool-input/text blob" } }
```

`POST /v1/hooks/session-end` → `202` `{ "session_id": "..." }` (enqueues
distillation jobs; returns immediately).

`POST /v1/hooks/file-context` → `200`
```json
{ "repo": "myrepo", "relpath": "src/x.ts", "session_id": "..." }
```
→ `{ "additional_context": "…" }`. `relpath` must be repo-relative; absolute
paths and `..` segments are rejected (`400`).

`POST /v1/hooks/delegation` → `204`
```json
{ "session_id": "...", "tool_use_id": "...", "subagent_type": "explorer",
  "prompt": "...", "description": "...", "tool_response": { } }
```

### Queries (scope: `read`)

Every query returns a common envelope; `markdown` is authoritative and is
printed verbatim by the CLI so client-mode output is byte-identical to local
mode. `items` is reserved for structured data.

```json
{ "markdown": "…", "items": [ { } ] }
```

- `POST /v1/recall/query` — recall dry-run: `{ "query": "...", "repo": "..." }`.
- `GET /v1/recall/temporal?window=&file=` — time-window work summary, or a
  file's history when `file` is set. `window` mirrors the `recall` CLI flag
  (`today`, `7d`, `since-monday`, …).
- `POST /v1/code/similar` — `{ "repo": "...", "query": "...", "exclude": "Symbol", "limit": 10 }`.
- `POST /v1/code/impact` — `{ "repo": "...", "target": "sym|file", "depth": 3 }`.
- `GET /v1/code/risky?repo=&area=&limit=` — `repo` required.
- `GET /v1/view?session_id=&cypher=` — session snapshot; `cypher=true` returns
  only the paste-ready visual Cypher. `session_id` defaults to the most recent.
- `POST /v1/forget/preview` — `{ "phrase": "...", "include_lessons": false, "k": 20, "threshold": 0.8 }`
  → candidates + cascade counts, writes nothing.
- `POST /v1/forget/confirm` (scope: `write`) — `{ "ids": ["..."], "include_lessons": false }`
  deletes exactly the ids from a prior preview.

### Query catalog (scope: `read`)

The free-form Cypher console was **removed**. On Community neo4j there is no
row-level security to backstop a query, so its only tenant guard was a regex
validator over attacker-authored Cypher — a bypass whack-a-mole. It is replaced
by a fixed catalog of canned, parameterised, tenant-scoped queries. Every Cypher
string is a **compile-time constant** authored server-side; `$tenant` is
injected onto every traversed node, and user input only ever reaches the graph
as bound `$params` (never string-concatenated). There is no Cypher to validate
because there is no user Cypher. **Arbitrary read-only Cypher would require
neo4j Enterprise** (RLS/ABAC as the real backstop) and is not offered here.

- `GET /v1/query/catalog` →
  `{ "queries": [ { "id": "lessons.list", "title": "Lessons", "description": "…",
  "category": "Lessons", "params": [ { "name": "order", "type": "enum",
  "required": false, "default": "confidence", "options": ["confidence","recent"],
  "help": "Sort order." } ] } ] }`. Lists the registry (no Cypher exposed). Each
  param spec carries `type` (`int`|`float`|`string`|`enum`|`bool`), `required`,
  an optional `default`, numeric `min`/`max`, enum `options`, and
  `placeholder`/`help` hints for a form UI. A param may also carry `hidden:true`
  (omitted otherwise): a machine-set override the UI keeps out of its form —
  today the `anchor_id` re-center param (see below). An entry may also carry a
  `shape` field: it is omitted (or `"table"`) for the default scalar-row queries,
  and `"graph"` for the graph-shaped queries below. An anchorable graph entry
  also carries `anchor_param` — the param the UI re-anchors the graph on when a
  node is clicked (re-run the query with that param set to the clicked node);
  omitted on non-anchorable entries. Both anchorable graph queries
  (`graph.entity_neighborhood`, `graph.code_neighborhood`) anchor on the hidden
  `anchor_id` param: a click re-centers on the **exact clicked node id** rather
  than by name, so a re-center can never resolve to an arbitrary same-named
  duplicate. When `anchor_id` is null the query falls back to its visible
  name/symbol match (`entity_name`/`symbol_name`); `entity_name` is therefore no
  longer required.

- `POST /v1/query/run` — `{ "id": "sessions.recent", "params": { "since_days": 30 },
  "limit": 200 }` → `{ "columns": [ … ], "rows": [ { } ], "truncated": false,
  "took_ms": 12 }`. Looks up the entry (`404` if unknown), then coerces and
  validates each param against its spec: an unknown param, a wrong-typed value,
  an enum value outside its `options`, a number outside its `min`/`max`, or a
  missing required param is a `400`. Defaults fill omitted params; an omitted
  optional param binds to `null` so its `$x IS NULL` filter guard is disabled.
  A client-supplied `tenant` param is a `400` — `$tenant` is injected
  server-side from the request's resolved tenant. `limit` is clamped to the
  entry's `[1,maxLimit]` window (default 200, cap 1000); the read runs under
  `AccessModeRead` with a ~15s timeout and a bounded stream (stops at `limit`+1
  rather than collecting the full result set), and over-cap results set
  `truncated`. `columns` is authoritative for header order. Nodes flatten to
  `{labels,props}`, relationships to `{type,props}`, temporals to their ISO
  strings, and embedding vectors are elided — both nested inside a node's props
  (key `embedding`/`*_vec`) and when projected as a bare scalar column
  (`RETURN n.embedding AS vec`), replaced with a `"<vector:N elided>"`
  placeholder so a renamed alias can't smuggle the raw floats past a key-only
  check.

Catalog queries (ids): `sessions.recent`, `prompts.recent`, `lessons.list`,
`lessons.top`, `entities.list`, `entities.byType`, `ontology.entity_types`,
`ontology.rel_types`, `remembered.recent`, `relations.for_entity`, `code.files`,
`code.symbols`, `stats.node_counts`.

Graph-shaped queries (`shape: "graph"`): `graph.entity_neighborhood`,
`graph.entity_relations`, `graph.session`, `graph.code_neighborhood`,
`graph.ontology_taxonomy`. Unlike the scalar queries these RETURN exactly one
row of two explicit lists — `nodes` (`{id,label,group,sub}` maps; the ontology
query adds an `instances` count) and `edges` (`{source,target,type}` maps whose
`source`/`target` match `nodes[].id`) — plus a `truncated` bool. Their fan-out
is bounded INSIDE the Cypher (a `LIMIT` before `collect`, then the lists are
sliced) because `limit`/`truncated` on the envelope bound top-level rows, not
graph nodes; `truncated` in the row reports whether a node/edge cap was hit. The
SPA reads `rows[0]` to render a node/edge graph.

`graph.session` takes NO session id: it returns the `count` most-recent sessions
(default 5, 1–20) as prompt→response chains with mentioned entities, optionally
narrowed by `since_days` and a case-insensitive `summary_contains` substring of
the session summary (whose values are suggested from `sessions.recent`).

### Stats (scope: `read`)

- `GET /v1/stats/usage?days=30` — `days` clamped to `[1,365]` →
  `{ "points": [ { "day": "2026-07-18", "kind": "llm", "model": "haiku", "calls": 3, "tokens_in": 120, "tokens_out": 40 } ] }`.
  Daily per-tenant usage aggregates (`kind`: `llm`/`embed`/`recall_query`/
  `hook_prompt`/`hook_stop`; embed `tokens_in` counts items). Best-effort
  telemetry flushed every 30s.
- `GET /v1/stats/graph` — `{ "counts": { "Entity": 42, "Prompt": 10, "Entity:function": 30, … } }`.
  Per-label node counts for the tenant over a fixed real label set (`Session`,
  `Prompt`, `Response`, `Entity`, `Lesson`, `SchemaType`) — these are the only
  labels the graph actually writes. The code/ontology graph has no separate `File`/`Function`/
  `Class`/... labels: it's all `:Entity` nodes discriminated by a `type`
  property (indexer write path), so `Entity` is broken down by that
  discriminator as `Entity:<type>` keys (e.g. `Entity:file`, `Entity:function`,
  `Entity:class`, `Entity:method`, `Entity:type`), consistent with the
  `stats.node_counts` query catalog entry.

### Index push (scope: `write`)

The client parses (tree-sitter, sha256, embed-text assembly, import
resolution); the server embeds and writes. Node identity is
`tenant:repo:relpath(#qualifiedName)`, derived server-side — no absolute path
crosses the wire. Ceilings: ≤ 500 files per
`/delta` batch, ≤ 50 per `/files` batch (keeps worst-case bodies under the
5 MB cap); over-limit → `413`.

- `POST /v1/index/delta` — `{ "repo": "...", "files": [ { "relpath": "...", "sha": "..." } ] }`
  → `{ "changed": [...], "unknown": [...], "repo_indexed": true }`.
- `POST /v1/index/files` — `{ "repo": "...", "files": [ FilePush ] }`
  → `{ "results": [ { "relpath": "...", "nodes": 3, "embeds": 3, "error": "" } ] }`.
  A per-file failure never fails the batch.
- `POST /v1/index/complete` — `{ "repo": "...", "changed": [...], "all_files": [...], "apps": { } }`
  → `{ "edges": 12, "nodes_deleted": 1, "errors": 0 }`. `all_files` empty
  skips the deletion reconcile (single-file incremental pushes).

See the index push request shapes (FilePush / SymbolPush / AppBatch) for the
full parsed-file and application-layer shapes.

### Admin (scope: `admin`)

`POST /v1/admin/tenants` — `{ "id": "acme" }` → `201` `{ "id": "acme" }`
(provisions the tenant and seeds its ontology vocabulary).

`POST /v1/admin/keys` — `{ "tenant": "acme", "scopes": ["read","write"] }`
→ `201` `{ "key": "mn_…", "id": "k_…" }`. `key` is returned **once**; empty
`scopes` defaults to `read`+`write`.

`DELETE /v1/admin/keys/{id}` — `204` (revoked) or `404` (no such key).

`GET /v1/admin/config` — `{ "effective": { "recall.ann_k_prompt": 50, … }, "overrides": { }, "fields": [ … ] }`.
The tenant's effective config as a flat dotted-key map with secrets (passwords,
API keys) masked, plus its stored overrides, plus `fields`: a per-key metadata
view for the config UI, sorted by `(section, key)`. Each `ConfigField` is:

```jsonc
{
  "key": "recall.trivial_word_min", // dotted config key
  "section": "recall",              // top-level segment before the first "."
  "value": 4,                       // effective (merged, redacted) value
  "default": 4,                     // process Default(), redacted identically (tenant-agnostic)
  "overridable": true,              // may be set via PUT /v1/admin/config
  "secret": false,                  // credential material (value/default masked when true)
  "type": "int",                    // string|int|float|bool|string_list|duration|object
  "description": "Minimum word count before a prompt is non-trivial enough to run recall."
}
```

`value`/`default` mirror `effective` (secrets are `***redacted***`, durations
are strings like `"4s"`). `description` is `""` for keys without a curated blurb.
`effective` and `overrides` are unchanged; `fields` is additive.

`PUT /v1/admin/config` — `{ "overrides": { "lesson.distill_dedup_threshold": 0.9 } }`
→ the fresh `ConfigResponse`. Full-replace of the tenant's overrides (`{}`
clears them). Only the allowlisted per-tenant tuning knobs may be set — the same
allowlist a project `.muninn.toml` may set, never endpoints/secrets/paths or
cost-multiplying fan-out — else `400` naming the offending key; an out-of-bounds
value is also `400`. Stored in neo4j and merged at request time (30s TTL cache),
so edits are hot without a restart.

**Multi-replica caveat:** revoke drops the key from **this instance's**
auth cache immediately. Sibling replicas keep honouring a warm-cached key
until their own TTL expires (`serve` key-cache TTL). Multi-replica serving is
out of scope for v1; for immediate global revoke, run a single serve instance
or shorten the TTL.

---

## Management UI (`/ui/`)

A Vite single-page app (config, graph explorer, recall playground, ontology,
usage stats) is embedded in the binary via `//go:embed` and served same-origin:

- `GET /ui/` serves the SPA; hashed asset URLs under `/ui/assets/` carry
  `Cache-Control: public, max-age=31536000, immutable`, `index.html` carries
  `no-cache`. The SPA is hash-routed, so deep links never round-trip to the
  server — there is no history-fallback rewrite.
- `GET /ui` → `301` to `/ui/`; bare `GET /` → `302` to `/ui/`.
- Static assets are auth-exempt (see [Authentication](#authentication)); the
  app authenticates its own `/v1` calls with the user's key.

The UI is served from the assets baked in at build time. Build the frontend
before compiling the binary:

```sh
npm --prefix web ci        # first time / after dep changes
npm --prefix web run build # emits web/dist/
go build ./cmd/muninn      # embeds web/dist/ into the binary
```

Without the frontend build step, `web/dist/` holds only a committed `.gitkeep`,
so `go build` still succeeds and `/ui/` returns the standard `not_found` error
envelope (`"UI not built into this binary"`).

---

## Client-mode degradation

When the CLI runs in client mode and the server is unreachable, hooks degrade
to "no context injected, exit 0" — identical to neo4j-down in local mode. All
seven [CONTRACT.md](CONTRACT.md) guarantees hold verbatim.
