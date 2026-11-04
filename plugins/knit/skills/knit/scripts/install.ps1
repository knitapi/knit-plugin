<#
.SYNOPSIS
  Knit MCP installer for Claude Code, Codex, Cursor and Antigravity (Windows PowerShell 5.1 or PowerShell 7).

.DESCRIPTION
  1. Makes (or reuses) your Knit trial identity and keeps it in ~\.knit\identity.
  2. Adds the "knit-mcp" MCP server to each agent you have, sending the identity as the
     X-Knit-Client-Id header on every request.
  3. Places the Knit skill file for each agent that reads skills (skip with -NoSkill).
  4. Adds a short Knit note to each agent's global instructions file so the agent prefers Knit for
     work in third-party business apps (skip with -NoInstructions):
       Claude Code  ~\.claude\CLAUDE.md
       Codex        ~\.codex\AGENTS.md
       Antigravity  ~\.gemini\GEMINI.md
       Cursor       has no such file (its all-projects rules live in the app), so the note is printed for you to paste.

  It prints what it is about to change and then does it; it never stops to ask.

  -Uninstall removes what this installer added: the knit-mcp server entries, the skill files and the notes.
  ~\.knit\identity is kept, so you can still claim the trial account later.

  It makes no network requests. The trial account itself is created by the server the first time the
  agent calls a Knit tool. No API key is needed.

  Uses the Knit cloud address by default. Set the KNIT_MCP_URL environment variable to use another one (for testing).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -Agents claude,cursor

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall

.EXAMPLE
  # Without downloading a file (the script is self-contained):
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/knitapi/knit-plugin/main/plugins/knit/skills/knit/scripts/install.ps1))) -Agents codex
#>
[CmdletBinding()]
param(
  [string[]]$Agents = @("all"),
  [string]$Region = "eu",
  [switch]$Instructions,      # kept for older commands; adding the note is now the default
  [switch]$NoInstructions,
  [switch]$NoSkill,
  [switch]$Uninstall,
  [switch]$KeepIdentity,      # kept for older commands; the identity is always kept now
  [Alias("y")][switch]$Yes
)
$ErrorActionPreference = "Stop"

$McpName = "knit-mcp"

function Fail($msg) { Write-Error "knit install: $msg"; exit 1 }
function Note($msg) { Write-Host "  $msg" }

# Agents this run changed (their MCP entry was added or removed), so the last message can say which ones to restart.
$script:DoneAgents = @()
function Done-Agent($name) { if ($script:DoneAgents -notcontains $name) { $script:DoneAgents += $name } }
function Restart-Text($name) {
  switch ($name) {
    "claude"      { return "Claude Code: restart it, or run /mcp inside it and reconnect knit-mcp" }
    "codex"       { return "Codex: quit and start a new Codex session, then run /mcp to check" }
    "cursor"      { return "Cursor: restart Cursor (or toggle knit-mcp in Settings > MCP)" }
    "antigravity" { return "Antigravity: reload MCP servers (/mcp in the CLI, refresh in the IDE) or restart it" }
  }
}
function Show-Restart($purpose) {
  if (-not $script:DoneAgents.Count) { Write-Host ""; Write-Host "Nothing was changed, so nothing needs restarting."; return }
  Write-Host ""
  Write-Host "Restart ${purpose}:"
  foreach ($a in $script:DoneAgents) { Write-Host "  - $(Restart-Text $a)" }
}

# One table maps a region to its MCP URL. Only eu exists for now; add a line per new region.
# KNIT_MCP_URL overrides it (for testing against another server).
switch ($Region) {
  "eu"    { $McpUrl = "https://integrations.getknit.dev/mcp" }
  default { Fail "region '$Region' is not available yet. Only 'eu' is supported for now." }
}
if ($env:KNIT_MCP_URL) { $McpUrl = $env:KNIT_MCP_URL }
if ($McpUrl -notmatch '^https?://') { Fail "KNIT_MCP_URL must start with http:// or https:// (got '$McpUrl')" }

