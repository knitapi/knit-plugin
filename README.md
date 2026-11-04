# Knit for coding agents

Lets Claude Code, Codex, Antigravity and Cursor take actions in your third-party business apps (HRIS, payroll, CRM,
ERP, accounting) through Knit's MCP server. No API key: you get a free trial identity (500 calls, 30 days).

## Install

| Agent | How | Commands |
|---|---|---|
| Claude Code | plugin | `/plugin marketplace add knitapi/knit-plugin` then `/plugin install knit@knit` |
| Codex | plugin | `codex plugin marketplace add knitapi/knit-plugin`, then install **knit** from `/plugins` |
| Antigravity | plugin | `agy plugin install https://github.com/knitapi/knit-plugin` (CLI), or `/plugin install <path>` inside the CLI |
| Cursor | script | see below |

The plugins only ship the skill and the installer scripts. The first time a task involves an app, the skill
asks before running the installer, which is what adds the `knit-mcp` server to that agent. Afterwards restart the agent
(or reload its MCP servers) and ask again.

### Cursor (script)

    git clone https://github.com/knitapi/knit-plugin
    bash knit-plugin/plugins/knit/skills/knit/scripts/install.sh --agents cursor

Windows:

    powershell -ExecutionPolicy Bypass -File knit-plugin\plugins\knit\skills\knit\scripts\install.ps1 -Agents cursor

Restart Cursor afterwards.

### Any agent, by hand

    bash plugins/knit/skills/knit/scripts/install.sh --agents claude,codex,cursor,antigravity
    powershell -ExecutionPolicy Bypass -File plugins\knit\skills\knit\scripts\install.ps1 -Agents claude,codex,cursor,antigravity

Options: `--agents` (claude, codex, cursor, antigravity or all; default all that are found), `--instructions` (also add a
short Knit note to the global CLAUDE.md / AGENTS.md), `--uninstall`. Region defaults to `eu`, the only one accepted for now.

## What the installer writes

- `~/.knit/identity`: your trial identity (`idn_eu_<id>.<secret>`), owner-only. Reused on every run, so one trial covers
  every agent on the machine.
- Claude Code: `claude mcp add --scope user ...` with the `X-Knit-Client-Id` header.
- Codex: a marked block in `~/.codex/config.toml` (`[mcp_servers.knit-mcp]`, `http_headers`).
- Cursor: an entry in `~/.cursor/mcp.json` (`url`, `headers`).
- Antigravity (IDE and CLI): an entry in `~/.gemini/config/mcp_config.json` (`serverUrl`, `headers`).
- With `--instructions`: a marked block in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.

It makes no network requests. The server creates the trial account the first time a Knit tool is called.

## Layout

    .claude-plugin/marketplace.json          Claude Code marketplace (repo root is the marketplace)
    .agents/plugins/marketplace.json         Codex marketplace
    .antigravity-plugin/plugin.json          Antigravity plugin at the repo root (points at plugins/knit/skills)
    plugins/knit/
      .claude-plugin/plugin.json             Claude Code plugin manifest
      .codex-plugin/plugin.json              Codex plugin manifest
      .antigravity-plugin/plugin.json        Antigravity manifest, for installing plugins/knit directly
      skills/knit/SKILL.md                   asks the user, then runs the installer for the agent it is in
      skills/knit/scripts/install.sh         Linux / macOS installer
      skills/knit/scripts/install.ps1        Windows installer

## Updating

- Claude Code: `/plugin update knit`.
- Codex: `codex plugin marketplace upgrade`, then `codex plugin upgrade knit`.
- Antigravity: run `agy plugin uninstall knit`, then install it again.
- Re-running the installer is safe: it reuses the identity and rewrites its own config entries and marked blocks only.

## Uninstalling

Remove the MCP server from every agent with `bash install.sh --uninstall` (it leaves `~/.knit/identity` so the
same trial can be used again; delete `~/.knit` to forget it). Without the script:

- Claude Code: `claude mcp remove knit-mcp --scope user`, and `/plugin uninstall knit@knit` for the plugin.
- Codex: delete the `knit-mcp` block from `~/.codex/config.toml`, and remove the plugin with `codex plugin remove knit`.
- Antigravity: delete the `knit-mcp` entry from `~/.gemini/config/mcp_config.json`, and `agy plugin uninstall knit`.
- Cursor: delete the `knit-mcp` entry from `~/.cursor/mcp.json`.
