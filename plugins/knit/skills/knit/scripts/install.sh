#!/usr/bin/env bash
# Knit MCP installer for Claude Code, Codex, Cursor and Antigravity (Linux and macOS).
#
#   bash install.sh [--agents claude,codex,cursor,antigravity|all] [--region eu]
#                   [--instructions | --no-instructions] [--uninstall]
#
# What it does:
#   1. Makes (or reuses) your Knit trial identity and keeps it in ~/.knit/identity (owner-only).
#   2. Adds the "knit-mcp" MCP server to each agent you have, with the identity sent as the
#      X-Knit-Client-Id header on every request.
#   3. Only with --instructions: adds a short Knit block to the agent's global CLAUDE.md / AGENTS.md.
#
# It makes no network requests. The trial account itself is created by the server the first time
# the agent calls a Knit tool. No API key is needed.
set -euo pipefail

MCP_NAME="knit-mcp"
REGION="eu"
AGENTS="all"
INSTRUCTIONS="ask"        # yes | no | ask
UNINSTALL=0

die()  { printf 'knit install: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --agents)          [ $# -ge 2 ] || die "--agents needs a value"; AGENTS="$2"; shift 2 ;;
    --agents=*)        AGENTS="${1#*=}"; shift ;;
    --region)          [ $# -ge 2 ] || die "--region needs a value"; REGION="$2"; shift 2 ;;
    --region=*)        REGION="${1#*=}"; shift ;;
    --instructions)    INSTRUCTIONS="yes"; shift ;;
    --no-instructions) INSTRUCTIONS="no"; shift ;;
    --uninstall)       UNINSTALL=1; shift ;;
    -h|--help)         sed -n '2,15p' "$0"; exit 0 ;;
    *)                 die "unknown option: $1 (try --help)" ;;
  esac
done

# One table maps a region to its MCP URL. Only eu exists for now; add a line per new region.
# KNIT_MCP_URL overrides it (for testing against another server).
case "$REGION" in
  eu) MCP_URL="https://integrations.getknit.dev/mcp" ;;
  *)  die "region '$REGION' is not available yet. Only 'eu' is supported for now." ;;
esac
MCP_URL="${KNIT_MCP_URL:-$MCP_URL}"

KNIT_DIR="${HOME}/.knit"
ID_FILE="${KNIT_DIR}/identity"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
CODEX_DIR="${CODEX_HOME:-${HOME}/.codex}"
CURSOR_DIR="${HOME}/.cursor"
GEMINI_DIR="${HOME}/.gemini"                         # Antigravity (IDE and CLI) share ${GEMINI_DIR}/config/mcp_config.json
TOKEN_RE="^idn_${REGION}_[0-9a-f]{16}\\.[A-Za-z0-9_-]{20,128}\$"

# ---------------------------------------------------------------------------------- which agents
want() { case ",${AGENTS}," in *,all,*|*,"$1",*) return 0 ;; *) return 1 ;; esac; }
explicit() { [ "$AGENTS" != "all" ]; }

for a in $(printf '%s' "$AGENTS" | tr ',' ' '); do
  case "$a" in all|claude|codex|cursor|antigravity) ;; *) die "unknown agent '$a' (use claude, codex, cursor, antigravity or all)" ;; esac
done

has_claude() { command -v claude >/dev/null 2>&1; }
has_codex()  { command -v codex  >/dev/null 2>&1 || [ -d "$CODEX_DIR" ]; }
has_cursor() { command -v cursor >/dev/null 2>&1 || [ -d "$CURSOR_DIR" ]; }
has_antigravity() {
  command -v antigravity >/dev/null 2>&1 || command -v agy >/dev/null 2>&1 \
    || [ -d "${GEMINI_DIR}/config" ] || [ -d "${GEMINI_DIR}/antigravity-ide" ] || [ -d "${GEMINI_DIR}/antigravity-cli" ]
}

