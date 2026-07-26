<p align="center">
  <img src="assets/muninn.jpg" alt="muninn" width="480">
</p>

# muninn

Persistent memory for coding agents. muninn records what you and your agent
work on, distils durable lessons from it, and injects the relevant parts back
into every prompt automatically — so you stop re-explaining your codebase,
your conventions, and the approaches that already failed.

It runs entirely on your own machine. Your memory graph lives in a database you
control, prompts go only to model endpoints you configure, and nothing is
reported anywhere.

Closed-source software. See [LICENSE](LICENSE).

## What it does

- **Auto-injected recall.** A `UserPromptSubmit` hook finds the memory relevant
  to what you just asked and prepends it. No command to remember to run.
- **Lessons with confidence.** Corrections and preferences become durable
  lessons, deduplicated semantically and superseded in chains as you change your
  mind. Lessons that keep proving useful gain confidence; stale ones lose it.
- **Dead ends.** Negative knowledge is first class: "X was tried for P and did
  not work because Y". Surfaced in its own section so an agent stops re-exploring
  approaches you already ruled out.
- **A code graph.** tree-sitter parses your repo into files, functions, classes
  and types with import and call edges, so you can ask what depends on a symbol,
  which files are risky to change, and where similar code already exists.
- **Entity ontology.** People, tools, projects and concepts are minted as typed
  entities and linked, so recall can follow relationships rather than just
  matching text.

## Requirements

| | |
|---|---|
| **Docker** | For the local neo4j + Ollama stack. Anything Docker-compatible works. |
| **Disk** | ~1 GB for images, ~6 GB more if you use local Ollama models. |
| **RAM** | neo4j is configured for a 1 GB heap; 8 GB total is comfortable. |
| **macOS** | 12 (Monterey) or newer, Apple Silicon or Intel. |
| **Linux** | glibc 2.34 or newer — Debian 12+, Ubuntu 22.04+, RHEL 9+. |
| **Go** | **Not required.** muninn ships as a single compiled binary. |

Optionally an Anthropic API key, for higher-quality lesson distillation. Without
one, set `llm.provider = "ollama"` to stay fully local.

## Install

### Direct download