$AgentList = @($Agents | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($a in $AgentList) {
  if (@("all", "claude", "codex", "cursor", "antigravity") -notcontains $a) { Fail "unknown agent '$a' (use claude, codex, cursor, antigravity or all)" }
}
$Explicit = -not ($AgentList -contains "all")
function Wants($name) { return ($AgentList -contains "all") -or ($AgentList -contains $name) }

$KnitDir   = Join-Path $HOME ".knit"
$IdFile    = Join-Path $KnitDir "identity"
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$CodexDir  = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$CursorDir = Join-Path $HOME ".cursor"
$GeminiDir = Join-Path $HOME ".gemini"                      # Antigravity IDE and CLI read from here
$AntigravityCfg = Join-Path (Join-Path $GeminiDir "config") "mcp_config.json"
$TokenRe   = "^idn_$Region`_[0-9a-f]{16}\.[A-Za-z0-9_-]{20,128}$"

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Read-Text($path) { if (Test-Path $path) { return [System.IO.File]::ReadAllText($path) } else { return "" } }
function Write-Text($path, $text) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, $text, $Utf8NoBom)
}
function Restrict-File($path) {
  try { & icacls $path /inheritance:r /grant:r "$($env:USERNAME):(R,W)" 2>&1 | Out-Null } catch { }
}

function Has-Claude { return [bool](Get-Command claude -ErrorAction SilentlyContinue) }
function Has-Codex  { return [bool](Get-Command codex -ErrorAction SilentlyContinue) -or (Test-Path $CodexDir) }
function Has-Cursor { return [bool](Get-Command cursor -ErrorAction SilentlyContinue) -or (Test-Path $CursorDir) }
function Has-Antigravity {
  return [bool](Get-Command antigravity -ErrorAction SilentlyContinue) -or [bool](Get-Command agy -ErrorAction SilentlyContinue) `
    -or (Test-Path (Join-Path $GeminiDir "config")) -or (Test-Path (Join-Path $GeminiDir "antigravity-ide")) -or (Test-Path (Join-Path $GeminiDir "antigravity-cli"))
}

# ------------------------------------------------------------------------------------- identity
function New-Identity {
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $idBytes = New-Object byte[] 8
  $secretBytes = New-Object byte[] 32
  $rng.GetBytes($idBytes); $rng.GetBytes($secretBytes); $rng.Dispose()
  $hex = -join ($idBytes | ForEach-Object { $_.ToString("x2") })
  $secret = [Convert]::ToBase64String($secretBytes).Replace("+", "-").Replace("/", "_").TrimEnd("=")
  return "idn_$Region`_$hex.$secret"
}

function Ensure-Identity {
  if (-not (Test-Path $KnitDir)) { New-Item -ItemType Directory -Path $KnitDir -Force | Out-Null }
  if (Test-Path $IdFile) {
    $existing = (Read-Text $IdFile).Trim()
    if ($existing -match $TokenRe) {
      Note "Reusing your Knit identity from $IdFile"
      return $existing
    }
    Move-Item $IdFile "$IdFile.invalid.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Note "The old identity file was not valid for region '$Region'; moved it aside and making a new one"
  }
  $token = New-Identity
  if ($token -notmatch $TokenRe) { Fail "could not generate a valid identity" }
  Write-Text $IdFile ($token + "`n")
  Restrict-File $IdFile
  Note "Made a new Knit identity and saved it to $IdFile"
  return $token
}

# --------------------------------------------------------------------------- managed text blocks
function Remove-Block($file, $start, $end) {
  if (-not (Test-Path $file)) { return }
  $text = Read-Text $file
  if (-not $text.Contains($start)) { return }
  $pattern = "(?s)\r?\n?" + [regex]::Escape($start) + ".*?" + [regex]::Escape($end) + "\r?\n?"
  Write-Text $file ([regex]::Replace($text, $pattern, ""))
}

function Set-Block($file, $start, $end, $body) {
  Remove-Block $file $start $end
  $text = Read-Text $file
  if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" }
  if ($text.Length -gt 0) { $text += "`n" }
  Write-Text $file ($text + "$start`n$body`n$end`n")
}

# Delete the file if nothing but whitespace is left (for example a file this installer created).
function Remove-IfBlank($file) {
  if ((Test-Path $file) -and -not ((Read-Text $file) -match '\S')) {
    Remove-Item -Force $file
    Note "Removed the now-empty $file"
  }
}

# Remove the managed block from the file, say so, and delete the file if it is then empty.
function Drop-Block($file, $start, $end, $label) {
  if ((Test-Path $file) -and (Read-Text $file).Contains($start)) {
    Remove-Block $file $start $end
    Note "${label}: removed the Knit note from $file"
  }
  Remove-IfBlank $file
}

