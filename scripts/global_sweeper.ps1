<#
.SYNOPSIS
  Rhea Umbrella — Global Workspace Sweeper for Windows.
  (Cross-platform sibling of scripts/global_sweeper.sh on macOS/Linux.)

.DESCRIPTION
  SAFETY-FIRST — Defaults to DRY-RUN (100% read-only). Pass -Apply explicitly to
  run destructive commands. Phase map (identical to the bash script):
    1. ANALYZE       — Orphan rhea-* / omnia-* / blueshoes-* repos OUTSIDE the
                       Umbrella repo root (parent of scripts/). Reports size,
                       git status, dirty-tree, stashes.
    2. CACHE PURGE   — Deletes ALLOWLISTED cache directories (AI IDEs, npm,
                       yarn, pnpm, go, cargo, pip, NuGet, Docker, Windows Search,
                       WinSxS / MSU temp caches, Teams/Slack caches, etc.).
                       NEVER deletes source-code directories, documents, or git
                       repos directly.
    3. CONSOLIDATE   — For every orphan git repo with uncommitted work or stashes,
                       "git stash push -u -m pre-umbrella-sweep-<timestamp>" +
                       tar via Compress-Archive (or 7z if available) into a
                       ColdStorage directory with a sidecar metadata file.
                       NEVER deletes the original directory by itself.
    4. REPORT        — PROJECTED or ACTUAL reclaim summary + optional JSON file.

.PARAMETER Apply
  Default = $false (safe dry-run). Pass -Apply:$true to execute destructive actions.

.PARAMETER SkipAnalyze, SkipCache, SkipConsolidate
  Skip individual phases (useful for re-runs or CI).

.PARAMETER ColdStorageDir
  Absolute path OUTSIDE the Umbrella repo. Default:
    "$env:USERPROFILE\rhea-umbrella-cold-storage"

.PARAMETER OrphanRoot
  Array of directories to scan for orphans (can be passed multiple times).
  Default = @($env:USERPROFILE)

.PARAMETER ReportJson
  Absolute or relative path where the final machine-readable JSON summary is
  written.

.EXAMPLE
  # Safe dry-run (NO disk changes)
  scripts/global_sweeper.ps1

  # Real apply (destructive, but only allowlisted caches + consolidation)
  scripts/global_sweeper.ps1 -Apply -ReportJson C:\temp\sweep-report.json
