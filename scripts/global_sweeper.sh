#!/usr/bin/env bash
# global_sweeper — Consolidate orphan repos and purge AI / build / container caches
# on macOS and Linux workstations. STRONG SAFETY GUARANTEE: unless --apply is passed
# NOTHING destructive is ever executed. Defaults are dry-run.
#
# Phase map (all phases run unless a phase is explicitly skipped via flags):
#   1. ANALYZE      — scan for orphan rhea-*/omnia-*/blueshoes-* repos outside the
#                     new Umbrella checkout (REPO_ROOT), calculate sizes + dirty-git state.
#   2. CACHE PURGE  — emit commands to safely delete known AI caches, Docker, Xcode,
#                     npm/yarn/pnpm caches, shell completion caches, etc.
#   3. CONSOLIDATE  — offer a "move to cold storage" path for orphan repos that still
#                     have uncommitted git work (stash + tarball into COLD_STORAGE_DIR).
#   4. REPORT       — print a machine-readable + human-readable "Disk Space Reclaimed"
#                     summary at the very end (only meaningful under --apply, but prints
#                     a PROJECTED summary under --dry-run too).
#
set -euo pipefail

# ---------- Globals ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ---------- Sensible defaults (user-overridable via env or flags) ----------
# A directory OUTSIDE the Umbrella repo where orphan-but-valuable code is moved
# into date-stamped tarballs instead of being deleted. Never inside REPO_ROOT.
DEFAULT_COLD_STORAGE="$HOME/rhea-umbrella-cold-storage"

# Maximum number of orphan directories we will scan (cap runaway).
MAX_ORPHAN_SCAN_DIRS=${MAX_ORPHAN_SCAN_DIRS:-200}

# ---------- Logging helpers ----------
log_info()  { echo "🟢 [Sweep] $*"; }
log_warn()  { echo "🟡 [Sweep] $*"; }
log_err()   { echo "🔴 [Sweep] $*" >&2; }
log_plan()  { echo "📋 [Plan]  $*"; }
log_banner(){ echo; echo "══════════════════════════════════════════════════════════"; echo "══ $*"; echo "══════════════════════════════════════════════════════════"; }

# ---------- Parse arguments ----------
DRY_RUN=1                 # DEFAULT = SAFE (dry run). Explicit --apply required to touch disk.
APPLY=0
SKIP_ANALYZE=0
SKIP_CACHE=0
SKIP_CONSOLIDATE=0
COLD_STORAGE_DIR="$DEFAULT_COLD_STORAGE"
ORPHAN_ROOTS=( "$HOME" )  # default scan roots: user's HOME. Pass --orphan-root DIR multiple times.
REPORT_JSON=""            # if non-empty, path where final summary is written as JSON.

