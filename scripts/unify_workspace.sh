#!/usr/bin/env bash
# unify_workspace — Bind omnia-playbook (Declarative Oracle) and omnia-vault (State Engine)
# into rhea-project (Umbrella/Command Center) using Git Submodules.
#
# Safety guarantees:
#   • Never modifies the internal contents of omnia-playbook or omnia-vault checkouts.
#   • Never overwrites uncommitted local work in rhea-project; aborts before touching
#     a dirty working tree unless --force is passed (explicit opt-in).
#   • Idempotent: if a submodule is already registered and initialized, re-run is a no-op
#     unless --recreate is passed.
#   • Always prefers local on-disk checkouts (from the provided --playbook-src /
#     --vault-src arguments or the known paths) over fresh network clones. Only falls
#     back to network clone if local source is missing.
#   • --dry-run prints the exact sequence of git commands WITHOUT executing them.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

log_info()  { echo "🟢 [Unify] $*"; }
log_warn()  { echo "🟡 [Unify] $*"; }
log_err()   { echo "🔴 [Unify] $*" >&2; }
log_plan()  { echo "📋 [Plan] $*"; }

usage() {
  cat <<'EOF'
Rhea Umbrella Unifier — bind omnia-playbook + omnia-vault as git submodules.

USAGE:
  scripts/unify_workspace.sh [OPTIONS]

OPTIONS:
  --dry-run                Print plan only; do not modify any files or git state.
  --force                  Proceed even if rhea-project working tree has uncommitted
                           changes (defaults to ABORT on dirty tree).
  --recreate               Remove then re-add existing submodule entries. Implies loss
                           of the locally-registered commit pointer; use with care.
  --no-network             Do NOT fall back to `git clone` if local src is missing.
                           Simply abort and tell the user where to clone from.
  --playbook-src PATH      Local filesystem path to an existing omnia-playbook checkout
                           (used as the submodule source before any network).
                           Default: /tmp/omnia-playbook-inspect/omnia-playbook
  --vault-src PATH         Local filesystem path to an existing omnia-vault checkout.
                           Default: "/Users/sa/Documents/Documents - mio/timelabs-npo/omnia-vault"
  --playbook-url URL       Upstream URL for omnia-playbook (used only when --no-network
                           is absent and local --playbook-src is unavailable).
                           Default: https://github.com/timelabs-npo/omnia-playbook.git
  --vault-url URL          Upstream URL for omnia-vault.
                           Default: https://github.com/timelabs-npo/omnia-vault.git
  --submodules-dir DIR     Directory inside rhea-project where submodules live.
                           Default: vendor/omnia (NOT top-level; keeps root clean)
  -h|--help                Show this help.

SUBMODULE PATHS (non-negotiable default layout):
  vendor/omnia/playbook   — Declarative Oracle (omnia-playbook)
  vendor/omnia/vault      — State Engine     (omnia-vault)
EOF
}

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
DRY_RUN=0
FORCE=0
RECREATE=0
NO_NETWORK=0
PB_SRC="/tmp/omnia-playbook-inspect/omnia-playbook"
VAULT_SRC="/Users/sa/Documents/Documents - mio/timelabs-npo/omnia-vault"
PB_URL="https://github.com/timelabs-npo/omnia-playbook.git"
VAULT_URL="https://github.com/timelabs-npo/omnia-vault.git"
SUB_DIR="vendor/omnia"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=1; shift ;;
    --force)          FORCE=1; shift ;;
    --recreate)       RECREATE=1; shift ;;
    --no-network)     NO_NETWORK=1; shift ;;
    --playbook-src)   PB_SRC="$2"; shift 2 ;;
    --vault-src)      VAULT_SRC="$2"; shift 2 ;;
    --playbook-url)   PB_URL="$2"; shift 2 ;;
    --vault-url)      VAULT_URL="$2"; shift 2 ;;
    --submodules-dir) SUB_DIR="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) log_err "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

PB_SUB="${SUB_DIR}/playbook"
VAULT_SUB="${SUB_DIR}/vault"

# ---------------------------------------------------------------------------
# Run helpers
# ---------------------------------------------------------------------------
maybe() {
  # Print then run a command, unless DRY_RUN. Commands with unix-boundaries like
  # `cd ... && ...` are passed as a single string and evaluated under bash -c
  # so globbing/redirections still behave as expected.
  local shell_cmd="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    log_plan "$shell_cmd"
    return 0
  fi
  log_info "$ $shell_cmd"
  bash -c "$shell_cmd"
}