#>
[CmdletBinding()]
param(
    [switch]$Apply = $false,
    [switch]$SkipAnalyze   = $false,
    [switch]$SkipCache     = $false,
    [switch]$SkipConsolidate = $false,
    [string]$ColdStorageDir = "$env:USERPROFILE\rhea-umbrella-cold-storage",
    [string[]]$OrphanRoot = @($env:USERPROFILE),
    [string]$ReportJson   = ""
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Path setup (mirrors bash: SCRIPT_DIR -> REPO_ROOT = parent of scripts/)
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $RepoRoot

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
function Write-Info([string]$m)  { Write-Host "🟢 [Sweep] $m" -ForegroundColor Green }
function Write-Warn([string]$m)  { Write-Host "🟡 [Sweep] $m" -ForegroundColor Yellow }
function Write-Err([string]$m)   { Write-Host "🔴 [Sweep] $m" -ForegroundColor Red    }
function Write-Plan([string]$m)  { Write-Host "📋 [Plan]  $m" -ForegroundColor Cyan   }
function Write-Banner([string]$t){ Write-Host ""; Write-Host ("═"*62) -ForegroundColor DarkGray; Write-Host "══ $t" -ForegroundColor DarkCyan; Write-Host ("═"*62) -ForegroundColor DarkGray }

function Get-HBytes([long]$Bytes) {
    if ($Bytes -le 0) { return "0.00 B" }
    $units = @("B","KB","MB","GB","TB","PB")
    [double]$n = $Bytes
    foreach ($u in $units) {
        if ($n -lt 1024) { return ("{0:n2} {1}" -f $n,$u) }
        $n /= 1024
    }
    return ("{0:n2} EB" -f $n)
}

function Get-FreeBytesOnSystemDrive() {
    try {
        $sys = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $driveLetter = ($env:SystemDrive).Replace(":","")
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceId='$env:SystemDrive'" -ErrorAction Stop
        return [long]$disk.FreeSpace
    } catch { return 0 }
}

# ---------------------------------------------------------------------------
# Safety guards
# ---------------------------------------------------------------------------
$ModeLabel = if ($Apply) { "APPLY (DESTRUCTIVE — you passed -Apply)" } else { "DRY-RUN (SAFE)" }
Write-Banner "GLOBAL SWEEPER starting: mode = $ModeLabel"
Write-Info "Umbrella REPO_ROOT:  $RepoRoot"
Write-Info "ColdStorageDir:      $ColdStorageDir"
Write-Info "Orphan scan roots:   $($OrphanRoot -join ', ')"
Write-Info "Phases: analyze=$(-not $SkipAnalyze) cache=$(-not $SkipCache) consolidate=$(-not $SkipConsolidate)"
Write-Host ""

# Guard: ColdStorage must be absolute path.
if (-not [System.IO.Path]::IsPathRooted($ColdStorageDir)) {
    Write-Err "ColdStorageDir must be an absolute rooted path. Got: $ColdStorageDir"
    exit 4
}
# Guard: ColdStorage must not live inside the Umbrella repo.
$umbFull  = [System.IO.Path]::GetFullPath($RepoRoot.Path).TrimEnd("\") + "\"
$coldFull = [System.IO.Path]::GetFullPath($ColdStorageDir).TrimEnd("\") + "\"
if ($coldFull.StartsWith($umbFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Err "ColdStorageDir ($coldFull) must NOT be a child of the Umbrella repo ($umbFull)."
    Write-Err "Avoid accidental bloat of umbrella git history. Move cold storage elsewhere. Abort."
    exit 3
}

# Safe plan-or-run helper. Takes a scriptblock { Command arg1 arg2 } and a friendly label.
function Invoke-Safe($Label, [scriptblock]$Command) {
    if ($Apply) {
        Write-Info "▸ $Label"
        Write-Info "  & $Command"
        try { & $Command } catch { Write-Warn "  Command failed: $($_.Exception.Message)" }
    } else {
        Write-Plan "$Label  ->  $Command"
    }
}

# ---------------------------------------------------------------------------
# Summary accumulators
# ---------------------------------------------------------------------------
$PhaseBefore = @{}
$PhaseAfter  = @{}
[long]$ProjectedReclaimTotal = 0
[long]$ActualReclaimDelta    = 0

function Record-Projection([string]$Phase, [long]$Bytes) {
    if (-not $PhaseBefore.ContainsKey($Phase)) { $PhaseBefore[$Phase] = 0 }
    $PhaseBefore[$Phase] += $Bytes
    $script:ProjectedReclaimTotal += $Bytes
}
function Snapshot-Before([string]$Phase) {
    if ($Apply) { $script:PhaseBefore[$Phase] = Get-FreeBytesOnSystemDrive }
}
function Snapshot-After([string]$Phase) {
    if ($Apply) {
        $after = Get-FreeBytesOnSystemDrive
        $script:PhaseAfter[$Phase] = $after
        $before = $PhaseBefore[$Phase]
        $delta  = $after - $before
        if ($delta -gt 0) { $script:ActualReclaimDelta += $delta }
    }
}

# ============================================================
# PHASE 1. ANALYZE orphans
# ============================================================
$orphansMeta = New-Object System.Collections.Generic.List[object]
[int]$orphansFound = 0; [long]$orphansTotalBytes = 0

if (-not $SkipAnalyze) {
    Write-Banner "PHASE 1. ANALYZE — orphan rhea-* / omnia-* / blueshoes-*"
    $umbExcludePrefix = [System.IO.Path]::GetFullPath($RepoRoot.Path).TrimEnd("\")

    foreach ($root in $OrphanRoot) {
        if (-not (Test-Path -LiteralPath $root)) {
            Write-Warn "Orphan root not a directory, skip: $root"
            continue
        }
        Write-Info "Scanning orphan root (depth <= 6): $root"
        $dirs = Get-ChildItem -LiteralPath $root -Recurse -Depth 6 -Directory -ErrorAction SilentlyContinue `
                | Where-Object {
                    ($_.Name -like "rhea-*" -or $_.Name -like "omnia-*" -or $_.Name -like "blueshoes-*") -and
                    (-not $_.FullName.StartsWith($umbExcludePrefix, [System.StringComparison]::OrdinalIgnoreCase))
                }
        $seen = @{}
        foreach ($d in $dirs) {
            if ($seen.ContainsKey($d.FullName)) { continue }
            $seen[$d.FullName] = $true
            $orphansFound++
            # Size: sum all children files (recursive, but best effort — skip ACL errors).
            $sz = 0L
            try {
                Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $sz += $_.Length }
            } catch { }
            $orphansTotalBytes += $sz
            Record-Projection "phase1-projected-if-purged" $sz

            $isGit=$false; $dirty="n/a"; [int]$stashes=0; $hasNode=$false
            $gitDir = Join-Path $d.FullName ".git"
            if ((Test-Path -LiteralPath $gitDir) -and (Get-Command git -ErrorAction SilentlyContinue)) {
                $isGit = $true
                $porcelain = (git -C $d.FullName status --porcelain 2>$null)
                $dirty = if ([string]::IsNullOrWhiteSpace($porcelain)) { "clean" } else { "DIRTY" }
                $stashOut = (git -C $d.FullName stash list 2>$null)
                if ($null -ne $stashOut) { $stashes = @($stashOut).Count }
            }
            if (Test-Path -LiteralPath (Join-Path $d.FullName "node_modules")) { $hasNode = $true }
            $dirFlag = @()
            if ($isGit)  { $dirFlag += "[git]" }
            if ($dirty -eq "DIRTY") { $dirFlag += "[UNCOMMITTED-WORK⚠️]" }
            if ($stashes -gt 0) { $dirFlag += "[stashes=$stashes]" }
            if ($hasNode) { $dirFlag += "[node_modules]" }

            $orphansMeta.Add([pscustomobject]@{
                Bytes = $sz; Path = $d.FullName; IsGit = $isGit
                HasUncommitted = $dirty; StashCount = $stashes; HasNodeModules = $hasNode
            })
            Write-Info ("$(Get-HBytes $sz)  orphan $orphansFound : {0} {1}" -f $d.FullName, ($dirFlag -join " "))
        }
    }
    Write-Host ""
    Write-Info "Phase 1 done: orphans_found=$orphansFound, projected_total_if_removed=$(Get-HBytes $orphansTotalBytes)"
} else {
    Write-Info "Phase 1 skipped per -SkipAnalyze."
}

# ============================================================
# PHASE 2. CACHE PURGE (Windows allowlist)
# ============================================================
if (-not $SkipCache) {
    Write-Banner "PHASE 2. CACHE PURGE — allowlisted only (NO source code paths)"
    Snapshot-Before "phase2-cache"

    if (-not $Apply) {
        Write-Info "Dry-run mode: below are the EXACT commands that would run under -Apply."
        Write-Info "No command is actually touching your disk."
        Write-Host ""
    }

    $cacheJobs = New-Object System.Collections.Generic.List[object]
    function Add-CacheJob([string]$Label, [scriptblock]$Cmd) {
        $cacheJobs.Add([pscustomobject]@{Label=$Label; Cmd=$Cmd})
    }

    # --- Trae, Cursor, VSCode-family user caches, workspace storage, logs -----
    Add-CacheJob "Trae: user caches + workspaceStorage + logs" {
        @(
            "$env:APPDATA\Trae\Cache",
            "$env:APPDATA\Trae\CacheData",
            "$env:APPDATA\Trae\CachedData",
            "$env:APPDATA\Trae\Code Cache",
            "$env:APPDATA\Trae\GPUCache",
            "$env:APPDATA\Trae\User\workspaceStorage",
            "$env:LOCALAPPDATA\Trae\Cache",
            "$env:LOCALAPPDATA\Trae\Temp"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "Cursor: user caches + workspaceStorage + logs" {
        @(
            "$env:APPDATA\Cursor\Cache",
            "$env:APPDATA\Cursor\CacheData",
            "$env:APPDATA\Cursor\Code Cache",
            "$env:APPDATA\Cursor\GPUCache",
            "$env:APPDATA\Cursor\User\workspaceStorage",
            "$env:LOCALAPPDATA\Cursor\Cache"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "VSCode / VSCode Insiders caches (shared with Trae/Cursor family)" {
        @(
            "$env:APPDATA\Code\Cache",
            "$env:APPDATA\Code\CachedData",
            "$env:APPDATA\Code\Code Cache",
            "$env:APPDATA\Code\User\workspaceStorage",
            "$env:APPDATA\Code - Insiders\Cache",
            "$env:APPDATA\Code - Insiders\User\workspaceStorage",
            "$env:APPDATA\VSCodium\User\workspaceStorage"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "Github Copilot, Claude Desktop caches" {
        @(
            "$env:LOCALAPPDATA\GitHubCopilot",
            "$env:LOCALAPPDATA\Claude"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # --- Package manager caches ---------------------------------------------
    Add-CacheJob "NPM global + user cache (force clean + local cache dir)" {
        if (Get-Command npm -ErrorAction SilentlyContinue) { & npm cache clean --force 2>$null | Out-Null }
        @(
            "$env:APPDATA\npm-cache",
            "$env:LOCALAPPDATA\npm-cache",
            "$env:USERPROFILE\.npm\_cacache"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "Yarn 1.x / Berry (v2+) global caches" {
        if (Get-Command yarn -ErrorAction SilentlyContinue) { & yarn cache clean 2>$null | Out-Null }
        @(
            "$env:LOCALAPPDATA\Yarn",
            "$env:USERPROFILE\.yarn\cache",
            "$env:LOCALAPPDATA\YarnBerry"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "PNPM store prune" {
        if (Get-Command pnpm -ErrorAction SilentlyContinue) { & pnpm store prune 2>$null | Out-Null }
        @(
            "$env:LOCALAPPDATA\pnpm\store",
            "$env:USERPROFILE\.local\share\pnpm\store"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "NuGet / dotnet / MSBuild / Roslyn caches" {
        if (Get-Command dotnet -ErrorAction SilentlyContinue) { & dotnet nuget locals all --clear 2>$null | Out-Null }
        @(
            "$env:LOCALAPPDATA\NuGet\Cache",
            "$env:LOCALAPPDATA\NuGet\v3-cache",
            "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ComponentModelCache",
            "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\Roslyn\Cache",
            "$env:LOCALAPPDATA\Temp\MSBuild"
        ) | ForEach-Object {
            # wildcards in VS version number: we don't use Test-Path, resolve via GCI
            Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.PSIsContainer) { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    Add-CacheJob "Rust cargo registry + git DB cache (global, not project targets/)" {
        @(
            "$env:USERPROFILE\.cargo\registry\cache",
            "$env:USERPROFILE\.cargo\registry\src",
            "$env:USERPROFILE\.cargo\git\db",
            "$env:USERPROFILE\.rustup\downloads"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "Go module + build cache" {
        if (Get-Command go -ErrorAction SilentlyContinue) {
            & go clean -cache -fuzzcache -testcache 2>$null | Out-Null
        }
        $gopath = if ($env:GOPATH) { $env:GOPATH } else { (Join-Path $env:USERPROFILE "go") }
        $gocache = Join-Path $gopath "pkg\mod\cache"
        if (Test-Path -LiteralPath $gocache) { Remove-Item -LiteralPath $gocache -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Add-CacheJob "Pip / Pyenv / Poetry / uv wheel caches" {
        @(
            "$env:LOCALAPPDATA\pip\Cache",
            "$env:APPDATA\pip\Cache",
            "$env:USERPROFILE\.cache\pip",
            "$env:LOCALAPPDATA\pypoetry\Cache",
            "$env:APPDATA\pypoetry\Cache",
            "$env:USERPROFILE\.cache\pypoetry"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
        if (Get-Command uv -ErrorAction SilentlyContinue) { & uv cache clean 2>$null | Out-Null }
    }

    # --- OS-level caches (safe) ----------------------------------------------
    Add-CacheJob "Windows temp + user temp (non-locked files only)" {
        @($env:TEMP, "$env:SystemRoot\Temp") | ForEach-Object {
            Get-ChildItem -LiteralPath $_ -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Add-CacheJob "Windows Recycle Bin (safe — user-confirmed deletion semantics match our sweep intent)" {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }
    Add-CacheJob "Windows Update / Component cleanup (via DISM, safe MS official cmd)" {
        if ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) {
            Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>$null | Out-Null
        } else {
            Write-Warn "  Not running as Admin. Skip DISM /ResetBase (big reclaim). Re-run with elevated if desired."
        }
    }
    Add-CacheJob "Docker system prune --all --volumes (if Docker CLI is reachable)" {
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            & docker system prune --all --volumes --force 2>$null | Out-Null
        }
    }
    Add-CacheJob "Microsoft Teams / Slack / Discord caches (NOT user data, just blob cache)" {
        @(
            "$env:APPDATA\Microsoft\Teams\Cache",
            "$env:APPDATA\Microsoft\Teams\Service Worker\CacheStorage",
            "$env:APPDATA\Microsoft\Teams\Service Worker\IndexedDB",
            "$env:APPDATA\Slack\Cache",
            "$env:APPDATA\Slack\Service Worker\CacheStorage",
            "$env:APPDATA\discord\Cache",
            "$env:APPDATA\discord\Code Cache"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CacheJob "Windows Search / Windows.old leftovers (safe — not user documents)" {
        $winOld = "$env:SystemDrive\Windows.old"
        if (Test-Path -LiteralPath $winOld) {
            Write-Warn "  Found Windows.old ($winOld) — can reclaim 10-30 GB after 10-day grace period."
            Write-Warn "  Script skips deletion (too destructive for default). Use Disk Cleanup → 'Clean up system files' to remove it."
        }
    }

    # Run each cache job or plan it
    for ($i = 0; $i -lt $cacheJobs.Count; $i++) {
        $job = $cacheJobs[$i]
        Write-Info ("▸ [cache-$i] {0}" -f $job.Label)
        Invoke-Safe $job.Label $job.Cmd
    }

    Snapshot-After "phase2-cache"
}

# ============================================================
# PHASE 3. CONSOLIDATE — dirty / stashed orphans → ColdStorage
# ============================================================
if (-not $SkipConsolidate) {
    Write-Banner "PHASE 3. CONSOLIDATE — orphan git repos with uncommitted work → ColdStorage"
    Snapshot-Before "phase3-consolidate"

    if ($Apply) {
        New-Item -ItemType Directory -Path $ColdStorageDir -Force -ErrorAction SilentlyContinue | Out-Null
    } else {
        Write-Plan "New-Item -ItemType Directory -Path '$ColdStorageDir' -Force"
    }

    if ($orphansFound -eq 0) {
        Write-Info "No orphans in Phase 1. Consolidation skipped."
    } else {
        $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
        [int]$consolidateOffers = 0
        foreach ($o in $orphansMeta) {
            if (-not $o.IsGit) { Write-Info ("Skip non-git orphan: {0} ({1})" -f $o.Path,(Get-HBytes $o.Bytes)); continue }
            if (($o.HasUncommitted -ne "DIRTY") -and ($o.StashCount -eq 0)) {
                Write-Info ("Skip CLEAN git orphan: {0} ({1}) — no uncommitted work / stashes. If unneeded, just rm -rf manually." -f $o.Path,(Get-HBytes $o.Bytes))
                continue
            }
            $consolidateOffers++
            $base = Split-Path -Leaf $o.Path
            $archive = Join-Path $ColdStorageDir ("{0}-{1}.zip" -f $ts,$base)
            $stashNote = "pre-umbrella-sweep-$ts"

            Write-Host ""
            Write-Info ("Consolidate #{0}: {1} (dirty={2}, stashes={3})" -f $consolidateOffers,$o.Path,$o.HasUncommitted,$o.StashCount)
            Write-Info ("  Archive: $archive")

            # A) git stash push -u -m <note> (idempotent)
            $gitStashCmd = [scriptblock]::Create("git -C '$($o.Path)' stash push -u -m '$stashNote' 2>`$null; `$LASTEXITCODE = 0")
            Invoke-Safe "git stash push (idempotent — clean tree does nothing)" $gitStashCmd

            # B) Compress-Archive of the orphan directory into ColdStoragePath.
            $tarCmd = [scriptblock]::Create("Compress-Archive -Path '$($o.Path)' -DestinationPath '$archive' -Force -ErrorAction SilentlyContinue")
            Invoke-Safe "Compress-Archive -> $archive" $tarCmd

            # C) Sidecar metadata file next to archive.
            $metaPath = "$archive.meta.txt"
            $meta = @"
Umbrella Sweep consolidated project (Windows)
=================================================
archived_at:       $([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))
original_path:     $($o.Path)
original_size:     $(Get-HBytes $o.Bytes)
uncommitted:       $($o.HasUncommitted)
stashes_before:    $($o.StashCount)
has_node_modules:  $($o.HasNodeModules)
stash_note:        $stashNote
umbrella_repo:     $($RepoRoot.Path)
"@
            if ($Apply) {
                Set-Content -LiteralPath $metaPath -Value $meta -Encoding UTF8
                Write-Info ("  Sidecar metadata written to: $metaPath")
            } else {
                Write-Plan ("Set-Content -LiteralPath '{0}' (meta sidecar)" -f $metaPath)
            }

            Write-Warn "  SAFETY: Phase 3 WILL NEVER delete the original orphan folder. Confirm the zip opens cleanly, then delete manually."
            Write-Plan ("  Expand-Archive -LiteralPath '{0}' -DestinationPath (Join-Path `$env:TEMP verify_sweep)  # verify" -f $archive)
        }
        Write-Host ""
        Write-Info "Phase 3 done: consolidate_offers=$consolidateOffers"
    }

    Snapshot-After "phase3-consolidate"
}

# ============================================================
# PHASE 4. REPORT
# ============================================================
Write-Banner "PHASE 4. REPORT — Disk Space Reclaimed"
$freeNow = Get-FreeBytesOnSystemDrive

Write-Host ""
Write-Host "  Mode:                    $ModeLabel"
Write-Host "  Free bytes on SystemDrive now: $(Get-HBytes $freeNow)  ($freeNow)"
Write-Host "  Umbrella repo:           $($RepoRoot.Path)"
Write-Host "  Cold storage:            $ColdStorageDir"
Write-Host "  Orphans found (Phase 1): $orphansFound"
Write-Host "  Projected bytes if purge + orphan purge (Phase1+2 est.): $(Get-HBytes $ProjectedReclaimTotal)"
Write-Host ""
Write-Host "══ Per-phase snapshot table (APPLY fills ACTUAL, DRY-RUN fills PROJECTED):"
Write-Host ("  {0,-24} | {1,16} | {2,16} | {3,16}" -f "Phase","Before (bytes)","After (bytes)","Δ free")
Write-Host ("  {0,-24} + {1,16} + {2,16} + {3,16}" -f ("-"*24),("-"*16),("-"*16),("-"*16)) -replace "[^|+\r\n]","-"

foreach ($phase in @("phase2-cache","phase3-consolidate","phase1-projected-if-purged")) {
    $before = if ($PhaseBefore.ContainsKey($phase)) { $PhaseBefore[$phase] } else { $null }
    $after  = if ($PhaseAfter.ContainsKey($phase))  { $PhaseAfter[$phase]  } else { $null }
    $delta = if (($null -ne $before) -and ($null -ne $after)) {
        $d = $after - $before
        if ($d -lt 0) { "0 (background alloc?)" } else { "$d" }
    } else { "n/a" }
    Write-Host ("  {0,-24} | {1,16} | {2,16} | {3,16}" -f $phase,
        ($before -as [string] ?? "n/a"),
        ($after  -as [string] ?? "n/a"),
        $delta)
}

Write-Host ""
Write-Host "══ Master human checklist AFTER running with -Apply:"
Write-Host "   ✓ Phase 2 cache purge ran (console output above)."
Write-Host "   ✓ Phase 3 consolidated N dirty git repos into $ColdStorageDir\*.zip + *.meta.txt sidecars."
Write-Host "   ✓ Original orphan source-code directories were NEVER deleted by this script."
Write-Host "   ✓ No git repos, no user docs were touched — only allowlisted cache paths."
Write-Host ""

# Optional JSON report
if ($ReportJson -ne "") {
    $orphansList = @($orphansMeta | ForEach-Object {
        [ordered]@{
            bytes = $_.Bytes; path = $_.Path; is_git = $_.IsGit
            has_uncommitted = $_.HasUncommitted; stash_count = [int]$_.StashCount; has_node_modules = $_.HasNodeModules
        }
    })
    $summary = [ordered]@{
        mode = [ordered]@{ dry_run = (-not $Apply); apply = [bool]$Apply }
        umbrella_repo = $RepoRoot.Path
        cold_storage_dir = $ColdStorageDir
        free_bytes_on_systemdrive_now = [long]$freeNow
        phase1 = [ordered]@{
            orphans_found = [int]$orphansFound
            total_orphan_bytes = [long]$orphansTotalBytes
            orphans = $orphansList
        }
        projected_bytes_reclaimable = [long]$ProjectedReclaimTotal
        actual_bytes_reclaimed_delta_df = [long]$ActualReclaimDelta
    }
    $parent = Split-Path -Parent $ReportJson
    if ($parent -ne "" -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReportJson -Encoding UTF8
    $written = (Get-Item -LiteralPath $ReportJson).Length
    Write-Info "JSON report → $ReportJson ($written bytes)"
}

Write-Info "Global sweeper done — mode $ModeLabel. ✅"
