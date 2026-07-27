#!/usr/bin/env bash
# install.sh: one-command install for muninn — download, verify, set up the local
# stack, wire Claude Code.
#
# usage:  curl -fsSL https://raw.githubusercontent.com/scottlarkin/muninn-release/main/install.sh | bash
#         curl -fsSL .../install.sh | bash -s -- --yes --no-stack
#
# Design notes, because a curl|sh script is a trust ask and should be readable:
#
#   * Prompts are read from /dev/tty, not stdin. Under `curl | bash` stdin IS the
#     download pipe, so `read` would consume script bytes or hang. With no tty at
#     all we refuse to touch Docker or ~/.claude unless --yes was passed.
#   * The binary is moved to its FINAL location before `muninn install` runs.
#     muninn bakes the absolute path of the running binary into the hook commands
#     it writes, so installing from a temp dir would produce hooks pointing at a
#     file we then delete — and hooks fail silently by design (exit 0 always), so
#     nothing would report it.
#   * The checksum is verified and a mismatch aborts. Shipping checksums and not
#     checking them is theatre.
#   * Re-running is safe: every step detects existing state rather than failing.
set -uo pipefail

REPO="scottlarkin/muninn-release"
# BIN_NAME is the member inside the archive; CMD_NAME is what we install it as.
# --name changes the latter so a second install can sit beside an existing one
# without overwriting it. Deliberately undocumented in --help: it exists for
# testing a release against a working setup, not as a supported configuration.
# Note it does NOT isolate config — every name still reads
# ~/.config/muninn/config.toml unless you also pass --config to the binary.
BIN_NAME="muninn"
CMD_NAME="muninn"

ASSUME_YES=0
WANT_VERSION=""
LOCAL_FILE=""
PREFIX=""
DO_STACK=1
DO_CLAUDE=1
STACK_DIR="$HOME/.config/muninn/stack"
CONFIG_PATH="$HOME/.config/muninn/config.toml"

# ---------------------------------------------------------------------------
# Output. Colour only when attached to a terminal and NO_COLOR is unset, so
# piping to a file or a CI log stays clean.
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_DIM=$'\033[2m'
  C_B=$'\033[1m'
  C_OK=$'\033[32m'
  C_WARN=$'\033[33m'
  C_ERR=$'\033[31m'
  C_OFF=$'\033[0m'
else
  C_DIM=""
  C_B=""
  C_OK=""
  C_WARN=""
  C_ERR=""
  C_OFF=""
fi

say() { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s%s%s\n' "$C_B" "$C_OFF" "$C_B" "$*" "$C_OFF"; }
ok() { printf '  %sok%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %swarn%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
die() {
  printf '\n  %serror%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2
  exit 1
}

# banner draws the raven and wordmark.
#
# The bird is Braille (U+2800), which is the only thing in a terminal with enough
# effective resolution to read as an actual raven rather than a smudge — each cell
# carries 8 sub-pixels. It needs a UTF-8 locale AND a font with Braille coverage;
# most terminal fonts have it, but set MUNINN_NO_ART=1 to skip the art entirely if
# yours does not. Non-UTF-8 locales get a plain ASCII bird instead of mojibake.
banner() {
  if [ -n "${MUNINN_NO_ART:-}" ]; then
    printf '  %smuninn%s - persistent memory for coding agents\n' "$C_B" "$C_OFF"
    return
  fi
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8* | *utf8* | *UTF8* | *utf-8*)
    printf '%s' "$C_B"
    cat <<'ART'
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⡀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣰⣜⣽⣦⡄⣎
⠀⡀⣦⡀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢦⣻⣿⣿⣿⣿⡇
⡀⠹⡪⣿⣾⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠐⢦⣝⣿⣿⣿⣿⠁
⠘⠷⣾⣿⣿⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⢐⣿⣾⣿⣿⣿⠏⠀
⠠⢥⣴⣾⣿⣿⣿⣿⣿⣿⣷⡄⠀⠀⢀⣲⣿⣿⣿⣿⠟⠀⠀
⠀⠀⢂⣩⣵⢿⣿⣿⣿⣿⣿⣿⣄⢠⣾⣿⣿⣿⣯⣥⡀⠀⠀
⠀⠀⠀⠠⠤⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡀⠀
⠀⠀⠀⠀⠀⠺⢯⣿⣿⢿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠀⠱⠑⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣾⣿⣿⣿⣿⡿⠛⠁⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⢀⣴⡿⣿⣿⡿⠻⣯⠀⠧⢀⣀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠉⠀⠈⠈⠀⠀⠀⣵⢦⠈⠿⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠀⠀⠀⠀⠀⠀⠀⠀
ART
    printf '%s' "$C_OFF"
    printf '%s' "$C_B"
    cat <<'ART'
  █▀▄▀█ █  █ █▄ █ █ █▄ █ █▄ █
  █ ▀ █ █▄▄█ █ ▀█ █ █ ▀█ █ ▀█
ART
    printf '%s' "$C_OFF"
    ;;
  *)
    printf '%s' "$C_B"
    cat <<'ART'
      ___
    <(o )___
     ( ._> /
      `---'
   m u n i n n
ART
    printf '%s' "$C_OFF"
    ;;
  esac
  printf '  %spersistent memory for coding agents%s\n' "$C_DIM" "$C_OFF"
}

usage() {
  cat <<'EOF'
usage: install.sh [options]

  --yes             assume yes; required when there is no terminal to prompt on
  --version TAG     install a specific release (default: latest)
  --file PATH       install from a local .tar.gz instead of downloading
  --prefix DIR      install the binary here (default: /usr/local/bin, else ~/.local/bin)
  --stack-dir DIR   where to write the docker compose stack (default ~/.config/muninn/stack)
  --no-stack        skip Docker: do not write or start the neo4j + Ollama stack
  --no-claude       skip writing Claude Code hooks and skills into ~/.claude
  --help            show this and exit

Re-running is safe; existing state is detected rather than overwritten.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  --yes | -y) ASSUME_YES=1 ;;
  --version)
    WANT_VERSION="${2:?--version needs a tag}"
    shift
    ;;
  --file)
    LOCAL_FILE="${2:?--file needs a path}"
    shift
    ;;
  --prefix)
    PREFIX="${2:?--prefix needs a directory}"
    shift
    ;;
  --stack-dir)
    STACK_DIR="${2:?--stack-dir needs a directory}"
    shift
    ;;
  --no-stack) DO_STACK=0 ;;
  --no-claude) DO_CLAUDE=0 ;;
  # Undocumented: install under a different command name (see the note above).
  --name)
    CMD_NAME="${2:?--name needs a value}"
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# ask: yes/no via the terminal, NOT stdin (see the header). Returns 1 when there
# is no tty and --yes was not given, so callers can skip that step rather than
# guess consent.
# ---------------------------------------------------------------------------
ask() {
  [ "$ASSUME_YES" = 1 ] && return 0
  if [ ! -r /dev/tty ]; then
    return 1
  fi
  printf '\n  %s [y/N] ' "$1" >/dev/tty
  local reply=""
  read -r reply </dev/tty || return 1
  case "$reply" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# interactive reports whether we can prompt at all. Without a terminal the wizard
# is skipped entirely and defaults are used — announced, never assumed silently.
interactive() { [ "$ASSUME_YES" = 0 ] && [ -r /dev/tty ]; }

# ask_choice <prompt> <default-index> <label...> -> echoes the chosen index
ask_choice() {
  local prompt="$1" default="$2"
  shift 2
  local n=$#
  printf '\n  %s%s%s\n' "$C_B" "$prompt" "$C_OFF" >/dev/tty
  local i=1
  for label in "$@"; do
    if [ "$i" = "$default" ]; then
      printf '    %s) %s %s(default)%s\n' "$i" "$label" "$C_DIM" "$C_OFF" >/dev/tty
    else
      printf '    %s) %s\n' "$i" "$label" >/dev/tty
    fi
    i=$((i + 1))
  done
  local reply=""
  while :; do
    printf '  choice [%s]: ' "$default" >/dev/tty
    read -r reply </dev/tty || {
      echo "$default"
      return
    }
    [ -z "$reply" ] && {
      echo "$default"
      return
    }
    case "$reply" in
    *[!0-9]*) ;;
    *) if [ "$reply" -ge 1 ] && [ "$reply" -le "$n" ]; then
      echo "$reply"
      return
    fi ;;
    esac
    printf '  %s1-%s please%s\n' "$C_WARN" "$n" "$C_OFF" >/dev/tty
  done
}

# ask_value <prompt> <default> -> echoes the answer (default when empty)
ask_value() {
  local prompt="$1" default="${2:-}" reply=""
  if [ -n "$default" ]; then
    printf '  %s [%s]: ' "$prompt" "$default" >/dev/tty
  else
    printf '  %s: ' "$prompt" >/dev/tty
  fi
  read -r reply </dev/tty || reply=""
  [ -z "$reply" ] && reply="$default"
  echo "$reply"
}

# ask_secret <prompt> -> echoes the answer without echoing keystrokes
ask_secret() {
  local reply=""
  printf '  %s: ' "$1" >/dev/tty
  stty -echo 2>/dev/null </dev/tty
  read -r reply </dev/tty || reply=""
  stty echo 2>/dev/null </dev/tty
  printf '\n' >/dev/tty
  echo "$reply"
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

banner

# ---------------------------------------------------------------------------
# 1. Platform
# ---------------------------------------------------------------------------
step "Checking platform"
need curl
need tar
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
  die "need sha256sum or shasum to verify the download"

case "$(uname -s)" in
Darwin) OS="darwin" ;;
Linux) OS="linux" ;;
*) die "unsupported OS: $(uname -s). muninn ships for macOS and Linux." ;;
esac
case "$(uname -m)" in
arm64 | aarch64) ARCH="arm64" ;;
x86_64 | amd64) ARCH="amd64" ;;
*) die "unsupported architecture: $(uname -m)" ;;
esac
PLATFORM="${OS}_${ARCH}"
ok "$PLATFORM"

# ---------------------------------------------------------------------------
# 2. Resolve the version. Asset filenames embed the tag, so /releases/latest/
# download/<asset> cannot be used — resolve the tag from the redirect first.
# ---------------------------------------------------------------------------
if [ -n "$LOCAL_FILE" ]; then
  VERSION="local"
else
step "Finding the latest release"
if [ -n "$WANT_VERSION" ]; then
  VERSION="$WANT_VERSION"
else
  VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/${REPO}/releases/latest" 2>/dev/null | sed 's#.*/tag/##')
  [ -n "$VERSION" ] && [ "$VERSION" != "latest" ] ||
    die "could not resolve the latest release; pass --version vX.Y.Z"
fi
ok "$VERSION"
fi

# ---------------------------------------------------------------------------
# 3. Download and verify
# ---------------------------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ -n "$LOCAL_FILE" ]; then
  # --file installs a tarball you already have: a local build, an artifact pulled
  # from CI, or a mirrored release. Everything after extraction is identical, so
  # this exercises the real install path — which is the point, since the download
  # is the one step that cannot be tested before the release repo is public.
  step "Installing from $LOCAL_FILE"
  [ -f "$LOCAL_FILE" ] || die "no such file: $LOCAL_FILE"
  cp "$LOCAL_FILE" "$TMP/local.tar.gz" || die "could not read $LOCAL_FILE"
  ok "$(wc -c <"$TMP/local.tar.gz" | tr -d ' ') bytes"
  # No checksum: there is no published digest for a file you built yourself, and
  # inventing one here would only verify the copy we just made.
  warn "checksum not verified for a local file"
  tar -xzf "$TMP/local.tar.gz" -C "$TMP" || die "could not extract $LOCAL_FILE"
  [ -f "$TMP/$BIN_NAME" ] || die "archive did not contain a $BIN_NAME binary"
else
ASSET="muninn_${VERSION}_${PLATFORM}.tar.gz"
# MUNINN_RELEASE_BASE overrides where artifacts are fetched from: an internal
# mirror, or a file:// directory. It is also the only way to exercise this script
# end to end before the release repo is public, since anonymous asset downloads
# from a private repo 404.
BASE="${MUNINN_RELEASE_BASE:-https://github.com/${REPO}/releases/download/${VERSION}}"

step "Downloading $ASSET"
curl -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET" ||
  die "download failed: $BASE/$ASSET"
ok "$(wc -c <"$TMP/$ASSET" | tr -d ' ') bytes"

if curl -fsSL -o "$TMP/checksums.txt" "$BASE/checksums.txt" 2>/dev/null; then
  want=$(grep " ${ASSET}\$" "$TMP/checksums.txt" | awk '{print $1}')
  got=$(sha256_of "$TMP/$ASSET")
  if [ -z "$want" ]; then
    warn "no checksum listed for $ASSET"
  elif [ "$want" != "$got" ]; then
    die "checksum mismatch for $ASSET
    expected $want
    got      $got
  Refusing to install. Try again, and report this if it persists."
  else
    ok "sha256 verified"
  fi
else
  warn "checksums.txt unavailable; skipping verification"
fi

tar -xzf "$TMP/$ASSET" -C "$TMP" || die "could not extract $ASSET"
[ -f "$TMP/$BIN_NAME" ] || die "archive did not contain a $BIN_NAME binary"
fi

# ---------------------------------------------------------------------------
# 4. Install the binary to its FINAL location (see the header — muninn install
# bakes this path into the hooks it writes).
# ---------------------------------------------------------------------------
step "Installing the binary"
SUDO=""
if [ -n "$PREFIX" ]; then
  DEST="$PREFIX"
  mkdir -p "$DEST" || die "cannot create $DEST"
elif [ -w /usr/local/bin ] 2>/dev/null; then
  DEST="/usr/local/bin"
elif [ -r /dev/tty ] && command -v sudo >/dev/null 2>&1; then
  DEST="/usr/local/bin"
  SUDO="sudo"
  say "  ${C_DIM}/usr/local/bin needs sudo; you may be prompted${C_OFF}"
else
  DEST="$HOME/.local/bin"
  mkdir -p "$DEST"
fi

$SUDO install -m 0755 "$TMP/$BIN_NAME" "$DEST/$CMD_NAME" ||
  die "could not install to $DEST (try --prefix ~/.local/bin)"
MUNINN="$DEST/$CMD_NAME"
ok "$MUNINN ($("$MUNINN" version 2>/dev/null || echo '?'))"

# HINT is what the closing instructions tell the user to type. When the install
# directory is not on PATH, a bare command name is not copy-pasteable and reads as
# a broken install — so name the absolute path instead.
HINT="$CMD_NAME"
case ":$PATH:" in
*":$DEST:"*) ;;
*)
  HINT="$MUNINN"
  warn "$DEST is not on your PATH."
  say  "         Either use the full path below, or add it to your shell profile:"
  say  "           export PATH=\"$DEST:\$PATH\""
  ;;
esac

# ---------------------------------------------------------------------------
# 5. Dependency wizard.
#
# muninn needs three things: a neo4j graph, an embedding endpoint, and an LLM for
# lesson distillation. Each can be run by us in Docker, already be running
# locally, or live on a remote provider. The right answer differs per person —
# plenty of people already have Ollama on 11434 or a neo4j they use for something
# else — so ask instead of assuming, and never start a container that would
# collide with one they already run.
#
# The embedding DIMENSION matters here in particular: it is baked into the neo4j
# vector indexes when `schema init` runs, and cannot be changed afterwards without
# a fresh database. A remote model with a different dim has to be configured
# before that point, which is why this wizard runs before the schema step.
#
# With no terminal (piped, no --yes) we take the all-Docker defaults and print
# them rather than silently guessing.
# ---------------------------------------------------------------------------
NEO_MODE=docker
NEO_URI="neo4j://127.0.0.1:7687"
NEO_USER="neo4j"
NEO_PASS=""
EMB_MODE=docker
EMB_URL="http://127.0.0.1:11434"
EMB_KEY=""
EMB_MODEL=""
EMB_DIM=""
LLM_MODE=ollama
LLM_URL="http://127.0.0.1:11434"
LLM_KEY=""
LLM_MODEL=""
NEED_NEO4J=0
NEED_OLLAMA=0

# An API key already in the environment is the strongest hint that hosted
# distillation is wanted; reference the variable rather than copying the secret
# into a config file.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  LLM_MODE=anthropic
  LLM_KEY="env:ANTHROPIC_API_KEY"
fi

if [ "$DO_STACK" = 0 ]; then
  NEO_MODE=existing
  EMB_MODE=existing
fi

if interactive; then
  step "How should muninn reach its dependencies?"

  case "$(ask_choice "Memory graph — neo4j" 1 \
    "Run it for me in Docker" \
    "I already have neo4j running" \
    "Use a remote neo4j (Aura, or self-hosted elsewhere)")" in
  1) NEO_MODE=docker ;;
  2)
    NEO_MODE=existing
    NEO_URI=$(ask_value "neo4j URI" "neo4j://127.0.0.1:7687")
    NEO_USER=$(ask_value "neo4j username" "neo4j")
    NEO_PASS=$(ask_secret "neo4j password")
    ;;
  3)
    NEO_MODE=remote
    NEO_URI=$(ask_value "neo4j URI" "neo4j+s://xxxxxxxx.databases.neo4j.io")
    NEO_USER=$(ask_value "neo4j username" "neo4j")
    NEO_PASS=$(ask_secret "neo4j password")
    ;;
  esac

  case "$(ask_choice "Embeddings — how memory is indexed and searched" 1 \
    "Run Ollama for me in Docker (pulls ~2GB of models)" \
    "I already have Ollama running" \
    "Use a remote OpenAI-compatible endpoint")" in
  1) EMB_MODE=docker ;;
  2)
    EMB_MODE=existing
    EMB_URL="http://127.0.0.1:$(ask_value "Ollama port" "11434")"
    say "  ${C_DIM}muninn needs nomic-embed-text and a code embedding model there.${C_OFF}"
    say "  ${C_DIM}Pull them with: ollama pull nomic-embed-text${C_OFF}"
    ;;
  3)
    EMB_MODE=remote
    EMB_URL=$(ask_value "embeddings base URL" "https://api.openai.com")
    EMB_KEY=$(ask_secret "embeddings API key")
    EMB_MODEL=$(ask_value "embedding model" "text-embedding-3-small")
    EMB_DIM=$(ask_value "embedding dimensions (baked into the index; cannot change later)" "1536")
    ;;
  esac

  llm_default=2
  [ "$LLM_MODE" = anthropic ] && llm_default=1
  case "$(ask_choice "LLM — distils lessons from your sessions" "$llm_default" \
    "Anthropic API (best quality)" \
    "Local model via Ollama (free, private, slower)" \
    "A remote OpenAI-compatible endpoint" \
    "Skip for now")" in
  1)
    LLM_MODE=anthropic
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
      LLM_KEY="env:ANTHROPIC_API_KEY"
      ok "using \$ANTHROPIC_API_KEY from your environment"
    else
      LLM_KEY=$(ask_secret "Anthropic API key")
    fi
    ;;
  2)
    LLM_MODE=ollama
    case "$EMB_MODE" in
    docker) LLM_URL="http://127.0.0.1:11434" ;;
    existing) LLM_URL="$EMB_URL" ;;
    remote) LLM_URL="http://127.0.0.1:$(ask_value "Ollama port for the LLM" "11434")" ;;
    esac
    LLM_MODEL=$(ask_value "local model" "qwen2.5-coder:7b")
    ;;
  3)
    LLM_MODE=openai
    LLM_URL=$(ask_value "LLM base URL" "https://api.openai.com")
    LLM_KEY=$(ask_secret "LLM API key")
    LLM_MODEL=$(ask_value "model" "gpt-4o-mini")
    ;;
  4) LLM_MODE=skip ;;
  esac
else
  step "Dependency setup"
  say "  ${C_DIM}No terminal to ask on — using defaults. Re-run interactively to change them.${C_OFF}"
fi

[ "$NEO_MODE" = docker ] && NEED_NEO4J=1
[ "$EMB_MODE" = docker ] && NEED_OLLAMA=1

# --no-stack is authoritative. The wizard still asks about each dependency (the
# answers shape the config either way), so without this a Docker choice would
# start containers despite the flag that exists to prevent exactly that.
if [ "$DO_STACK" = 0 ] && { [ "$NEED_NEO4J" = 1 ] || [ "$NEED_OLLAMA" = 1 ]; }; then
  warn "--no-stack given, so no containers will be started."
  say  "         Point the config at endpoints you already run, or re-run without --no-stack."
  NEED_NEO4J=0
  NEED_OLLAMA=0
  # Report the modes as "existing" too, so the plan below describes what will
  # actually happen rather than the Docker setup that was asked for and refused.
  [ "$NEO_MODE" = docker ] && NEO_MODE=existing
  [ "$EMB_MODE" = docker ] && EMB_MODE=existing
fi

step "Plan"
case "$NEO_MODE" in
docker) say "  graph        Docker (neo4j on 127.0.0.1:7687)" ;;
existing) say "  graph        existing at $NEO_URI" ;;
remote) say "  graph        remote at $NEO_URI" ;;
esac
case "$EMB_MODE" in
docker) say "  embeddings   Docker (Ollama on 127.0.0.1:11434)" ;;
existing) say "  embeddings   existing Ollama at $EMB_URL" ;;
remote) say "  embeddings   $EMB_URL ($EMB_MODEL, dim $EMB_DIM)" ;;
esac
case "$LLM_MODE" in
anthropic) say "  llm          Anthropic API" ;;
ollama) say "  llm          Ollama at $LLM_URL (${LLM_MODEL:-qwen2.5-coder:7b})" ;;
openai) say "  llm          $LLM_URL (${LLM_MODEL:-gpt-4o-mini})" ;;
skip) say "  llm          none — lessons will not be distilled until configured" ;;
esac

# ---------------------------------------------------------------------------
# 6. Start only the containers actually needed. Starting an Ollama when one is
# already bound to 11434 would just fail on the port, so the wizard's answers
# decide the service list.
# ---------------------------------------------------------------------------
COMPOSE="$STACK_DIR/docker-compose.yml"
STACK_STARTED=0
SERVICES=""
[ "$NEED_NEO4J" = 1 ] && SERVICES="$SERVICES neo4j"
[ "$NEED_OLLAMA" = 1 ] && SERVICES="$SERVICES ollama ollama-init"

if [ -z "$SERVICES" ]; then
  step "No containers needed"
  ok "using your existing/remote services"
elif ! command -v docker >/dev/null 2>&1; then
  step "Docker not found"
  warn "cannot start the services muninn needs. Install Docker, then:"
  say "         $MUNINN stack init && docker compose -f $COMPOSE up -d$SERVICES"
else
  step "Starting:$SERVICES"
  if [ -f "$COMPOSE" ]; then
    ok "compose file already at $COMPOSE"
  else
    "$MUNINN" stack init --dir "$STACK_DIR" --yes >/dev/null || die "stack init failed"
    ok "wrote $COMPOSE"
  fi
  if [ "$NEED_OLLAMA" = 1 ]; then
    say "  ${C_DIM}First start pulls ~2GB of embedding models (plus the LLM if local).${C_OFF}"
  fi
  if ask "Start$SERVICES with docker compose now?"; then
    # shellcheck disable=SC2086  # deliberate word-split: SERVICES is a service list
    docker compose -f "$COMPOSE" up -d $SERVICES || die "docker compose up failed"
    STACK_STARTED=1
    if [ "$NEED_NEO4J" = 1 ]; then
      printf '  waiting for neo4j'
      state=""
      for _ in $(seq 1 60); do
        state=$(docker inspect -f '{{.State.Health.Status}}' muninn-neo4j 2>/dev/null || echo "")
        [ "$state" = "healthy" ] && break
        printf '.'
        sleep 2
      done
      printf '\n'
      [ "$state" = "healthy" ] && ok "neo4j healthy" ||
        warn "neo4j not healthy yet (${state:-unknown}); schema init may fail"
    fi
  else
    warn "not started. Run when ready:"
    say "         docker compose -f $COMPOSE up -d$SERVICES"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Write the config from the wizard's answers.
#
# For a Docker graph the password comes from the .env `stack init` generated —
# nothing in the binary wires that up, so the installer does it. An existing
# config is never overwritten; we print what to add instead, because clobbering
# someone's settings to save them a paste is not a trade worth making.
# ---------------------------------------------------------------------------
step "Configuration"
if [ "$NEO_MODE" = docker ] && [ -f "$STACK_DIR/.env" ]; then
  NEO_PASS=$(grep '^MUNINN_NEO4J_PASSWORD=' "$STACK_DIR/.env" 2>/dev/null | cut -d= -f2-)
fi

render_config() {
  printf '# muninn configuration, written by install.sh.\n'
  printf '# Every setting not listed here has a default; `muninn config show` prints them all.\n\n'
  printf '[neo4j]\n'
  printf 'uri = "%s"\n' "$NEO_URI"
  printf 'username = "%s"\n' "$NEO_USER"
  printf 'password = "%s"\n' "$NEO_PASS"

  if [ "$EMB_MODE" = remote ]; then
    printf '\n[embed]\nprovider = "openai"\n'
    printf 'base_url = "%s"\n' "$EMB_URL"
    printf 'api_key = "%s"\n' "$EMB_KEY"
    # Both spaces get the same model: a remote endpoint rarely serves a
    # code-specific embedding model. Split them later if yours does.
    printf '\n[embed.spaces.text]\nmodel = "%s"\ndim = %s\nasymmetric = true\n' "$EMB_MODEL" "$EMB_DIM"
    printf '\n[embed.spaces.code]\nmodel = "%s"\ndim = %s\nasymmetric = false\n' "$EMB_MODEL" "$EMB_DIM"
  elif [ "$EMB_URL" != "http://127.0.0.1:11434" ]; then
    printf '\n[embed]\nbase_url = "%s"\n' "$EMB_URL"
  fi

  case "$LLM_MODE" in
  anthropic)
    printf '\n[llm]\nprovider = "anthropic"\n'
    printf 'anthropic_api_key = "%s"\n' "$LLM_KEY"
    ;;
  ollama)
    printf '\n[llm]\nprovider = "ollama"\n'
    printf 'base_url = "%s"\n' "$LLM_URL"
    [ -n "$LLM_MODEL" ] && printf 'local_model = "%s"\n' "$LLM_MODEL"
    ;;
  openai)
    printf '\n[llm]\nprovider = "openai"\n'
    printf 'base_url = "%s"\n' "$LLM_URL"
    printf 'api_key = "%s"\n' "$LLM_KEY"
    [ -n "$LLM_MODEL" ] && printf 'model_haiku = "%s"\n' "$LLM_MODEL"
    ;;
  skip)
    printf '\n# No LLM configured: lessons are not distilled. Set llm.provider when ready.\n'
    ;;
  esac
}

if [ -f "$CONFIG_PATH" ]; then
  warn "$CONFIG_PATH already exists — leaving it alone."
  say "         To use the settings chosen above, merge this in:"
  say ""
  render_config | sed 's/^/           /'
  say ""
else
  mkdir -p "$(dirname "$CONFIG_PATH")"
  render_config >"$CONFIG_PATH"
  chmod 600 "$CONFIG_PATH"
  ok "wrote $CONFIG_PATH"
fi

# ---------------------------------------------------------------------------
# 8. Schema. This is the installer's only write to a graph, so it is gated:
# creating indexes in a database someone else is using is not ours to assume.
# ---------------------------------------------------------------------------
step "Graph schema"
run_schema=0
if [ "$STACK_STARTED" = 1 ] && [ "$NEED_NEO4J" = 1 ]; then
  run_schema=1 # we just created this database
elif [ "$NEO_MODE" != docker ] && [ -f "$CONFIG_PATH" ]; then
  ask "Create muninn's indexes in $NEO_URI?" && run_schema=1
fi

if [ "$run_schema" = 1 ]; then
  if "$MUNINN" schema init 2>&1 | tail -1; then
    ok "schema ready"
  else
    warn "schema init failed. Retry with: $MUNINN schema init"
  fi
else
  say "  ${C_DIM}Skipped. When your graph is reachable:${C_OFF}"
  say "         $MUNINN schema init"
fi

# 9. Claude Code wiring
# ---------------------------------------------------------------------------
if [ "$DO_CLAUDE" = 0 ]; then
  step "Skipping Claude Code setup (--no-claude)"
else
  step "Claude Code integration"
  say "  ${C_DIM}Writes 13 skills and 7 hooks into ~/.claude. Existing settings are${C_OFF}"
  say "  ${C_DIM}merged, not replaced, after a timestamped backup.${C_OFF}"
  if ask "Install the Claude Code skills and hooks?"; then
    "$MUNINN" install --yes || warn "muninn install failed; run it manually"
  else
    warn "skipped. Run when ready:"
    say "         $MUNINN install"
  fi
fi

# ---------------------------------------------------------------------------
# 10. Verify and hand over
# ---------------------------------------------------------------------------
step "Checking the install"
"$MUNINN" doctor || warn "some checks failed — see above"

step "Done"
say "  Restart Claude Code so the hooks load."
say ""
say "  Then index a repository:"
say "    ${C_B}cd /path/to/your/project && $HINT index${C_OFF}"
say ""
say "  ${C_DIM}Ask memory anything:     $HINT search \"how did we do auth\"${C_OFF}"
say "  ${C_DIM}Turn off auto-injection: set recall.inject = false${C_OFF}"
say "  ${C_DIM}Disable entirely:        export MUNINN_DISABLE=1${C_OFF}"
say ""