# ------------------------------------------------------------------------------------- identity
random_hex() { head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
random_secret() {
  if command -v base64 >/dev/null 2>&1; then
    head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=\n'
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

ensure_identity() {
  mkdir -p "$KNIT_DIR"; chmod 700 "$KNIT_DIR"
  if [ -f "$ID_FILE" ]; then
    TOKEN="$(tr -d ' \r\n' < "$ID_FILE")"
    if printf '%s' "$TOKEN" | grep -Eq "$TOKEN_RE"; then
      note "Reusing your Knit identity from $ID_FILE"
      return
    fi
    mv "$ID_FILE" "${ID_FILE}.invalid.$(date +%s)"
    note "The old identity file was not valid for region '$REGION'; moved it aside and making a new one"
  fi
  TOKEN="idn_${REGION}_$(random_hex).$(random_secret)"
  printf '%s\n' "$TOKEN" | grep -Eq "$TOKEN_RE" || die "could not generate a valid identity (is /dev/urandom available?)"
  ( umask 077; printf '%s\n' "$TOKEN" > "$ID_FILE" )
  chmod 600 "$ID_FILE"
  note "Made a new Knit identity and saved it to $ID_FILE"
}

# ------------------------------------------------------------------------- managed text blocks
# strip_block FILE START END : remove the lines from START through END (inclusive) from FILE.
strip_block() {
  [ -f "$1" ] || return 0
  awk -v s="$2" -v e="$3" 'index($0, s) {skip=1} !skip {print} index($0, e) {skip=0}' "$1" > "$1.knit.tmp"
  mv "$1.knit.tmp" "$1"
}

# put_block FILE START END TEXT : replace (or add at the end) the managed block in FILE.
put_block() {
  local file="$1" start="$2" end="$3" text="$4"
  mkdir -p "$(dirname "$file")"; [ -f "$file" ] || : > "$file"
  strip_block "$file" "$start" "$end"
  { [ -s "$file" ] && printf '\n'; printf '%s\n%s\n%s\n' "$start" "$text" "$end"; } >> "$file"
}

INSTR_START="<!-- knit-mcp:start -->"
INSTR_END="<!-- knit-mcp:end -->"
INSTR_TEXT='## Knit
For any task that takes an action in the user'"'"'s third-party business apps (HRIS, payroll, CRM, ERP, accounting and more),
such as reading or changing employees, invoices or contacts, do it through the `knit-mcp` MCP server: check
`list_supported_apps`, then use `execute_api` (in code you write, use the curl from `include_curl` / `dry_run`).
Do not call those apps'"'"' APIs directly and do not build authentication yourself. You can work out the request from your
own knowledge of the app; only the doing goes through Knit. If the app is not supported, tell the user.'

ask_instructions() {
  case "$INSTRUCTIONS" in yes) return 0 ;; no) return 1 ;; esac
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Add a short Knit note to your global CLAUDE.md / AGENTS.md so agents prefer Knit for app tasks? [y/N] '
    read -r reply || reply=""
    case "$reply" in y|Y|yes|YES) return 0 ;; esac
  fi
  return 1
}

# ----------------------------------------------------------------------------------- per agent
install_claude() {
  if has_claude; then
    claude mcp remove "$MCP_NAME" --scope user >/dev/null 2>&1 || true
    claude mcp add --scope user --transport http "$MCP_NAME" "$MCP_URL" --header "X-Knit-Client-Id: ${TOKEN}" >/dev/null
    note "Claude Code: added $MCP_NAME (user scope)"
  else
    explicit && note "Claude Code: the 'claude' command was not found. Run this once it is installed:"
    explicit && note "  claude mcp add --scope user --transport http $MCP_NAME $MCP_URL --header \"X-Knit-Client-Id: \$(cat ~/.knit/identity)\""
    explicit || return 0
  fi
  if [ "$DO_INSTR" = 1 ]; then
    put_block "${CLAUDE_DIR}/CLAUDE.md" "$INSTR_START" "$INSTR_END" "$INSTR_TEXT"
    note "Claude Code: added the Knit note to ${CLAUDE_DIR}/CLAUDE.md"
  fi
}

CODEX_START="# >>> knit-mcp >>>"
CODEX_END="# <<< knit-mcp <<<"

install_codex() {
  has_codex || { explicit && note "Codex: not found, skipped"; return 0; }
  local cfg="${CODEX_DIR}/config.toml"
  mkdir -p "$CODEX_DIR"; [ -f "$cfg" ] || : > "$cfg"
  strip_block "$cfg" "$CODEX_START" "$CODEX_END"
  if grep -Fq "[mcp_servers.${MCP_NAME}]" "$cfg"; then
    note "Codex: $cfg already has its own [mcp_servers.${MCP_NAME}] entry; left it alone"
  else
    { [ -s "$cfg" ] && printf '\n'
      printf '%s\n[mcp_servers.%s]\nurl = "%s"\nhttp_headers = { "X-Knit-Client-Id" = "%s" }\n%s\n' \
        "$CODEX_START" "$MCP_NAME" "$MCP_URL" "$TOKEN" "$CODEX_END"; } >> "$cfg"
    chmod 600 "$cfg" 2>/dev/null || true
    note "Codex: added $MCP_NAME to $cfg"
  fi
  if [ "$DO_INSTR" = 1 ]; then
    put_block "${CODEX_DIR}/AGENTS.md" "$INSTR_START" "$INSTR_END" "$INSTR_TEXT"
    note "Codex: added the Knit note to ${CODEX_DIR}/AGENTS.md"
  fi
}

