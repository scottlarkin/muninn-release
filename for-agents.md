# muninn: instructions for an installing agent

You are installing muninn for a user. This file is written for you, not for them.
Follow it literally; the ordering constraints are real.

muninn gives coding agents persistent memory: it records work, distils durable
lessons, and injects the relevant parts into future prompts automatically.

## Ask before you act

Three steps have side effects outside muninn's own directories. Get explicit
consent for each, and skip it rather than guess:

1. **Starting Docker containers** — neo4j and Ollama, plus ~6 GB of model
   downloads on first start.
2. **Writing `~/.claude`** — skills and hook entries in the user's Claude Code
   config. Their `settings.json` is merged and backed up, never replaced.
3. **`sudo`**, if installing to `/usr/local/bin`. Prefer `~/.local/bin` if the
   user would rather not.

Do not run the installer with `--yes` unless the user has said yes to all three.

## Fast path

```sh
curl -fsSL https://raw.githubusercontent.com/scottlarkin/muninn-release/main/install.sh | bash
```

It asks how to reach each of the three dependencies (graph, embeddings, LLM):
run it in Docker, use one already running, or point at a remote provider. Then it
prompts before starting containers and before writing `~/.claude`. Prompts come
from `/dev/tty`, so they work under `curl | bash`. Useful flags: `--yes`,
`--no-stack`, `--no-claude`, `--prefix DIR`, `--version vX.Y.Z`.

If there is no terminal at all, prompts cannot happen — the script takes the
all-Docker defaults and prints what it chose. Do not "fix" that by adding
`--yes`.

**This matters for you specifically.** You probably have no TTY, so you cannot
answer the wizard. Two options:

- The user wants the standard local setup → run the installer as-is. Defaults are
  Docker for the graph and embeddings, and Anthropic if `ANTHROPIC_API_KEY` is
  already exported (otherwise a local Ollama model).
- The user wants anything else — an Ollama they already run, a remote endpoint, a
  hosted neo4j → **use the manual path below and write the config yourself.** The
  exact shapes are in "Non-default dependencies".

## Manual path

Use this when the user wants to see each step, or the script failed.

**1. Install the binary.** Resolve the latest tag, pick the platform
(`darwin_arm64`, `darwin_amd64`, `linux_amd64`, `linux_arm64`), download,
**verify the sha256 against `checksums.txt`**, and place the binary.

```sh
tar -xzf muninn_<tag>_<platform>.tar.gz
sudo mv muninn /usr/local/bin/      # or ~/.local/bin, no sudo needed
```

> **Ordering constraint, do not reorder.** The binary must be at its final path
> *before* step 4. `muninn install` writes the absolute path of the running
> binary into each hook command. Run it from a temp dir and the hooks point at a
> file that no longer exists — and hooks are required to exit 0 always, so this
> fails **silently**: memory just never works, with no error anywhere.

**2. Local dependencies.**

```sh
muninn stack init                   # writes compose + .env with a generated password
docker compose -f ~/.config/muninn/stack/docker-compose.yml up -d
```

Wait for health before step 3:
`docker inspect -f '{{.State.Health.Status}}' muninn-neo4j` must say `healthy`.
The Ollama model pulls continue in the background; `docker logs muninn-ollama-init`
shows progress.

**3. Config, then schema.** `stack init` only *prints* the neo4j password —
nothing wires it up. Write it into the config yourself:

```sh
PW=$(grep '^MUNINN_NEO4J_PASSWORD=' ~/.config/muninn/stack/.env | cut -d= -f2-)
printf '[neo4j]\npassword = "%s"\n' "$PW" >> ~/.config/muninn/config.toml
muninn schema init
```

If `config.toml` already exists, **do not overwrite it** — append or patch the
`[neo4j]` block only.

**4. Claude Code.**

```sh
muninn install          # add --dry-run first to show the user what will change
```

**5. Verify, then hand back.**

```sh
muninn doctor           # exits non-zero if anything is wrong
```

Tell the user to **restart Claude Code** — hooks load at startup. Then suggest
`cd <their repo> && muninn index` to build the code graph.

## Verifying success

`muninn doctor` should be all `ok`. Specifically confirm:

- `neo4j reachable` and `embedder reachable`
- `embed dim vs schema` — a mismatch means the embedding model changed after the
  schema was created; the vector index dimension is fixed at creation
- `hooks installed` — a `warn` here is fine if the user gets hooks from the
  Claude Code plugin instead; a `FAIL hook binary` line means a hook points at a
  moved or deleted binary, so re-run `muninn install`

## Failure modes

| Symptom | Cause and fix |
|---|---|
| `404` downloading the asset | Wrong tag, or the release lacks that platform. Re-resolve the latest tag. |
| `checksum mismatch` | Do not proceed. Re-download; report it if it repeats. |
| `port is already allocated` | Something already uses 7474/7687/11434. If it is another muninn stack, reuse it instead of starting a second. |
| `docker: command not found` | Install Docker, or use `--no-stack` and point config at an existing neo4j. |
| `schema init` connection refused | neo4j not healthy yet, or the password is not in the config. Check both. |
| `embedder unreachable` | Ollama is still pulling models. Wait, then re-check. |
| macOS `cannot be opened because the developer cannot be verified` | The tarball was downloaded by a browser and quarantined. `xattr -dr com.apple.quarantine <path>/muninn`. Use `curl`. |
| Memory silently not working | Almost always a stale hook path. `muninn doctor`, then `muninn install`, then restart Claude Code. |

## Turning off auto-injection

If the user wants muninn to keep learning but stop adding context to prompts:

```toml
[recall]
inject = false
```

or `MUNINN_RECALL__INJECT=false`. Recording and lesson promotion still run, so
the graph keeps growing, and `muninn search` plus all skills still work. This is
**not** the same as `MUNINN_DISABLE=1`, which makes every hook a silent no-op —
nothing is recorded at all.

## Installing a second, isolated instance

If the user already runs muninn and wants a separate one — testing a release, or
a second graph — do not touch the existing install. Isolate all four of these:

```sh
# 1. binary: keep it OFF PATH, call it by absolute path.
#    install.sh also takes an undocumented --name, so a second binary can sit
#    beside the first without overwriting it:
#      install.sh --prefix ~/muninn-test/bin --name muninn-test
--prefix ~/muninn-test/bin

# 2. graph: its own stack dir, hence its own container and volume
muninn stack init --dir ~/muninn-test/stack

# 3. Claude Code: its own config dir
muninn install --claude-dir ~/muninn-test/claude

# 4. launch a Claude Code that uses only the test install
CLAUDE_CONFIG_DIR=~/muninn-test/claude \
MUNINN_SERVER__URL= \
MUNINN_NEO4J__URI=neo4j://127.0.0.1:7687 \
MUNINN_NEO4J__PASSWORD=<from the test stack .env> \
claude
```

`MUNINN_SERVER__URL=` (empty) forces local mode, overriding a client-mode config
file without editing it. Env beats the config file, so the test instance ignores
the user's main settings.

Watch for port collisions: if their main stack or a host Ollama already binds
7687/11434, start only the services you need (`docker compose up -d neo4j`) and
point the test config at the existing Ollama.

## Things not to do

- Do not add `--yes` to work around a missing terminal.
- Do not overwrite an existing `config.toml`, `settings.json`, or stack `.env`.
  The password in `.env` is baked into the neo4j volume on first start; rotating
  it locks the user out of their own graph.
- Do not run `muninn schema init` against a graph you did not just create.
- Do not put a second binary earlier on `PATH` than an existing install.