die() {
  log_err "$*"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# Preflight checks (run even under dry-run)
# ---------------------------------------------------------------------------
log_info "Unify starting. repo_root=$REPO_ROOT dry_run=$DRY_RUN force=$FORCE recreate=$RECREATE no_network=$NO_NETWORK"
require_cmd git

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  die "rhea-project is not a git repository. Must be run from inside a git checkout."
fi

# Dirty-tree safety
if [[ $FORCE -ne 1 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    log_warn "Uncommitted changes detected in rhea-project working tree:"
    git status --short || true
    die "Aborting. Stash/commit first, or re-run with --force to proceed anyway."
  fi
fi

# Never mutate submodule internals; show a banner for operator clarity.
log_info "ZERO-TRUST: This script never edits omnia-playbook or omnia-vault internal files."
log_info "Submodules are registered only; submodule commits must be advanced explicitly in their own repos."

# ---------------------------------------------------------------------------
# Build the canonical plan (in order), then execute.
# ---------------------------------------------------------------------------
PLAN_STEPS=()

step() { PLAN_STEPS+=("$1"); }

# Step 0: ensure vendor/omnia dir exists
step "mkdir -p '${REPO_ROOT}/${SUB_DIR}'"

# Helpers per submodule
register_submodule() {
  local sub_path="$1"
  local preferred_src="$2"
  local fallback_url="$3"
  local name_suffix="$4"

  if git submodule status -- "$sub_path" >/dev/null 2>&1; then
    # Already registered
    if git config --file .gitmodules --get "submodule.${sub_path}.path" >/dev/null 2>&1; then
      if [[ $RECREATE -eq 1 ]]; then
        step "# [recreate] removing existing submodule entry for ${sub_path}"
        step "cd '${REPO_ROOT}' && git submodule deinit -f -- '${sub_path}' && git rm -f --cached '${sub_path}' && rm -rf '.git/modules/${name_suffix}' && rm -rf '${sub_path}' && (git config --file .gitmodules --remove-section submodule.${sub_path} || true) && (git rm -f --ignore-unmatch .gitmodules || true)"
      else
        step "# [noop] submodule already registered: ${sub_path} (use --recreate to replace)"
        step "cd '${REPO_ROOT}' && git submodule update --init -- '${sub_path}'"
        return
      fi
    fi
  fi

  # Choose source: preferred local src (with git repo) > fallback_url > abort
  local use_src=""
  if [[ -d "$preferred_src" ]] && git -C "$preferred_src" rev-parse --git-dir >/dev/null 2>&1; then
    use_src="local"
    step "# adding ${sub_path} from local checkout: ${preferred_src}"
    step "cd '${REPO_ROOT}' && git submodule add -f --name '${name_suffix}' -- '${preferred_src}' '${sub_path}'"
  else
    if [[ $NO_NETWORK -eq 1 ]]; then
      log_err "Missing local ${name_suffix} source at: ${preferred_src}"
      log_err "Network clone disabled (--no-network). Clone manually, pass --playbook-src/--vault-src, or re-run without --no-network."
      log_err "Fallback URL would be: ${fallback_url}"
      exit 3
    fi
    use_src="url"
    step "# adding ${sub_path} from upstream URL: ${fallback_url} (local source missing)"
    step "cd '${REPO_ROOT}' && git submodule add -f --name '${name_suffix}' -- '${fallback_url}' '${sub_path}'"
  fi
}

register_submodule "$PB_SUB"    "$PB_SRC"    "$PB_URL"    "omnia-playbook"
register_submodule "$VAULT_SUB" "$VAULT_SRC" "$VAULT_URL" "omnia-vault"

# Initialize/update each new submodule to its registered tip (no checkout deep-mutation)
step "# initialize both submodule checkouts without pulling/rebasing"
step "cd '${REPO_ROOT}' && git submodule update --init -- '${PB_SUB}' '${VAULT_SUB}'"

# Record a status summary to stdout + optional JSON
step "# final topology summary (dry-run-safe read-only)"
step "cd '${REPO_ROOT}' && git submodule status -- '${PB_SUB}' '${VAULT_SUB}' && ls -la '${SUB_DIR}'"

# ---------------------------------------------------------------------------
# Execute or print plan
# ---------------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
  echo
  log_info "--- DRY-RUN PLAN (${#PLAN_STEPS[@]} steps) ---"
  for s in "${PLAN_STEPS[@]}"; do
    if [[ "$s" == "#"* ]]; then
      echo
      log_plan "$s"
    else
      echo "  $ $s"
    fi
  done
  echo
  log_info "End of dry-run. Re-run WITHOUT --dry-run to apply."
  exit 0
fi

log_info "Applying ${#PLAN_STEPS[@]} plan steps..."
for s in "${PLAN_STEPS[@]}"; do
  if [[ "$s" == "#"* ]]; then
    log_info "${s#'# '}"
    continue
  fi
  maybe "$s"
done

log_info "Unify complete."
log_info "Next actions:"
echo "  1. Review submodule state:    git submodule status -- ${PB_SUB} ${VAULT_SUB}"
echo "  2. Review .gitmodules diff:   git diff -- .gitmodules ${PB_SUB} ${VAULT_SUB}"
echo "  3. Commit ONLY when happy:    git add .gitmodules ${PB_SUB} ${VAULT_SUB}"
echo "  4. (Optional) Lock SHAs:      scripts/unify_lock_versions.sh  (not part of this script)"
echo
echo "  Declarative Oracle lives at:  ${PB_SUB}"
echo "  State Engine       lives at:  ${VAULT_SUB}"