# json_merge FILE URL_KEY : add/replace mcpServers["knit-mcp"] in an agent's MCP JSON file (python3, else jq).
# URL_KEY is the field that holds the server address: "url" for Cursor, "serverUrl" for Antigravity.
# The other servers in the file are kept as they are.
json_merge() {
  local file="$1" urlkey="$2"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$MCP_NAME" "$MCP_URL" "$TOKEN" "$urlkey" <<'PY'
import json, os, sys
path, name, url, token, urlkey = sys.argv[1:6]
data = {}
if os.path.exists(path) and os.path.getsize(path):
    with open(path) as f:
        data = json.load(f)
data.setdefault("mcpServers", {})[name] = {urlkey: url, "headers": {"X-Knit-Client-Id": token}}
with open(path, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
PY
  elif command -v jq >/dev/null 2>&1; then
    local src="$file"; [ -s "$file" ] || { src="$file.knit.empty"; echo '{}' > "$src"; }
    jq --arg n "$MCP_NAME" --arg u "$MCP_URL" --arg t "$TOKEN" --arg k "$urlkey" \
      '.mcpServers = ((.mcpServers // {}) + {($n): {($k): $u, headers: {"X-Knit-Client-Id": $t}}})' "$src" > "$file.knit.tmp"
    mv "$file.knit.tmp" "$file"; rm -f "$file.knit.empty"
  else
    return 1
  fi
}

# json_remove FILE : remove mcpServers["knit-mcp"] from an agent's MCP JSON file (needs python3).
json_remove() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$1" "$MCP_NAME" <<'PY'
import json, sys
path, name = sys.argv[1:3]
with open(path) as f:
    data = json.load(f)
data.get("mcpServers", {}).pop(name, None)
with open(path, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
PY
}

install_cursor() {
  has_cursor || { explicit && note "Cursor: not found, skipped"; return 0; }
  local cfg="${CURSOR_DIR}/mcp.json"
  mkdir -p "$CURSOR_DIR"
  if json_merge "$cfg" url; then
    chmod 600 "$cfg" 2>/dev/null || true
    note "Cursor: added $MCP_NAME to $cfg"
  else
    note "Cursor: could not update $cfg (it needs python3 or jq, or the file is not valid JSON). Add this under \"mcpServers\":"
    note "  \"$MCP_NAME\": { \"url\": \"$MCP_URL\", \"headers\": { \"X-Knit-Client-Id\": \"<contents of ~/.knit/identity>\" } }"
  fi
}

install_antigravity() {
  has_antigravity || { explicit && note "Antigravity: not found, skipped"; return 0; }
  local cfg="${GEMINI_DIR}/config/mcp_config.json"
  mkdir -p "${GEMINI_DIR}/config"
  if json_merge "$cfg" serverUrl; then
    chmod 600 "$cfg" 2>/dev/null || true
    note "Antigravity: added $MCP_NAME to $cfg"
  else
    note "Antigravity: could not update $cfg (it needs python3 or jq, or the file is not valid JSON). Add this under \"mcpServers\":"
    note "  \"$MCP_NAME\": { \"serverUrl\": \"$MCP_URL\", \"headers\": { \"X-Knit-Client-Id\": \"<contents of ~/.knit/identity>\" } }"
  fi
}

# ------------------------------------------------------------------------------------ uninstall
uninstall_all() {
  if has_claude; then claude mcp remove "$MCP_NAME" --scope user >/dev/null 2>&1 && note "Claude Code: removed $MCP_NAME" || true; fi
  strip_block "${CLAUDE_DIR}/CLAUDE.md" "$INSTR_START" "$INSTR_END"
  if [ -f "${CODEX_DIR}/config.toml" ]; then strip_block "${CODEX_DIR}/config.toml" "$CODEX_START" "$CODEX_END"; note "Codex: removed $MCP_NAME"; fi
  strip_block "${CODEX_DIR}/AGENTS.md" "$INSTR_START" "$INSTR_END"
  if [ -f "${CURSOR_DIR}/mcp.json" ]; then json_remove "${CURSOR_DIR}/mcp.json" && note "Cursor: removed $MCP_NAME"; fi
  if [ -f "${GEMINI_DIR}/config/mcp_config.json" ]; then json_remove "${GEMINI_DIR}/config/mcp_config.json" && note "Antigravity: removed $MCP_NAME"; fi
  note "Left $ID_FILE in place so the same trial account can be used again. Delete ~/.knit to forget it."
}

# ------------------------------------------------------------------------------------------ run
printf 'Knit MCP installer (region: %s)\n' "$REGION"

if [ "$UNINSTALL" = 1 ]; then
  uninstall_all
  exit 0
fi

DO_INSTR=0
ask_instructions && DO_INSTR=1

ensure_identity
want claude && install_claude
want codex  && install_codex
want cursor && install_cursor
want antigravity && install_antigravity

printf '\nDone. Restart your agent (or reconnect MCP servers) so it picks up "%s".\n' "$MCP_NAME"
printf 'Your trial identity is in %s. Keep it private: it is how your Knit trial account is found.\n' "$ID_FILE"