Grab the archive for your platform from the
[latest release](https://github.com/scottlarkin/muninn-release/releases/latest),
then:

```sh
tar -xzf muninn_*_darwin_arm64.tar.gz
sudo mv muninn /usr/local/bin/
```

Verify the download against `checksums.txt`:

```sh
shasum -a 256 muninn_*.tar.gz
```

> **macOS, browser downloads only.** A file downloaded through a browser is
> quarantined by Gatekeeper and will refuse to run. Homebrew and `curl` are not
> affected. To clear it:
>
> ```sh
> xattr -dr com.apple.quarantine /usr/local/bin/muninn
> ```
>
> The binary is signed ad-hoc but not notarised.

### Homebrew

Not available yet. A tap is planned, at which point this becomes:

```sh
brew install scottlarkin/muninn/muninn
```

Homebrew is also the path that avoids the Gatekeeper quarantine above, since it
downloads with `curl` rather than a browser.

## Set up

**1. Start the dependencies.**

```sh
muninn stack init
docker compose -f ~/.config/muninn/stack/docker-compose.yml up -d
```

`stack init` writes a compose file for neo4j and Ollama, generates a neo4j
password, and prints the config to match. Both services bind to loopback only.
The first start pulls the embedding models, which takes a few minutes.

**2. Write a config file.**

```sh
muninn config init
```

Then set the neo4j password `stack init` printed:

```toml
[neo4j]
password = "…"
```

Everything else is optional — every setting has a default, and every line in the
generated file is commented out with its default shown.

**3. Create the graph schema.**

```sh
muninn schema init
```

**4. Wire up Claude Code.**

```sh
muninn install
```

This shows you every file it will write and every hook it will add, then waits
for your confirmation before touching `~/.claude`. Use `--dry-run` to preview
without being asked, or `--yes` in a script. `muninn install --uninstall`
reverses it. An existing `settings.json` is merged, not replaced, after a
timestamped backup.

Restart Claude Code afterwards so the hooks load.

**5. Check it.**

```sh
muninn doctor
```

Every line should read `ok`. Then index a repository:

```sh
cd ~/your/project
muninn index
```

## Using it

Recall is automatic — the hooks handle it. These commands and skills are for
when you want to ask directly.

| Skill | Command | What it does |
|---|---|---|
| `/muninn-recall` | `muninn recall --window 7d` | What you worked on over a time window, or a file's history |
| `/muninn-search` | `muninn recall-test "<query>"` | Search memory with your own phrasing |
| `/muninn-remember` | `muninn remember "<fact>"` | Save a fact, preference or decision durably |
| `/muninn-dead-end` | `muninn remember --dead-end "<what failed>"` | Record an approach that did not work |
| `/muninn-forget` | `muninn forget "<phrase>"` | Delete memories, with a preview and confirmation |
| `/muninn-find-similar` | `muninn similar "<description>"` | Find existing code before writing new code |
| `/muninn-impact` | `muninn impact <symbol\|file>` | What breaks if you change this |
| `/muninn-risky` | `muninn risky` | Files that are both central and historically buggy |
| `/muninn-open` | `muninn open "<description>"` | Open the files matching a description |
| `/muninn-index` | `muninn index` | Build or refresh the code graph |
| `/muninn-entities` | `muninn entities` | Browse the entity vocabulary |
| `/muninn-view` | `muninn view` | The memory graph for this session |
| `/muninn-recall-test` | `muninn recall-test "<prompt>"` | Preview exactly what recall would inject |

`muninn --help` lists everything.

## Configuration

Config lives at `~/.config/muninn/config.toml`. Precedence, lowest first:

```
defaults  <  config.toml  <  project .muninn.toml  <  MUNINN_* env  <  flags
```

Environment variables uppercase the key and nest with a **double** underscore:
`neo4j.password` becomes `MUNINN_NEO4J__PASSWORD`.

Secrets accept three forms — a literal, `env:VAR`, or `file:path`. Prefer the
latter two.

`muninn config show` prints the full effective config with secrets redacted.
`muninn config init` writes a documented starter file.

A project `.muninn.toml` is treated as untrusted — only a small allowlist of
tuning keys is honoured from it, never credentials or endpoints, so cloning a
repository cannot redirect your memory or leak your keys.

### Useful settings

```toml
[recall]
# Skills-only mode: stop injecting context into prompts, but keep recording
# and lesson promotion.
inject = false

[llm]
# Stay entirely local — no hosted API calls.
provider = "ollama"
```

### Turning it off

```sh
MUNINN_DISABLE=1
```

Set in your environment, every hook becomes a silent no-op. The fastest way to
rule muninn out while debugging something else.

## Privacy

- The memory graph is stored in **your** neo4j. Nothing is uploaded.
- Prompts and completions go only to the endpoints you configure — local Ollama
  by default.
- Usage counters (token spend, request kinds) are written into your own graph,
  visible only to you.
- There is no analytics, no version check, no crash reporting, and no
  phone-home of any kind.
- The one recurring paid outbound call, an optional LLM liveness probe, is off
  by default.

## Troubleshooting

**`doctor` says neo4j is unreachable.** Confirm the stack is up
(`docker ps`) and that the password in your config matches the one in
`~/.config/muninn/stack/.env`.

**`doctor` says the embedder is unreachable.** Ollama is still pulling models on
first start; give it a few minutes and check `docker logs muninn-ollama-init`.

**Memory is not being injected.** Run `muninn doctor` and look at the hook
lines. Hooks are required to exit 0 always, so a hook pointing at a moved or
deleted binary fails silently — nothing errors, memory just stops working.
Re-run `muninn install` to repoint them, and restart Claude Code.

**`embed dim vs schema` fails.** You changed embedding models after creating the
schema. The vector index dimension is fixed at creation; point `[neo4j].uri` at
a fresh database, or revert the model.

**macOS: "cannot be opened because the developer cannot be verified".** See the
quarantine note under [Install](#direct-download).

**Linux: `GLIBC_2.xx not found`.** Your distribution is older than the build
floor. Debian 12+, Ubuntu 22.04+ or RHEL 9+ are required.

## Support

Provided as-is, with no obligation to supply support, updates or maintenance —
see [LICENSE](LICENSE). Bug reports are welcome on the
[issue tracker](https://github.com/scottlarkin/muninn-release/issues).

When reporting a problem, include `muninn version` and `muninn doctor` output.
`muninn config show` redacts secrets by default — do not use
`--unsafe-show-secrets` in a bug report.

Third-party components and their licences are listed in
[THIRD_PARTY.md](THIRD_PARTY.md).