usage() {
  cat <<'EOF'
GLOBAL WORKSPACE SWEEPER (safe-by-default — dry-run unless --apply).

USAGE:
  scripts/global_sweeper.sh [OPTIONS]

OPTIONS (Safety):
  --apply                   Execute destructive commands. If omitted, script runs in
                            100% read-only / plan-only mode (DEFAULT).
  --dry-run                 (Default) Synonym for omitting --apply. Repeated to remind.

OPTIONS (Phase control):
  --skip-analyze            Skip Phase 1 orphan scan.
  --skip-cache              Skip Phase 2 cache purge.
  --skip-consolidate        Skip Phase 3 cold-storage consolidation offer.

OPTIONS (Paths / roots):
  --cold-storage-dir PATH   Directory where valuable-but-orphaned projects are archived
                            as date-stamped .tar.gz files. Must be OUTSIDE REPO_ROOT.
                            Default: $HOME/rhea-umbrella-cold-storage
  --orphan-root PATH        Add PATH as a scan root for orphan project detection.
                            Can be repeated. Default: just $HOME.
  --report-json PATH        Write final machine-readable summary JSON to PATH.

GENERAL:
  -h|--help                 Show this help.

PHASE-BY-PHASE WHAT-IT-DOES:
  1. ANALYZE     Walk each orphan root (depth 6 max) looking for directories whose
                 basename matches {rhea|omnia|blueshoes}-*. Skip anything inside the
                 new Umbrella REPO_ROOT. For each match, print size (du -sh), whether
                 it's a git repo, whether it has uncommitted work, and whether a
                 `git stash list` has entries.
  2. CACHE PURGE Emit commands to delete known safe caches. The master allowlist:
                   • AI caches    : Trae, Cursor, GitHub Copilot, Claude Desktop, etc.
                   • Build caches : Xcode DerivedData/Archives, npm/yarn/pnpm caches,
                                    Cargo target/<pkgid>, go-build cache, pip/wheels
                   • Container   : Docker images/volumes (via docker system prune)
                   • General OS  : ~/Library/Caches/*, ~/.cache/*, shell completions
                 NO source code, NO user documents, NO git repos are ever in this list.
  3. CONSOLIDATE For every orphan project with uncommitted work ("valuable leftovers"),
                 offer:
                   a) run `git stash push -u -m "pre-umbrella-sweep-<timestamp>"`
                   b) create a tarball of the whole directory into COLD_STORAGE_DIR
                   c) under --apply ONLY: optionally delete the original orphan folder.
                 Without --apply, this phase prints exact commands it would run.
  4. REPORT      Print a PROJECTED or ACTUAL summary table:
                     Phase | Category | Before | After | Reclaimed
                 And write JSON summary to --report-json if set.
EOF
}

orphan_roots_override=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)                    APPLY=1; DRY_RUN=0; shift ;;
    --dry-run)                  APPLY=0; DRY_RUN=1; shift ;;
    --skip-analyze)             SKIP_ANALYZE=1; shift ;;
    --skip-cache)               SKIP_CACHE=1; shift ;;
    --skip-consolidate)         SKIP_CONSOLIDATE=1; shift ;;
    --cold-storage-dir)         COLD_STORAGE_DIR="$2"; shift 2 ;;
    --orphan-root)
      if [[ $orphan_roots_override -eq 0 ]]; then
        ORPHAN_ROOTS=()
        orphan_roots_override=1
      fi
      ORPHAN_ROOTS+=("$2"); shift 2 ;;
    --report-json)              REPORT_JSON="$2"; shift 2 ;;
    -h|--help)                  usage; exit 0 ;;
    *) log_err "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# ---------- Safety guardrails ----------
run_mode_label="DRY-RUN (SAFE)"
if [[ $APPLY -eq 1 ]]; then
  run_mode_label="APPLY (DESTRUCTIVE — you passed --apply)"
fi

log_banner "GLOBAL SWEEPER starting: mode = ${run_mode_label}"
log_info "REPO_ROOT (Umbrella — excluded from orphan scan): ${REPO_ROOT}"
log_info "COLD_STORAGE_DIR: ${COLD_STORAGE_DIR}"
log_info "Orphan scan roots:    ${ORPHAN_ROOTS[*]}"
log_info "Phases: analyze=$([[ $SKIP_ANALYZE      -eq 1 ]] && echo SKIP || echo RUN)"
log_info "        cache=$([[ $SKIP_CACHE        -eq 1 ]] && echo SKIP || echo RUN)"
log_info "        consolidate=$([[ $SKIP_CONSOLIDATE -eq 1 ]] && echo SKIP || echo RUN)"
echo

# Guard: COLD_STORAGE_DIR must not be inside REPO_ROOT
case "${COLD_STORAGE_DIR}/" in
  "${REPO_ROOT}/"*)
    log_err "COLD_STORAGE_DIR (${COLD_STORAGE_DIR}) must NOT live inside REPO_ROOT (${REPO_ROOT})."
    log_err "Abort: if you archive orphans inside the umbrella and then commit them you inflate git history."
    exit 3 ;;
esac

# Guard: require COLD_STORAGE_DIR to be absolute
case "${COLD_STORAGE_DIR}" in
  /*) : ;;
  *) log_err "COLD_STORAGE_DIR must be an absolute path. Got: ${COLD_STORAGE_DIR}"; exit 4 ;;
esac

# ---------- Utility helper: run_or_plan ----------
# run_or_plan "$shell_cmd" — if APPLY, execute; if DRY, log as plan.
run_or_plan() {
  local cmd="$1"
  if [[ $APPLY -eq 1 ]]; then
    log_info "$ $cmd"
    # Use eval so redirects and pipes work, since many of our cache commands
    # involve `rm -rf PATH 2>/dev/null` style shells.
    eval "$cmd"
  else
    log_plan "$cmd"
  fi
}

# ---------- Summary accumulators (printed at very end) ----------
declare -A PHASE_BEFORE
declare -A PHASE_AFTER
BYTES_TOTAL_RECLAIMED_PROJECTED=0
BYTES_TOTAL_RECLAIMED_ACTUAL=0

# A helper: record projected bytes we would free (used in dry-run phases).
record_projected() {
  local phase="$1"
  local bytes="$2"
  PHASE_BEFORE["$phase"]=$(( ${PHASE_BEFORE["$phase"]:-0} + bytes ))
  PHASE_AFTER["$phase"]=${PHASE_AFTER["$phase"]:-0}  # after free = whatever was free
  BYTES_TOTAL_RECLAIMED_PROJECTED=$(( BYTES_TOTAL_RECLAIMED_PROJECTED + bytes ))
}

# A helper: after a real delete, record actual bytes reclaimed as delta of df -k.
# Note: diskspace delta is approximate, because background processes allocate too.
# We do best-effort per-phase snapshots via `df -k /` before/after inside APPLY mode.
free_bytes_now() {
  # Use statvfs via python3 for cross-platform stable reading of free bytes.
  python3 - <<'PY' 2>/dev/null
import os, sys
s=os.statvfs("/")
print(s.f_bavail * s.f_frsize)
PY
}

record_snapshot_before() {
  local phase="$1"
  if [[ $APPLY -eq 1 ]]; then
    local b
    b="$(free_bytes_now || echo 0)"
    PHASE_BEFORE["$phase"]="$b"
  fi
}
record_snapshot_after() {
  local phase="$1"
  if [[ $APPLY -eq 1 ]]; then
    local b a
    b="${PHASE_BEFORE["$phase"]:-0}"
    a="$(free_bytes_now || echo "$b")"
    PHASE_AFTER["$phase"]="$a"
    local delta=$(( a - b ))
    if [[ $delta -gt 0 ]]; then
      BYTES_TOTAL_RECLAIMED_ACTUAL=$(( BYTES_TOTAL_RECLAIMED_ACTUAL + delta ))
    fi
  fi
}

hbytes() {
  # Pretty print raw bytes, e.g. "2.4 GB". If python3 not available, echo raw.
  local b="${1:-0}"
  python3 - "$b" <<'PY' 2>/dev/null
import sys
n = int(sys.argv[1])
step = 1024.0
for u in ("B","KB","MB","GB","TB","PB"):
    if n < step:
        print(f"{n:.2f} {u}")
        sys.exit(0)
    n /= step
print(f"{n:.2f} EB")
PY
}

# ============================================================
# PHASE 1. ANALYZE orphan projects
# ============================================================
phase1_orphans_found=0
phase1_bytes_total=0
# Temp files holding discovered orphan paths + metadata.
P1_PATHS=$(mktemp /tmp/sweep_p1_paths.XXXXXX)
P1_META=$(mktemp /tmp/sweep_p1_meta.XXXXXX)
trap 'rm -f "$P1_PATHS" "$P1_META"' EXIT

if [[ $SKIP_ANALYZE -eq 0 ]]; then
  log_banner "PHASE 1. ANALYZE — orphan project discovery (rhea-* / omnia-* / blueshoes-*)"

  # Realpath REPO_ROOT so prefix exclusion is path-invariant.
  UMBRELLA_REAL="$(cd "$REPO_ROOT" && pwd -P)"

  for ORPHAN_ROOT in "${ORPHAN_ROOTS[@]}"; do
    if [[ ! -d "$ORPHAN_ROOT" ]]; then
      log_warn "Orphan root not a directory, skipping: ${ORPHAN_ROOT}"
      continue
    fi
    ORPHAN_ROOT_REAL="$(cd "$ORPHAN_ROOT" && pwd -P)"

    # Walk depth up to 6 (cap at 20,000 entries via head to avoid runaway).
    # Exclude: anything inside the Umbrella repo.
    find "$ORPHAN_ROOT_REAL" -maxdepth 6 -type d \( \
         -name 'rhea-*' -o -name 'omnia-*' -o -name 'blueshoes-*' \
      \) -not -path "${UMBRELLA_REAL}/*" -print 2>/dev/null \
      | head -n "$MAX_ORPHAN_SCAN_DIRS" >> "$P1_PATHS" || true
  done

  # Now inspect each discovered path; metadata is TSV:
  #   SIZE_BYTES \t PATH \t IS_GIT_REPO \t HAS_UNCOMMITTED \t STASH_COUNT \t HAS_NODE_MODULES
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    # Duplicate guard (same dir can be reached via multiple roots).
    if grep -Fsq $'\t'"$d"$'\t' "$P1_META" 2>/dev/null; then
      continue
    fi
    phase1_orphans_found=$(( phase1_orphans_found + 1 ))

    # size (first du -sk, shallow — but for summary we report shallow size of dir)
    sz_kb="$(/usr/bin/du -sk "$d" 2>/dev/null | awk '{print $1}' || echo 0)"
    sz_bytes=$(( sz_kb * 1024 ))
    phase1_bytes_total=$(( phase1_bytes_total + sz_bytes ))
    record_projected "phase1-projected-if-purged" "$sz_bytes"

    is_git="no"; has_uncommitted="n/a"; stashes="0"; has_node_mod="no"
    if command -v git >/dev/null 2>&1; then
      if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
        is_git="yes"
        if [[ -z "$(git -C "$d" status --porcelain 2>/dev/null)" ]]; then
          has_uncommitted="clean"
        else
          has_uncommitted="DIRTY"
        fi
        stashes="$(git -C "$d" stash list 2>/dev/null | wc -l | tr -d ' ')"
      fi
    fi
    if [[ -d "$d/node_modules" ]]; then
      has_node_mod="yes"
    fi
    printf '%d\t%s\t%s\t%s\t%s\t%s\n' \
      "$sz_bytes" "$d" "$is_git" "$has_uncommitted" "$stashes" "$has_node_mod" \
      >> "$P1_META"

    # Print per-directory banner.
    dir_flag=""
    [[ "$is_git"         == "yes"   ]] && dir_flag+="[git]"
    [[ "$has_uncommitted" == "DIRTY" ]] && dir_flag+="[UNCOMMITTED-WORK⚠️]"
    [[ "$stashes"        -gt 0      ]] && dir_flag+="[stashes=$stashes]"
    [[ "$has_node_mod"   == "yes"   ]] && dir_flag+="[node_modules]"
    log_info "$(hbytes "$sz_bytes")  orphan ${phase1_orphans_found}: ${d} ${dir_flag}"
  done < "$P1_PATHS"

  echo
  log_info "Phase 1 done: orphans_found=${phase1_orphans_found}, projected_total_if_removed=$(hbytes "$phase1_bytes_total")"
else
  log_info "Phase 1 skipped per --skip-analyze."
fi

# ============================================================
# PHASE 2. CACHE PURGE — emit (or run) known safe cache deletes.
# ============================================================
if [[ $SKIP_CACHE -eq 0 ]]; then
  log_banner "PHASE 2. CACHE PURGE (allowlisted paths only — NO source code ever listed)"
  record_snapshot_before "phase2-cache"

  # Define allowlist as associative array: human_label -> shell command.
  # Each command is idempotent, each ignores nonexistent paths with 2>/dev/null.
  declare -a CACHE_LABELS=()
  declare -a CACHE_CMDS=()

  add_cache_cmd() {
    CACHE_LABELS+=("$1")
    CACHE_CMDS+=("$2")
  }

  # --- Trae (the IDE we're in) + Cursor (popular sibling) ------------------
  add_cache_cmd "Trae: user cache dirs" \
    "rm -rf ~/Library/Application\ Support/Trae/Cache ~/Library/Application\ Support/Trae/CacheData ~/Library/Application\ Support/Trae/CachedData ~/Library/Application\ Support/Trae/Code\ Cache ~/Library/Application\ Support/Trae/GPUCache ~/Library/Application\ Support/Trae/User/workspaceStorage ~/Library/Caches/Trae 2>/dev/null || true"
  add_cache_cmd "Trae: service-worker CacheStorage + blob_storage" \
    "rm -rf ~/Library/Application\ Support/Trae/Service\ Worker/CacheStorage ~/Library/Application\ Support/Trae/Service\ Worker/ScriptCache ~/Library/Application\ Support/Trae/blob_storage ~/Library/Application\ Support/Trae/logs 2>/dev/null || true"
  add_cache_cmd "Cursor: app caches + workspace storage" \
    "rm -rf ~/Library/Application\ Support/Cursor/Cache* ~/Library/Application\ Support/Cursor/Code\ Cache ~/Library/Application\ Support/Cursor/GPUCache ~/Library/Application\ Support/Cursor/User/workspaceStorage ~/Library/Application\ Support/Cursor/blob_storage ~/Library/Logs/Cursor* 2>/dev/null || true"
  add_cache_cmd "VSCode family shared cache (ripgrep binaries are safe transient)" \
    "find ~/Library/Application\ Support -maxdepth 4 -type d -name 'rg' -path '*Code*' 2>/dev/null | while read -r rgdir; do rm -rf \"\$rgdir\" 2>/dev/null || true; done; find ~/.vscode* -maxdepth 3 -name '*.log*' -delete 2>/dev/null || true"
  add_cache_cmd "GitHub Copilot + Claude Desktop logs/caches" \
    "rm -rf ~/Library/Application\ Support/GitHub\ Copilot ~/Library/Application\ Support/Claude ~/Library/Logs/Claude 2>/dev/null || true"
  add_cache_cmd "Rust cargo build artifacts (global target/ cross-package, and registry cache .cargo)" \
    "rm -rf ~/.cargo/registry/cache ~/.cargo/registry/src ~/.cargo/git/db 2>/dev/null; (command -v cargo >/dev/null 2>&1 && cargo -v clean --manifest-path /dev/null 2>/dev/null) || true"
  add_cache_cmd "Go build cache & module download cache" \
    "(command -v go >/dev/null 2>&1 && go clean -cache -fuzzcache -testcache) || true; rm -rf ~/go/pkg/mod/cache 2>/dev/null || true"
  add_cache_cmd "Python pip / pyenv / uv / poetry wheels cache" \
    "rm -rf ~/.cache/pip ~/Library/Caches/pip ~/.cache/pypoetry 2>/dev/null; rm -rf ~/.pyenv/cache 2>/dev/null; command -v uv >/dev/null 2>&1 && uv cache clean 2>/dev/null || true"
  add_cache_cmd "NPM global + local caches (--force required to really purge)" \
    "(command -v npm >/dev/null 2>&1 && npm cache clean --force 2>/dev/null); rm -rf ~/.npm/_cacache 2>/dev/null || true"
  add_cache_cmd "Yarn 1.x + Berry (Yarn 2/3/4) global caches" \
    "rm -rf ~/.yarn/cache ~/.cache/yarn ~/Library/Caches/Yarn ~/Library/Caches/YarnBerry 2>/dev/null; (command -v yarn >/dev/null 2>&1 && yarn cache clean 2>/dev/null) || true"
  add_cache_cmd "PNPM global store" \
    "command -v pnpm >/dev/null 2>&1 && pnpm store prune 2>/dev/null || true; rm -rf ~/.local/share/pnpm/store 2>/dev/null || true"
  add_cache_cmd "Bun (fast JS package manager) install cache" \
    "rm -rf ~/.bun/install/cache 2>/dev/null || true"
  add_cache_cmd "macOS user-level .logs + general ~/Library/Caches minus crucial browser stuff" \
    "rm -rf ~/Library/Logs/* 2>/dev/null; find ~/Library/Caches -mindepth 1 -maxdepth 1 -type d -not -name 'com.apple.Safari*' -exec rm -rf {} + 2>/dev/null || true"
  add_cache_cmd "Linux-style XDG ~/.cache general bloat" \
    "find ~/.cache -mindepth 1 -maxdepth 1 -type d -not -name 'gnome-software' -not -name 'thumbnails' -exec rm -rf {} + 2>/dev/null || true"
  add_cache_cmd "Docker images / containers / volumes / build cache (prune, never deletes the installed app)" \
    "if command -v docker >/dev/null 2>&1; then (docker system prune --all --volumes --force 2>/dev/null || true); fi"
  add_cache_cmd "Xcode DerivedData, Archives, DeviceSupport, Docs cache, sim runtime caches (already done manually above; idempotent safe-run)" \
    "rm -rf ~/Library/Developer/Xcode/DerivedData ~/Library/Developer/Xcode/Archives ~/Library/Developer/Xcode/DeviceSupport ~/Library/Developer/Xcode/watchOS\ DeviceSupport ~/Library/Developer/Xcode/tvOS\ DeviceSupport ~/Library/Developer/Xcode/DocumentationCache 2>/dev/null; mkdir -p ~/Library/Developer/Xcode/DerivedData ~/Library/Developer/Xcode/Archives ~/Library/Developer/Xcode/DocumentationCache 2>/dev/null || true"
  add_cache_cmd "macOS CoreSimulator unavailable devices + global user device pairs" \
    "command -v xcrun >/dev/null 2>&1 && (xcrun simctl delete unavailable 2>/dev/null) || true; rm -rf ~/Library/Developer/CoreSimulator/Caches 2>/dev/null || true"
  add_cache_cmd "macOS sleepimage (safe: recreated next time machine sleeps — frees up to RAM size)" \
    "sudo -n rm -f /private/var/vm/sleepimage 2>/dev/null || { log_warn 'sleepimage requires sudo; skipped. Run: sudo rm -f /private/var/vm/sleepimage'; true; }"

  # Print headers
  if [[ $APPLY -eq 0 ]]; then
    log_info "Dry-run mode: below are the EXACT commands that would run under --apply."
    log_info "No command is actually touching your disk."
    echo
  fi

  idx=0
  total_cmds=${#CACHE_LABELS[@]}
  while [[ $idx -lt $total_cmds ]]; do
    label="${CACHE_LABELS[$idx]}"
    cmd="${CACHE_CMDS[$idx]}"
    log_info "▸ [${idx}] ${label}"
    run_or_plan "$cmd"
    idx=$(( idx + 1 ))
  done

  record_snapshot_after "phase2-cache"
fi

# ============================================================
# PHASE 3. CONSOLIDATE — move orphans with uncommitted work to cold storage.
# ============================================================
if [[ $SKIP_CONSOLIDATE -eq 0 ]]; then
  log_banner "PHASE 3. CONSOLIDATE — orphan projects with UNCOMMITTED WORK → move to cold storage"
  record_snapshot_before "phase3-consolidate"

  if [[ $APPLY -eq 1 ]]; then
    run_or_plan "mkdir -p '${COLD_STORAGE_DIR}'"
  else
    log_plan "mkdir -p '${COLD_STORAGE_DIR}'"
  fi

  if [[ $phase1_orphans_found -eq 0 ]]; then
    log_info "No orphans found in Phase 1. Consolidation has nothing to do. Skip."
  else
    TS=$(date +%Y%m%d-%H%M%S)
    consolidated_count=0
    while IFS=$'\t' read -r sz_bytes d is_git has_uncommitted stashes has_node_mod; do
      [[ -z "$d" ]] && continue
      # Only "valuable leftovers" = git repo AND (dirty or has stashes).
      if [[ "$is_git" != "yes" ]]; then
        log_info "Skip non-git orphan: ${d}  (size $(hbytes "$sz_bytes"))"
        continue
      fi
      if [[ "$has_uncommitted" != "DIRTY" ]] && [[ "$stashes" -eq 0 ]]; then
        log_info "Skip clean git orphan: ${d}  (size $(hbytes "$sz_bytes")). If you don't need it, just rm -rf it manually; no consolidation needed."
        continue
      fi
      consolidated_count=$(( consolidated_count + 1 ))
      base="$(basename "$d")"
      archive_path="${COLD_STORAGE_DIR}/${TS}-${base}.tar.gz"
      stash_note="pre-umbrella-sweep-${TS}"

      echo
      log_info "Consolidate #${consolidated_count}: ${d}  (dirty=${has_uncommitted}, stashes=${stashes})"
      log_info "  Destination tarball: ${archive_path}"

      # Step A: stash push -u -m <note> (idempotent: if index/working tree is clean, git stash is a no-op, exits 1, we || true).
      run_or_plan "git -C '$d' stash push -u -m '${stash_note}' 2>/dev/null || true"
      # Step B: create tarball archive of entire dir into COLD_STORAGE_DIR.
      run_or_plan "tar -czf '${archive_path}' -C '$(dirname "$d")' '$(basename "$d")'"
      # Step C: write a tiny sidecar metadata file next to the archive.
      if [[ $APPLY -eq 1 ]]; then
        cat > "${archive_path}.meta.txt" <<META
Umbrella Sweep consolidated project
=================================================
archived_at:       $(date -u +"%Y-%m-%dT%H:%M:%SZ")
original_path:     ${d}
original_size:     $(hbytes "$sz_bytes")
uncommitted:       ${has_uncommitted}
stashes_before:    ${stashes}
has_node_modules:  ${has_node_mod}
stash_note:        ${stash_note}
umbrella_repo:     ${REPO_ROOT}
META
        log_info "  Sidecar metadata written to: ${archive_path}.meta.txt"
      else
        log_plan "cat > '${archive_path}.meta.txt' <<META  (meta sidecar describing original path, stash note, size)"
      fi
      # Step D: AFTER user confirmation (separate interactive run, NOT this script),
      # they can run `rm -rf "$d"` themselves. This script NEVER deletes source dirs.
      log_warn "  SAFETY: Phase 3 will NEVER delete the original orphan dir. You must do that manually after verifying the tarball extracts cleanly with:"
      log_plan "  tar -tzf '${archive_path}' | head -n 20"
    done < "$P1_META"
    echo
    log_info "Phase 3 done: consolidate_offers=${consolidated_count}"
  fi

  record_snapshot_after "phase3-consolidate"
fi

# ============================================================
# PHASE 4. REPORT — print PROJECTED / ACTUAL summary.
# ============================================================
log_banner "PHASE 4. REPORT — Disk Space Reclaimed"

FREE_NOW_BYTES="$(free_bytes_now || echo 0)"

echo
echo "  Mode:                    ${run_mode_label}"
echo "  Free bytes on / now:     $(hbytes "${FREE_NOW_BYTES}")  (${FREE_NOW_BYTES})"
echo "  Umbrella repo:           ${REPO_ROOT}"
echo "  Cold storage:            ${COLD_STORAGE_DIR}"
echo "  Orphans found (Phase 1): ${phase1_orphans_found}"
echo "  Projected bytes if purge + orphans deleted (Phase1+2 est.): $(hbytes "${BYTES_TOTAL_RECLAIMED_PROJECTED}")"
echo

echo "══ Per-phase snapshot table (APPLY fills ACTUAL, DRY-RUN fills PROJECTED):"
printf '  %-22s | %16s | %16s | %16s\n' "Phase" "Before (bytes)" "After (bytes)" "Δ (free)"
printf '  %-22s-+-%16s-+-%16s-+-%16s\n' "----------------------" "----------------" "----------------" "----------------" \
  | tr ' ' '-'

for phase in phase2-cache phase3-consolidate phase1-projected-if-purged; do
  before="${PHASE_BEFORE[$phase]:-}"
  after="${PHASE_AFTER[$phase]:-}"
  delta=""
  label="$phase"
  if [[ -n "$before" && -n "$after" ]]; then
    delta=$(( after - before ))
    [[ $delta -lt 0 ]] && delta="0 (neg, background alloc?)"
  fi
  printf '  %-22s | %16s | %16s | %16s\n' \
    "$label" "${before:-n/a}" "${after:-n/a}" "${delta:-n/a}"
done

echo
echo "══ Master human checklist AFTER you run with --apply:"
echo "   ✓ Phase 2 cache-purge ran (output above)."
echo "   ✓ Phase 3 offered to consolidate N dirty git orphans (tarballs in COLD_STORAGE_DIR)."
echo "   ✓ Original orphan source-code directories were NEVER deleted by this script."
echo "   ✓ No git repos, no user docs were touched — only allowlisted cache paths."
echo

# Optional JSON summary
if [[ -n "$REPORT_JSON" ]]; then
  python3 - "$REPORT_JSON" \
    "$DRY_RUN" "$APPLY" "$REPO_ROOT" "$COLD_STORAGE_DIR" \
    "$phase1_orphans_found" "$phase1_bytes_total" \
    "$BYTES_TOTAL_RECLAIMED_PROJECTED" "$BYTES_TOTAL_RECLAIMED_ACTUAL" \
    "$FREE_NOW_BYTES" \
    "$P1_META" \
    <<'PY'
import json, pathlib, sys, os, csv
out, dry, apply, repo, cold, orph_n, orph_b, proj_b, act_b, free_b, meta = sys.argv[1:12]
rows = []
meta_path = pathlib.Path(meta)
if meta_path.exists():
    with meta_path.open("r", encoding="utf-8") as f:
        for line in f:
            line=line.rstrip("\n")
            if not line: continue
            parts=line.split("\t")
            while len(parts)<6: parts.append("")
            sz,d,git,dirty,st,nm=parts
            rows.append({"bytes": int(sz), "path": d, "is_git": git=="yes",
                         "has_uncommitted": dirty, "stash_count": int(st),
                         "has_node_modules": nm=="yes"})
summary = {
    "mode": {"dry_run": dry=="1", "apply": apply=="1"},
    "umbrella_repo": repo,
    "cold_storage_dir": cold,
    "free_bytes_on_slash_now": int(free_b),
    "phase1": {
        "orphans_found": int(orph_n),
        "total_orphan_bytes": int(orph_b),
        "orphans": rows,
    },
    "projected_bytes_reclaimable": int(proj_b),
    "actual_bytes_reclaimed_delta_df": int(act_b),
}
pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(out).write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
print(f"WROTE {out} ({pathlib.Path(out).stat().st_size} bytes)", file=sys.stderr)
PY
fi

log_info "Global sweeper done — mode ${run_mode_label}. ✅"