$InstrStart = "<!-- knit-mcp:start -->"
$InstrEnd   = "<!-- knit-mcp:end -->"
$InstrText  = @'
## Knit
Knit is how you take actions in the user's third-party business apps (HRIS, payroll, CRM, ERP, accounting and more),
such as reading or changing employees, invoices, contacts or deals in apps like BambooHR, Workday, Xero or Salesforce.
For any task like that, use the `knit-mcp` MCP server first:
1. `list_supported_apps` finds the app, and `find_apis_for_use_case` gives the documented request.
2. `execute_api` makes the call. In code you write, use the curl from `include_curl` / `dry_run`.
3. `create_integration_link` gives the user a link to connect their account when the app is not connected yet.
Do not call those apps' APIs directly and do not build authentication yourself. You can work out the request from your
own knowledge of the app; only the doing goes through Knit. If the app is not supported, tell the user.
'@

# ------------------------------------------------------------------------------------ skill file
# The skill is kept inside this script so it also works when the script is run straight from a URL.
# Claude Code reads ~\.claude\skills, Codex and Cursor read ~\.agents\skills, Antigravity reads ~\.gemini\config\skills.
# -NoSkill skips this.
$SkillName = "knit-mcp"
$SkillMark = "<!-- installed by the Knit installer -->"
$ClaudeSkillsDir = Join-Path $ClaudeDir "skills"
$AgentsRoot = Join-Path $HOME ".agents"
$AgentsSkillsDir = Join-Path $AgentsRoot "skills"
$AntigravitySkillsDir = Join-Path (Join-Path $GeminiDir "config") "skills"
$SkillsDone = @()
$SkillTemplate = @'
---
name: knit-mcp
description: Take actions in the user's third-party business apps (HRIS, payroll, CRM, ERP, accounting, e.g. BambooHR, Workday, Xero, Salesforce) through Knit's MCP server. Use when a task reads or changes data in such an app.
---
<!-- installed by the Knit installer -->

# Knit

Knit runs API calls for the user's third-party business apps and handles their sign-in, token refresh, call logging and issue tracking. For any task that takes an action in such an app, do it through the `knit-mcp` tools. Do not call the app's API directly and do not build authentication yourself. You can work out the request from your own knowledge of the app; only the doing goes through Knit.

## If the Knit tools are not available

The Knit installer has already added the `knit-mcp` server to this agent, but agents load MCP servers when they start. Ask the user to restart the agent (or reload its MCP servers) and then ask again. Do not make another identity.

## How to take an action

1. `list_supported_apps` finds the exact app id. If the app is not listed, tell the user, and offer `request_integration`.
2. `find_apis_for_use_case` gives the documented request and response. Skip it if you already know the endpoint.
3. `get_app_integration_info` is the read-only reference for the app's base URL(s) and how users connect their account. It returns documentation, never credentials, and you do not need it to authenticate (Knit does that). Use it to find the base URL when you need `execute_api`'s `path`: strip the base from the documented URL, tenant and service parts included (for Workday SOAP the base already ends in `/service/<tenant>`), and never put `{placeholders}` in `path`.
4. `execute_api` runs the call. Prefer a read-only GET first when exploring.
5. In code you write, use the curl from `include_curl` or `dry_run`. It calls `__KNIT_BASE_URL__` and reads the identity from `~/.knit/identity`.
6. No `integration_id` for the app yet? `create_integration_link` returns a link for the user to open and connect their account. Keep working on everything that needs no connection while they do.

`get_account` is free and shows how many trial calls are left.

## Rules

- Do not print or paste the contents of `~/.knit/identity` unless the user asks. It is how their trial account is found.
- To keep the trial account, the user emails support@getknit.dev with the `org_id` from `get_account` and their identity. Never send it anywhere else.
- If the trial has ended, say so; do not set up another identity to get around it.
'@

# Write PARENT\knit-mcp\SKILL.md. A file there that this installer did not make is left alone.
function Put-Skill($parent, $label) {
  if ($NoSkill) { return }
  $dir = Join-Path $parent $SkillName
  $file = Join-Path $dir "SKILL.md"
  if ($script:SkillsDone -contains $parent) { Note "${label}: reads the Knit skill already placed in $file"; return }
  $script:SkillsDone += $parent
  if ((Test-Path $file) -and -not (Read-Text $file).Contains($SkillMark)) {
    Note "${label}: $file already exists and was not made by this installer; left it alone"
    return
  }
  $base = if ($McpUrl.EndsWith("/mcp")) { $McpUrl.Substring(0, $McpUrl.Length - 4) } else { $McpUrl }
  $text = ($SkillTemplate -replace "`r`n", "`n").Replace("__KNIT_BASE_URL__", $base)
  Write-Text $file ($text.TrimEnd("`n") + "`n")
  Note "${label}: added the Knit skill to $file"
}

