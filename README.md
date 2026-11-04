# Knit for coding agents

Lets Claude Code, Codex, Antigravity and Cursor take actions in your third-party business apps (HRIS, payroll, CRM,
ERP, accounting) through Knit's MCP server. No API key: you get a free trial identity (2,000 calls, 30 days).

## Install

One self-contained installer covers all four agents. Run it in your own terminal, outside the agent (that also avoids
agent command sandboxes, which on some Linux machines block commands, e.g. `bwrap: ... Operation not permitted`).
It needs only bash (plus python3 or jq for Cursor and Antigravity) and uses the Knit cloud address by default.

    curl -fsSL https://raw.githubusercontent.com/knitapi/knit-plugin/main/plugins/knit/skills/knit/scripts/install.sh | bash

That sets up every agent it finds (Claude Code, Codex, Cursor, Antigravity). To pick agents:

    curl -fsSL https://raw.githubusercontent.com/knitapi/knit-plugin/main/plugins/knit/skills/knit/scripts/install.sh | bash -s -- --agents claude,codex

Or download it first, read it, then run `bash install.sh`. Restart the agent afterwards.

Before it changes anything, the installer prints a plan (which agents, which files) and then carries on; it never stops to
ask. Leave parts out with `--no-instructions` (the global note) or `--no-skill`.

Another MCP address (for testing): set `KNIT_MCP_URL` for the shell that runs the script, not for `curl`:

    curl -fsSL <url> | KNIT_MCP_URL=http://localhost:8091/mcp bash

Windows (PowerShell):

    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/knitapi/knit-plugin/main/plugins/knit/skills/knit/scripts/install.ps1))) -Agents codex

Options: `--agents` (claude, codex, cursor, antigravity or all; default all that are found), `--no-instructions` (skip the
global note), `--no-skill` (skip the skill file), `--uninstall`. Region defaults to `eu`, the only one
accepted for now.

### Plugins (optional)

Claude Code: `/plugin marketplace add knitapi/knit-plugin` then `/plugin install knit@knit`. The plugin ships the skill;
the first time a task involves an app, it asks, then runs the installer (with `--no-skill`) to add the server.
The repo also carries a Codex plugin (`plugins/knit/.codex-plugin`, marketplace in `.agents/plugins`) and an Antigravity
plugin (`.antigravity-plugin`). The installer is the supported route; a plugin's skill has to run the installer through
the agent's command sandbox, which can fail.

## What the installer writes

- `~/.knit/identity`: your trial identity (`idn_eu_<id>.<secret>`), owner-only. Reused on every run, so one trial covers
  every agent on the machine.
- Claude Code: `claude mcp add --scope user ...` with the `X-Knit-Client-Id` header.
- Codex: a marked block in `~/.codex/config.toml` (`[mcp_servers.knit-mcp]`, `http_headers`).
- Cursor: an entry in `~/.cursor/mcp.json` (`url`, `headers`).
- Antigravity (IDE and CLI): an entry in `~/.gemini/config/mcp_config.json` (`serverUrl`, `headers`).
- The Knit skill (`knit-mcp/SKILL.md`), built into the script. Claude Code: `~/.claude/skills/`. Codex and Cursor:
  `~/.agents/skills/`. Antigravity: `~/.gemini/config/skills/`. A file already there that the installer did not make is
  never overwritten.
- A short Knit note, so the agent knows to use Knit first for tasks in business apps, as a marked block in each agent's
  global instructions file: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`. Cursor has no such file
  (its all-projects rules live in the app), so the installer prints the note for you to paste into
  Cursor > Customize > Rules.

It makes no network requests. The server creates the trial account the first time a Knit tool is called.

## Layout

    .claude-plugin/marketplace.json          Claude Code marketplace (repo root is the marketplace)
    .agents/plugins/marketplace.json         Codex marketplace
    .antigravity-plugin/plugin.json          Antigravity plugin at the repo root (points at plugins/knit/skills)
    plugins/knit/
      .claude-plugin/plugin.json             Claude Code plugin manifest
      .codex-plugin/plugin.json              Codex plugin manifest
      .antigravity-plugin/plugin.json        Antigravity manifest, for installing plugins/knit directly
      skills/knit/SKILL.md                   asks the user, then runs the installer (Claude Code plugin)
      skills/knit/scripts/install.sh         Linux / macOS installer
      skills/knit/scripts/install.ps1        Windows installer

## Updating

- Run the installer again (safe: it reuses the identity and rewrites only its own entries and marked blocks).
- Claude Code plugin: `/plugin update knit`.

## Uninstalling

    curl -fsSL https://raw.githubusercontent.com/knitapi/knit-plugin/main/plugins/knit/skills/knit/scripts/install.sh | bash -s -- --uninstall

This removes the `knit-mcp` entries, the skill files and the notes it added, It never deletes
`~/.knit/identity`, so you can still claim the trial account later (delete `~/.knit` yourself to forget it). With
`--agents x` only those agents are cleaned. Files the installer did not make are never touched. Restart your agents afterwards. For
the Claude Code plugin also run `/plugin uninstall knit@knit`.