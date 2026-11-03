# Knit for coding agents

Lets Claude Code, Codex and Cursor take actions in your third-party business apps (HRIS, payroll, CRM, ERP,
accounting) through Knit's MCP server. No API key: you get a free trial identity (500 calls, 30 days).

## Layout

    .claude-plugin/marketplace.json          marketplace entry (repo root is the marketplace)
    plugins/knit/
      .claude-plugin/plugin.json             plugin manifest
      skills/knit/SKILL.md                   asks the user, then runs the installer
      skills/knit/scripts/install.sh         Linux / macOS installer
      skills/knit/scripts/install.ps1        Windows installer

## Install

Claude Code, through the plugin:

    /plugin marketplace add <github-org>/<repo>
    /plugin install knit@knit

The plugin only ships the skill and the scripts. The first time a task involves an app, the skill asks
before running the installer, which is what adds the `knit-mcp` server.

Any agent, by hand:

    bash plugins/knit/skills/knit/scripts/install.sh --agents claude,codex,cursor
    powershell -ExecutionPolicy Bypass -File plugins\knit\skills\knit\scripts\install.ps1 -Agents claude,codex,cursor

Options: `--agents` (claude, codex, cursor or all; default all that are found), `--instructions` (also add a short Knit
note to the global CLAUDE.md / AGENTS.md), `--uninstall`. Region defaults to `eu`, the only one accepted for now.

## What the installer writes

- `~/.knit/identity`: your trial identity (`idn_eu_<id>.<secret>`), owner-only. Reused on every run.
- Claude Code: `claude mcp add --scope user ...` with the `X-Knit-Client-Id` header.
- Codex: a marked block in `~/.codex/config.toml` (`[mcp_servers.knit-mcp]`, `http_headers`).
- Cursor: an entry in `~/.cursor/mcp.json` (`url`, `headers`).
- With `--instructions`: a marked block in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.

It makes no network requests. The server creates the trial account the first time a Knit tool is called.

## Updating

`/plugin update knit` replaces the skill and scripts. Re-running the installer is safe: it reuses the identity and
rewrites its own config entries and marked blocks only.