# Remove PARENT\knit-mcp if this installer made it (and PARENT itself if that leaves it empty).
function Remove-Skill($parent, $label) {
  $dir = Join-Path $parent $SkillName
  $file = Join-Path $dir "SKILL.md"
  if ((Test-Path $file) -and (Read-Text $file).Contains($SkillMark)) {
    Remove-Item -Force $file
    if (-not (Get-ChildItem -Force $dir)) { Remove-Item -Force $dir }
    Note "${label}: removed the Knit skill from $dir"
  }
  if ((Test-Path $parent) -and -not (Get-ChildItem -Force $parent)) { Remove-Item -Force $parent }
}

# --------------------------------------------------------------------------------- per agent
function Invoke-Claude([string[]]$ClaudeArgs) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { & claude @ClaudeArgs 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
}

function Install-Claude($token) {
  if (Has-Claude) {
    Invoke-Claude @("mcp", "remove", $McpName, "--scope", "user")
    Invoke-Claude @("mcp", "add", "--scope", "user", "--transport", "http", $McpName, $McpUrl, "--header", "X-Knit-Client-Id: $token")
    Note "Claude Code: added $McpName (user scope)"; Done-Agent "claude"
  } elseif ($Explicit) {
    Note "Claude Code: the 'claude' command was not found. Run this once it is installed:"
    Note "  claude mcp add --scope user --transport http $McpName $McpUrl --header `"X-Knit-Client-Id: <contents of ~\.knit\identity>`""
  } else { return }
  Put-Skill $ClaudeSkillsDir "Claude Code"
  if (-not $NoInstructions) {
    Set-Block (Join-Path $ClaudeDir "CLAUDE.md") $InstrStart $InstrEnd $InstrText
    Note "Claude Code: added the Knit note to $(Join-Path $ClaudeDir 'CLAUDE.md')"
  }
}

$CodexStart = "# >>> knit-mcp >>>"
$CodexEnd   = "# <<< knit-mcp <<<"

function Install-Codex($token) {
  if (-not (Has-Codex)) { if ($Explicit) { Note "Codex: not found, skipped" }; return }
  $cfg = Join-Path $CodexDir "config.toml"
  Remove-Block $cfg $CodexStart $CodexEnd
  $text = Read-Text $cfg
  if ($text.Contains("[mcp_servers.$McpName]")) {
    Note "Codex: $cfg already has its own [mcp_servers.$McpName] entry; left it alone"
  } else {
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" }
    if ($text.Length -gt 0) { $text += "`n" }
    $block = "$CodexStart`n[mcp_servers.$McpName]`nurl = `"$McpUrl`"`nhttp_headers = { `"X-Knit-Client-Id`" = `"$token`" }`n$CodexEnd`n"
    Write-Text $cfg ($text + $block)
    Restrict-File $cfg
    Note "Codex: added $McpName to $cfg"; Done-Agent "codex"
  }
  Put-Skill $AgentsSkillsDir "Codex"
  if (-not $NoInstructions) {
    Set-Block (Join-Path $CodexDir "AGENTS.md") $InstrStart $InstrEnd $InstrText
    Note "Codex: added the Knit note to $(Join-Path $CodexDir 'AGENTS.md')"
  }
}

# Add or replace mcpServers[knit-mcp] in an agent's MCP JSON file, keeping its other servers.
# $urlKey is the field holding the address: "url" for Cursor, "serverUrl" for Antigravity.
function Set-JsonServer($label, $cfg, $urlKey, $token) {
  try {
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    $raw = Read-Text $cfg
    $data = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { New-Object PSObject }
    if (-not $data.PSObject.Properties["mcpServers"]) {
      $data | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue (New-Object PSObject)
    }
    $entry = [PSCustomObject]@{ $urlKey = $McpUrl; headers = [PSCustomObject]@{ "X-Knit-Client-Id" = $token } }
    $data.mcpServers | Add-Member -NotePropertyName $McpName -NotePropertyValue $entry -Force
    Write-Text $cfg (($data | ConvertTo-Json -Depth 20) + "`n")
    Restrict-File $cfg
    Note "${label}: added $McpName to $cfg"; Done-Agent ($label.ToLower())
  } catch {
    Note "${label}: could not update $cfg (is it valid JSON?). Add this under `"mcpServers`":"
    Note "  `"$McpName`": { `"$urlKey`": `"$McpUrl`", `"headers`": { `"X-Knit-Client-Id`": `"<contents of ~\.knit\identity>`" } }"
  }
}

# Remove mcpServers[knit-mcp]; if that leaves the file with nothing in it, delete the file.
function Remove-JsonServer($label, $cfg) {
  if (-not (Test-Path $cfg)) { return }
  try {
    $data = (Read-Text $cfg) | ConvertFrom-Json
    if ($data.mcpServers -and $data.mcpServers.PSObject.Properties[$McpName]) {
      $data.mcpServers.PSObject.Properties.Remove($McpName)
      if (-not @($data.mcpServers.PSObject.Properties).Count) { $data.PSObject.Properties.Remove("mcpServers") }
      if (@($data.PSObject.Properties).Count) { Write-Text $cfg (($data | ConvertTo-Json -Depth 20) + "`n") } else { Remove-Item -Force $cfg }
      Note "${label}: removed $McpName"; Done-Agent ($label.ToLower())
    }
  } catch { Note "${label}: could not update $cfg" }
}

function Install-Cursor($token) {
  if (-not (Has-Cursor)) { if ($Explicit) { Note "Cursor: not found, skipped" }; return }
  Set-JsonServer "Cursor" (Join-Path $CursorDir "mcp.json") "url" $token
  Put-Skill $AgentsSkillsDir "Cursor"
  if (-not $NoInstructions) {
    # Cursor keeps its all-projects rules in the app (Customize > Rules), not in a file the installer can write.
    Note "Cursor: its all-projects rules live in the app, not in a file. To make Cursor prefer Knit everywhere,"
    Note "paste this into Cursor > Customize > Rules (User Rules):"
    ($InstrText -replace "`r`n", "`n").TrimEnd("`n") -split "`n" | ForEach-Object { Write-Host "        $_" }
  }
}

function Install-Antigravity($token) {
  if (-not (Has-Antigravity)) { if ($Explicit) { Note "Antigravity: not found, skipped" }; return }
  Set-JsonServer "Antigravity" $AntigravityCfg "serverUrl" $token
  Put-Skill $AntigravitySkillsDir "Antigravity"
  if (-not $NoInstructions) {
    Set-Block (Join-Path $GeminiDir "GEMINI.md") $InstrStart $InstrEnd $InstrText
    Note "Antigravity: added the Knit note to $(Join-Path $GeminiDir 'GEMINI.md')"
  }
}

# ------------------------------------------------------------------------------------ uninstall
# Removes what this installer added, for the agents selected with -Agents (default: all).
function Uninstall-All {
  if (Wants "claude") {
    if (Has-Claude) { Invoke-Claude @("mcp", "remove", $McpName, "--scope", "user"); Note "Claude Code: removed $McpName"; Done-Agent "claude" }
    Drop-Block (Join-Path $ClaudeDir "CLAUDE.md") $InstrStart $InstrEnd "Claude Code"
    Remove-Skill $ClaudeSkillsDir "Claude Code"
  }
  if (Wants "codex") {
    $cfg = Join-Path $CodexDir "config.toml"
    if ((Test-Path $cfg) -and (Read-Text $cfg).Contains($CodexStart)) {
      Remove-Block $cfg $CodexStart $CodexEnd; Note "Codex: removed $McpName"; Done-Agent "codex"
    }
    Remove-IfBlank $cfg
    Drop-Block (Join-Path $CodexDir "AGENTS.md") $InstrStart $InstrEnd "Codex"
  }
  if (Wants "cursor") { Remove-JsonServer "Cursor" (Join-Path $CursorDir "mcp.json") }
  # Codex and Cursor read the same skill folder, so it only goes when both are being removed.
  if ((Wants "codex") -and (Wants "cursor")) {
    Remove-Skill $AgentsSkillsDir "Codex and Cursor"
    if ((Test-Path $AgentsRoot) -and -not (Get-ChildItem -Force $AgentsRoot)) { Remove-Item -Force $AgentsRoot }
  } elseif ((Wants "codex") -or (Wants "cursor")) {
    if (Test-Path (Join-Path (Join-Path $AgentsSkillsDir $SkillName) "SKILL.md")) {
      Note "Kept the skill in $(Join-Path $AgentsSkillsDir $SkillName) (Codex and Cursor both read it). A full -Uninstall removes it."
    }
  }
  if (Wants "antigravity") {
    Remove-JsonServer "Antigravity" $AntigravityCfg
    Drop-Block (Join-Path $GeminiDir "GEMINI.md") $InstrStart $InstrEnd "Antigravity"
    Remove-Skill $AntigravitySkillsDir "Antigravity"
  }

  # The identity is deliberately left alone: the user may want to claim the trial account later.
  if (Test-Path $IdFile) {
    Note "Kept your Knit identity ($IdFile) so you can still claim the trial account or reinstall with the same one."
  }
}

# ------------------------------------------------------------------------------------------ plan
function Pick-Agents {
  $list = @()
  if ((Wants "claude")      -and ((Has-Claude)      -or $Explicit)) { $list += "claude" }
  if ((Wants "codex")       -and ((Has-Codex)       -or $Explicit)) { $list += "codex" }
  if ((Wants "cursor")      -and ((Has-Cursor)      -or $Explicit)) { $list += "cursor" }
  if ((Wants "antigravity") -and ((Has-Antigravity) -or $Explicit)) { $list += "antigravity" }
  return $list
}

function Show-Agent($label, $mcpText, $skillParent, $noteFile) {
  Write-Host "  $label"
  Write-Host "      - $mcpText"
  if (-not $NoSkill) { Write-Host "      - add the Knit skill to $(Join-Path $skillParent "$SkillName\")" }
  if (-not $NoInstructions) {
    if ($noteFile) { Write-Host "      - add a short Knit note to $noteFile" }
    else { Write-Host "      - print a short Knit note for you to paste into Cursor > Customize > Rules (no file to edit)" }
  }
}

function Show-Plan($planAgents) {
  Write-Host ""
  Write-Host "This will:"
  if (Test-Path $IdFile) { Write-Host "  - reuse your Knit trial identity in $IdFile" }
  else { Write-Host "  - create a Knit trial identity (2,000 calls, 30 days) in $IdFile, readable only by you" }
  Write-Host "  - send that identity to $McpUrl with every request"
  Write-Host ""
  foreach ($a in $planAgents) {
    switch ($a) {
      "claude"      { Show-Agent "Claude Code" "add the knit-mcp server (claude mcp add, user scope)" $ClaudeSkillsDir (Join-Path $ClaudeDir "CLAUDE.md") }
      "codex"       { Show-Agent "Codex" "add a marked knit-mcp block to $(Join-Path $CodexDir 'config.toml')" $AgentsSkillsDir (Join-Path $CodexDir "AGENTS.md") }
      "cursor"      { Show-Agent "Cursor" "add the knit-mcp server to $(Join-Path $CursorDir 'mcp.json')" $AgentsSkillsDir "" }
      "antigravity" { Show-Agent "Antigravity" "add the knit-mcp server to $AntigravityCfg" $AntigravitySkillsDir (Join-Path $GeminiDir "GEMINI.md") }
    }
  }
  Write-Host ""
  Write-Host "It makes no network requests and changes nothing else. Undo it any time with -Uninstall. Leave parts out with"
  Write-Host "-NoInstructions and -NoSkill."
  Write-Host ""
}

# ----------------------------------------------------------------------------------------- run
Write-Host "Knit MCP installer (region: $Region)"

if ($Uninstall) {
  Write-Host ""
  Write-Host "Removing what the Knit installer added (the knit-mcp server entries, the Knit skill files and the Knit notes)."
  Write-Host "Your Knit identity in $IdFile is kept."
  Write-Host ""
  Uninstall-All
  Write-Host ""
  Write-Host "Done."
  Show-Restart "these so they drop `"$McpName`""
  exit 0
}

$planAgents = @(Pick-Agents)
if (-not $planAgents.Count) {
  Write-Host ""
  Write-Host "No supported agent found (Claude Code, Codex, Cursor, Antigravity). Nothing changed."
  Write-Host "Name one to set it up anyway, for example: -Agents codex"
  exit 0
}

Show-Plan $planAgents

$token = Ensure-Identity
foreach ($a in $planAgents) {
  switch ($a) {
    "claude"      { Install-Claude $token }
    "codex"       { Install-Codex $token }
    "cursor"      { Install-Cursor $token }
    "antigravity" { Install-Antigravity $token }
  }
}

Write-Host ""
Write-Host "Done."
Show-Restart "these so they pick up `"$McpName`" (agents load MCP servers when they start)"
Write-Host ""
Write-Host "Your trial identity is in $IdFile. Keep it private: it is how your Knit trial account is found."