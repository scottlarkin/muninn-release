# Configuration reference

Every muninn setting, its default, and what it does.

**You do not need most of this.** A working install sets two or three values; the
rest are tuning knobs with sensible defaults. Start with
[the example configs in the README](README.md#example-configs), and come here when
you want to change something specific.

Config lives at `~/.config/muninn/config.toml`. Precedence, lowest first:

```
defaults  <  config.toml  <  project .muninn.toml  <  MUNINN_* env  <  flags
```

- **Env form** uppercases the key and nests with a **double** underscore:
  `neo4j.password` becomes `MUNINN_NEO4J__PASSWORD`.
- **Secrets** accept a literal, `env:VAR`, or `file:path`. Prefer the latter two.
- **A project `.muninn.toml`** is untrusted: only a small allowlist of tuning keys
  is honoured from it, never credentials, endpoints or paths, so cloning a
  repository cannot redirect your memory or leak your keys.
- `muninn config show` prints your effective config with secrets redacted.
  `muninn config init` writes a commented starter file.

> Generated from the binary by `make config-docs`. Do not edit by hand.

## `[neo4j]`

The memory graph. `muninn stack init` generates a password; everything else has a working default.

| Setting | Default | Description |
|---|---|---|
| `neo4j.database` | `neo4j` | Neo4j database name. |
| `neo4j.hook_timeout` | `6s` | Per-call Neo4j deadline for hook hot paths. |
| `neo4j.password` | _(unset)_ | Neo4j auth password (literal, env:VAR, or file:path); redacted in responses. |
| `neo4j.uri` | `neo4j://127.0.0.1:7687` | Bolt URI of the Neo4j graph the server reads and writes. |
| `neo4j.username` | `neo4j` | Neo4j auth username. |
| `neo4j.worker_timeout` | `30s` | Per-call Neo4j deadline for background worker operations. |

## `[embed]`

How memory is turned into vectors for search. `spaces` defines one embedding model per slot: `text` for prose, `code` for source.

> **Choose your embedding model carefully before you accumulate a large graph.**
>
> `dim` is written into the graph's vector indexes when `muninn schema init` runs. Changing it afterwards is refused by `schema migrate` / `doctor` (`embed dim vs schema`) until you repair: run **`muninn reembed`** to drop/recreate indexes, batch re-embed memory, and stamp `:EmbedConfig`. Code vectors need `muninn index` on each repo after a code-space change.
>
> Model changes at the *same* dim used to pass silently (mixed geometry, quiet recall degradation). The embed fingerprint closes that gap — `muninn doctor` and `muninn reembed --check` report drift; re-embed so old and new vectors are not mixed.

| Setting | Default | Description |
|---|---|---|
| `embed.api_key` | _(unset)_ | OpenAI embedding API key (openai provider only); redacted in responses. |
| `embed.base_url` | `http://127.0.0.1:11434` | Base URL of the embedding provider. |
| `embed.provider` | `ollama` | Embedding backend provider ("ollama" or "openai"). |
| `embed.spaces.code.asymmetric` | `false` | Whether the code model needs search_document:/search_query: prefixes. |
| `embed.spaces.code.dim` | `768` | Vector dimension for the code embedding space. |
| `embed.spaces.code.model` | `unclemusclez/jina-embeddings-v2-base-code:latest` | Model that produces vectors for the code embedding space. |
| `embed.spaces.text.asymmetric` | `true` | Whether the text model needs search_document:/search_query: prefixes. |
| `embed.spaces.text.dim` | `768` | Vector dimension for the text embedding space. |
| `embed.spaces.text.model` | `nomic-embed-text` | Model that produces vectors for the text embedding space. |
| `embed.timeout` | `4s` | Per-call timeout for embedding requests. |

## `[llm]`

Used to distil lessons from sessions and mint entities. `provider` selects the backend; the other keys are read per provider. `claude-cli` shells out to your local `claude` binary and is only reachable by naming it explicitly.

The quality evals are recorded against `claude-haiku-4-5`, so treat that as the floor: below it, models increasingly miss the strict-JSON output contract, which yields *no* lesson rather than a poor one. `qwen2.5-coder:7b` is the tested local default.

`model` is the model muninn actually calls — set it to any model id your provider accepts. Empty uses the provider default (`claude-haiku-4-5` for anthropic/openai, `qwen2.5-coder:7b` for ollama).

| Setting | Default | Description |
|---|---|---|
| `llm.anthropic_api_key` | `env:ANTHROPIC_API_KEY` | Anthropic API key (literal, env:VAR, or file:path); redacted in responses. |
| `llm.anthropic_url` | `https://api.anthropic.com/v1/messages` | Anthropic messages API endpoint. |
| `llm.api_key` | _(unset)_ | OpenAI bearer API key (openai provider only); redacted in responses. |
| `llm.base_url` | `http://127.0.0.1:11434` | Base URL for the ollama/openai LLM provider. |
| `llm.keep_alive` | `10m` | Ollama keep-alive window for the loaded model. |
| `llm.local_model` | _(empty)_ | Deprecated alias for llm.model when provider is ollama (still read for compatibility). |
| `llm.model` | _(empty)_ | Model id for every LLM call. Empty uses the provider default (claude-haiku-4-5 for anthropic/openai, qwen2.5-coder:7b for ollama). |
| `llm.model_haiku` | _(empty)_ | Deprecated alias for llm.model (still read for compatibility). |
| `llm.model_sonnet` | _(empty)_ | Deprecated and unused; there is no second model tier. Prefer llm.model. |
| `llm.provider` | `anthropic` | LLM provider ("anthropic", "openai", "ollama", or "claude-cli"). |
| `llm.timeout_api` | `30s` | Provider-level timeout ceiling for hosted API LLM calls. |
| `llm.timeout_local` | `1m0s` | Provider-level timeout ceiling for local LLM calls. |

## `[recall]`

What gets injected into a prompt, and how it is ranked. Almost all of this is tuning you will never need to touch — the two that matter are `inject` (turn auto-injection off) and the `budgets.*` character caps.

| Setting | Default | Description |
|---|---|---|
| `recall.ann_k_dead_end` | `40` | ANN fan-out for the dead-end arm; larger than the lesson fan-out because it post-filters a rare kind out of the shared lesson vector index. |
| `recall.ann_k_lesson` | `10` | Nearest-neighbour count fetched from the lesson vector index. |
| `recall.ann_k_prompt` | `50` | Nearest-neighbour count fetched from the prompt vector index. |
| `recall.ann_k_session` | `5` | Nearest-neighbour count fetched from the session vector index. |
| `recall.ann_overfetch` | `1` | Vector-ANN over-fetch multiplier for multi-tenant fairness (1 = off). |
| `recall.budgets.applications` | `500` | Character budget for the applications recall section. |
| `recall.budgets.code` | `1000` | Character budget for the code recall section (isolated code-navigation lane). |
| `recall.budgets.dead_ends` | `700` | Character budget for the dead-end recall section. |
| `recall.budgets.entity` | `1000` | Character budget for the entity recall section. |
| `recall.budgets.lessons` | `1200` | Character budget for the lessons recall section. |
| `recall.budgets.remembered` | `800` | Character budget for the remembered-context recall section. |
| `recall.budgets.semantic` | `1100` | Character budget for the semantic (similar-prompt) recall section. |
| `recall.budgets.temporal` | `1100` | Character budget for the temporal (recent-work) recall section. |
| `recall.cooccurrence_boost` | `0.05` | Ranking boost for memories that co-occur with recalled seeds. |
| `recall.dead_end_sim_threshold` | `0.8` | Min cosine a dead end must reach to surface; higher than the lesson threshold because a weakly-relevant prohibition can suppress a valid approach. |
| `recall.distiller.enabled` | `true` | Whether recalled memories are LLM-distilled before injection. |
| `recall.distiller.min_grade_code` | `0.4` | Min distiller relevance grade [0,1] a code item must reach to survive. |
| `recall.distiller.min_grade_dead_end` | `0.5` | Min distiller relevance grade [0,1] a dead end must reach to survive; the strictest tier. |
| `recall.distiller.min_grade_entity` | `0.4` | Min distiller relevance grade [0,1] an entity must reach to survive. |
| `recall.distiller.min_grade_lesson` | `0.2` | Min distiller relevance grade [0,1] a lesson must reach to survive. |
| `recall.distiller.min_items` | `6` | Min recalled items before the distiller runs. |
| `recall.distiller.timeout_api` | `5s` | Deadline for the recall distiller when it runs against a hosted API. |
| `recall.distiller.timeout_local` | `8s` | Deadline for the recall distiller when it runs against a local model. |
| `recall.entity.ann_k` | `24` | Nearest-neighbour count fetched from the entity vector index. |
| `recall.entity.max_nodes` | `30` | Max entity nodes returned by the entity recall walk. |
| `recall.entity.max_seeds` | `12` | Max entity seeds expanded in the entity recall walk. |
| `recall.entity.mention_boost` | `0.15` | Soft rank boost for entities with more MENTIONS + RELATED_TO degree (0 = off). |
| `recall.entity.rel_types` | _(empty)_ | Restrict entity expansion to these RELATED_TO edge types (empty = all). |
| `recall.entity.repo_match_boost` | `1.3` | Soft rank multiplier for entities in the current repo; the lane stays tenant-wide (1.0 = off). |
| `recall.entity.sim_min` | `0.6` | Min cosine similarity for an entity to be an entity-recall seed. |
| `recall.entity.summary_boost` | `0.25` | Soft rank boost for entities with a longer, non-empty summary (0 = off). |
| `recall.entity.summaryless_penalty` | `0.5` | Soft rank multiplier for entities with an empty summary (thin stubs); (0,1], 1.0 = off. |
| `recall.entity.type_inference.boost` | `1.25` | Seed-score multiplier applied to type-matched entities. |
| `recall.entity.type_inference.enabled` | `true` | Enable the auto-inferred type boost on entity seeds (boost-only). |
| `recall.entity.type_inference.threshold` | `0.72` | Min ANN score for an inferred top type to boost entity seeds. |
| `recall.entity.type_inference.top_k` | `3` | Max inferred seed types before entity expansion. |
| `recall.entity.usage_factor_clamp` | `[0.6 1.4]` | Min/max clamp on the usage-based ranking factor for entities. |
| `recall.entity.walk_hops` | `2` | Hop depth of the RELATED_TO entity expansion walk. |
| `recall.entity_sim_floor` | `0.6` | Min cosine similarity for an entity seed to enter recall. |
| `recall.file_context_timeout` | `3s` | Deadline for the PreToolUse file-context hook; it returns empty rather than delaying a tool call. |
| `recall.forget_sim_threshold` | `0.8` | Min cosine score a node must reach a `forget` phrase to be a deletion candidate. |
| `recall.inject` | `true` | Whether UserPromptSubmit / PreToolUse hooks inject additionalContext (false = skills-only; record/promote still run). |
| `recall.lesson_sim_threshold` | `0.76` | Min cosine similarity for a lesson to be recalled. |
| `recall.max_dead_ends` | `3` | Max dead ends (approaches already tried and rejected) surfaced in the dead-end recall section. |
| `recall.max_entity_lessons` | `5` | Max lessons attached via entity seeds. |
| `recall.max_hop_lessons` | `5` | Max lessons pulled in via graph hops. |
| `recall.max_lessons` | `8` | Max lessons included in recall output. |
| `recall.max_roots` | `5` | Max root memories seeded into a recall assembly. |
| `recall.prompt_sim_threshold` | `0.8` | Min cosine similarity for a past prompt to be recalled. |
| `recall.recency_decay` | `0.03` | Exponential decay rate applied to older memories in ranking. |
| `recall.rm_cum_floor` | `0.3` | Min cumulative path score to keep a remembered-context hop. |
| `recall.rm_drift_min` | `0.6` | Min semantic drift score for a remembered-context hop. |
| `recall.rm_edge_floor` | `0.45` | Min edge weight for a remembered-context multi-hop traversal step. |
| `recall.rm_hop_edge_min` | `0.85` | Min edge score for a remembered-context hop expansion. |
| `recall.rm_hop_seed_threshold` | `0.76` | Min similarity for a node to seed a remembered-context hop. |
| `recall.rm_max_hops` | `4` | Max hops for the remembered-context multi-hop walk. |
| `recall.session_sim_threshold` | `0.8` | Min cosine similarity for a session summary to be recalled. |
| `recall.skip_prefixes` | `/muninn-view`, `/muninn-recall`, `/muninn-index`, `/muninn-risky`, `/muninn-impact`, `/muninn-find-similar`, `<task-notification>`, `[SYSTEM NOTIFICATION` | Prompt prefixes on which recall is skipped entirely. |
| `recall.strength.base` | `0.7` | Base strength assigned to a recalled memory before boosts. |
| `recall.strength.cap` | `0.95` | Upper cap on a recalled memory's strength. |
| `recall.strength.kept_boost` | `1.1` | Strength boost for memories previously kept. |
| `recall.strength.relevance_damp_floor` | `0.6` | Floor on the relevance dampening applied to weak matches. |
| `recall.strength.spread` | `0.25` | Strength spread across the ranked recall list. |
| `recall.strength.used_boost` | `1.25` | Strength boost for memories previously used. |
| `recall.temporal_threshold` | `0.6` | Min cosine to a temporal-recap exemplar for the recent-activity block to fire (language-agnostic arm). |
| `recall.trivial_word_min` | `4` | Minimum word count before a prompt is non-trivial enough to run recall. |

## `[lesson]`

How durable lessons are promoted, deduplicated and superseded.

| Setting | Default | Description |
|---|---|---|
| `lesson.asserted_confidence` | `3` | Seed confidence for an explicitly asserted (`remember`) lesson; kept in the outcome clamp range so it is recallable immediately and resists demotion. |
| `lesson.dead_end_dedup_threshold` | `0.92` | Cosine threshold above which a new dead end is deduped against an existing dead end (kind-scoped — never against a positive lesson). |
| `lesson.distill_dedup_threshold` | `0.88` | Cosine threshold for deduping lessons during session distillation. |
| `lesson.distill_timeout` | `1m30s` | Deadline for the LLM call that distils a whole session. |
| `lesson.global_lessons_path` | _(empty)_ | Optional hand-written markdown file whose lessons are injected verbatim, ahead of learned ones. |
| `lesson.global_lessons_section` | `Principles & Rules` | Heading within that file to read; everything under it is treated as global lessons. |
| `lesson.promote_dedup_threshold` | `0.93` | Cosine threshold above which a promoted lesson is deduped against an existing one. |
| `lesson.promote_timeout` | `1m0s` | Deadline for the LLM call that promotes a prompt into a lesson. |
| `lesson.supersede_candidate_threshold` | `0.6` | Min cosine similarity for a lesson to be a supersede candidate. |
| `lesson.supersede_proven_floor` | `2` | Confidence at or above which an incumbent lesson is proven and resists being superseded by a less-confident newer lesson; a correction demotes it below the floor and restores replaceability. |

## `[outcome]`

How a lesson's confidence moves as it proves useful or gets corrected.

| Setting | Default | Description |
|---|---|---|
| `outcome.confidence_blend_factor` | `0.05` | Blend factor mixing new outcome signal into stored confidence. |
| `outcome.confidence_clamp` | `[-4 6]` | Min/max clamp on a lesson's accumulated confidence. |
| `outcome.confidence_clean` | `0.25` | Confidence delta applied when a turn ends clean (no correction). |
| `outcome.confidence_corrected` | `-0.5` | Confidence delta applied when a turn is corrected. |
| `outcome.confidence_min_grade` | `0.5` | Min distiller grade [0,1] a kept lesson needs to earn a clean-turn confidence reward. |
| `outcome.confidence_used_bonus` | `0.25` | Extra clean-turn confidence for a lesson with usage evidence (an entity it is ABOUT was touched). 0 disables. |
| `outcome.correction_max_len` | `240` | Max prompt substring length scanned for a correction signal. |
| `outcome.correction_patterns` | `(?i)^(no|nope|wrong|wait)[,. !]`, `(?i)not what i`, `(?i)that'?s (not|wrong)`, `(?i)i said`, `(?i)i asked for`, `(?i)you (broke|missed|forgot|ignored)`, `(?i)revert`, `(?i)undo th`, `(?i)stop doing`, `(?i)still (wrong|broken|fail|not work)`, `(?i)did(n'?t| not) (work|ask)`, `(?i)doesn'?t work`, `(?i)should have` | Case-insensitive regexes that mark a user turn as a correction. |
| `outcome.recall_confidence_cutoff` | `-3` | Min confidence for a lesson to still be recalled. |
| `outcome.usage_min_path_len` | `12` | Min matched-path length before usage attribution credits a memory. |

## `[ontology]`

The runtime-grown vocabulary of entity and relation types.

| Setting | Default | Description |
|---|---|---|
| `ontology.auto_reuse_threshold` | `0.97` | Cosine similarity above which an existing type is auto-reused with no LLM check. |
| `ontology.describe_min_instances` | `3` | Min members before the distiller re-describes a minted type. |
| `ontology.enabled` | `true` | Master switch for entity minting and the type vocabulary. |
| `ontology.expand_related_types` | `true` | Whether recall follows one hop over type-level RELATED_TO edges to pull in adjacent entities. |
| `ontology.gc_after` | `14d` | How long a quarantined, still-unused type is kept before deletion. |
| `ontology.lift_min_support` | `2` | Min instance-pair support before inducing a type-level relation. |
| `ontology.max_entities_per_turn` | `8` | Max entities minted from a single turn. |
| `ontology.max_relations_per_turn` | `8` | Max entity relations minted from a single turn. |
| `ontology.max_type_props` | `8` | Max arbitrary p_* properties kept per type. |
| `ontology.max_type_relations_per_turn` | `4` | Max type-level RELATED_TO edges minted per turn. |
| `ontology.merge_threshold` | `0.93` | Min cosine similarity to merge two schema types. |
| `ontology.min_instances` | `3` | Min instances a minted type needs before it is kept. |
| `ontology.mint_timeout` | `1m0s` | Deadline for the LLM call that mints entities from a turn. |
| `ontology.quarantine_after` | `14d` | A type with too few instances is quarantined after this long — kept, but no longer offered for reuse. |
| `ontology.reuse_threshold` | `0.9` | Min cosine similarity to reuse an existing schema type instead of minting. |
| `ontology.taxonomy_depth_max` | `4` | Max SUBTYPE_OF taxonomy depth. |

## `[record]`

What is persisted per turn.

| Setting | Default | Description |
|---|---|---|
| `record.response_max_chars` | `16000` | Assistant responses are truncated to this length before being stored. |

## `[indexer]`

The tree-sitter code graph: which files are parsed, and the guards against a bad re-index deleting it.

| Setting | Default | Description |
|---|---|---|
| `indexer.concurrency` | `min(8, CPU count)` | How many files are parsed and embedded in parallel. |
| `indexer.deletion_floor` | `3` | Repos with at most this many indexed files bypass the deletion cap, so a genuinely tiny repo can still shrink. |
| `indexer.deletion_safety_cap` | `0.5` | Refuse a re-index that would delete more than this FRACTION of a repo's indexed files — a wrong --root would otherwise wipe the graph for that repo. |
| `indexer.extensions` | `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.mts`, `.cts`, `.py`, `.go`, `.ex`, `.exs` | File extensions that have a tree-sitter grammar and get indexed. Overridable per project. |
| `indexer.max_file_bytes` | `262144` | Files larger than this are skipped (generated bundles and minified output are noise in a code graph). |
| `indexer.skip_dirs` | `node_modules`, `.git`, `dist`, `build`, `vendor`, `__pycache__`, `coverage`, `.next` | Directory names never descended into. Overridable per project. |

## `[health]`

Caching of dependency probes, so hooks do not hit the network every turn.

| Setting | Default | Description |
|---|---|---|
| `health.cache_ttl` | `30s` | How long a dependency probe result is reused before re-checking; keeps hooks off the network on every turn. |
| `health.llm_probe` | `false` | Enable the background LLM liveness ping in `muninn serve`; /v1/health reports its cached result (off by default; ≈$0.90/mo on Haiku at 5m). |
| `health.llm_probe_interval` | `5m0s` | How often the background LLM liveness ping runs (floored to 30s to bound cost). |
| `health.state_path` | `~/.local/state/muninn/health.json` | File holding the cached health result, shared between CLI invocations. |

## `[log]`

Where muninn logs and how much it keeps.

| Setting | Default | Description |
|---|---|---|
| `log.capture_hook_payloads` | `false` | Reserved; currently has no effect. |
| `log.level` | `info` | Log verbosity (debug, info, warn, error). |
| `log.max_size_mb` | `10` | Log file is truncated once it exceeds this size. |
| `log.path` | `~/.local/state/muninn/muninn.log` | Log file path. |

## `[serve]`

Only relevant if you run `muninn serve` as a shared server. These knobs configure **this** process when it is the HTTP backend. They are independent of `[server]` (how the CLI talks *to* a backend).

CLI overrides for a single invocation (see `muninn serve -h`):

| Flag | Overrides |
|---|---|
| `--addr host:port` | `serve.addr` |
| `--auth-mode none\|api_key` | `serve.auth_mode` |
| `--allow-insecure-bind` | permits `auth_mode=none` on a non-loopback bind (otherwise refused) |

Endpoint table: `muninn api`. Full narrative: `API.md` in the release tarball (source: [docs/API.md](docs/API.md)). Long-lived host service (Linux systemd / macOS launchd): README § HTTP server, or [docs/SERVE.md](docs/SERVE.md) in source.

| Setting | Default | Description |
|---|---|---|
| `serve.addr` | `127.0.0.1:8080` | Listen address for `muninn serve`. |
| `serve.auth_mode` | `none` | API auth mode: "none" (open, loopback) or "api_key". |
| `serve.client_ip_header` | `X-Forwarded-For` | Header consulted for the client IP when serve.trusted_proxy is on; the rightmost entry is used. |
| `serve.job_queue_size` | `256` | Depth of the in-process background job queue used in serve mode instead of detached workers. |
| `serve.job_workers` | `4` | Number of goroutines draining that job queue. |
| `serve.max_body_bytes` | `5242880` | Max request body size in bytes (0 = unlimited). |
| `serve.preauth_burst` | `100` | Pre-auth burst allowance per client IP for uncached-key lookups. |
| `serve.preauth_global_burst` | `1000` | Pre-auth burst backstop across all IPs. |
| `serve.preauth_global_rps` | `500` | Pre-auth sustained req/s backstop across all IPs. |
| `serve.preauth_rps` | `50` | Pre-auth sustained req/s per client IP for uncached-key lookups. |
| `serve.rate_burst` | `60` | Per-API-key burst allowance for the rate limiter. |
| `serve.rate_rps` | `20` | Per-API-key sustained request rate in req/s; <=0 disables (api_key mode only). |
| `serve.shutdown_timeout` | `2m0s` | Graceful-drain window on SIGTERM before the graph driver closes. |
| `serve.trusted_proxy` | `false` | Read the real client IP from serve.client_ip_header for rate limiting. Enable ONLY behind a proxy you control — the header is client-spoofable. |

## `[server]`

Only relevant if this CLI talks to a muninn server instead of neo4j directly. A non-empty `url` switches **other** CLI commands and hooks into client mode (HTTP `/v1` instead of dialling neo4j). It does **not** change `muninn serve`: serve always starts a local backend using `[serve]` / `neo4j.*` / `embed.*` / `llm.*`. Starting serve alone does not flip the CLI to client mode — set `server.url` (or `MUNINN_SERVER__URL`) for that.

Self-host on one machine:

```toml
[serve]
addr = "127.0.0.1:8080"

[server]
url = "http://127.0.0.1:8080"
```

| Setting | Default | Description |
|---|---|---|
| `server.api_key` | `env:MUNINN_API_KEY` | API key presented to that server; redacted in responses. |
| `server.timeout` | `5s` | Per-request timeout for calls to that server. |
| `server.url` | _(empty)_ | Base URL of a muninn server. Non-empty switches the CLI and hooks into client mode: everything goes over HTTP instead of dialling neo4j directly. |

## `[license]`

Reserved for a future licence key. Unused today.

| Setting | Default | Description |
|---|---|---|
| `license.key` | _(empty)_ | Reserved for a future licence key. Unused today; an empty value is fully licensed. |
