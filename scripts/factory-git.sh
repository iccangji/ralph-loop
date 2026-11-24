#!/bin/bash
# factory-git.sh - PRD branches, task worktrees, and host-owned merges
#
# Verbs:
#   prepare TASK-{id} --repos a,b   create the PRD branch and task worktrees
#   status  TASK-{id}               show the manifest as a table
#   merge   TASK-{id}               merge a PASSed task into the PRD branch (host)
#   abort   TASK-{id}               discard a task's worktree, branch, and verdict (host)
#   finish  PRD-{id} [--push]       print (or run) push and PR commands
#
# merge, abort, and finish --push require RALPH_HOST=1, which ralph.sh sets for
# its own calls. That keeps an agent from landing its own work.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR

# shellcheck source=lib/constants.sh
source "$SCRIPT_DIR/scripts/lib/constants.sh"
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/scripts/lib/logging.sh"
# shellcheck source=lib/factory.sh
source "$SCRIPT_DIR/scripts/lib/factory.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  factory-git.sh prepare TASK-{id} --repos repo1,repo2
  factory-git.sh status  TASK-{id}
  factory-git.sh merge   TASK-{id}               (RALPH_HOST=1)
  factory-git.sh abort   TASK-{id}               (RALPH_HOST=1)
  factory-git.sh finish  PRD-{id} [--push|--push-only]  (--push/--push-only needs RALPH_HOST=1)
EOF
  return $EXIT_GIT_USAGE
}

require_host() {
  if [ "${RALPH_HOST:-}" != "1" ]; then
    log_error "$1 is host-only. Run it from ralph.sh or set RALPH_HOST=1."
    return $EXIT_GIT_USAGE
  fi
}

# Single-quote a value for a copy-pasteable command line.
shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# ---------------------------------------------------------------------------
# prepare
# ---------------------------------------------------------------------------

prepare_one_repo() {
  local task="$1"
  local slug="$2"
  local type="$3"
  local name="$4"
  local source base worktree branch integration integration_sha base_sha source_head

  source=$(factory_source_repo "$name")
  if [ ! -d "$source/.git" ] && [ ! -f "$source/.git" ]; then
    log_error "No git repository at $source"
    return $EXIT_GIT_USAGE
  fi

  if factory_repo_dirty "$source"; then
    log_error "$name has uncommitted changes; commit or stash them before preparing a task."
    return $EXIT_GIT_DIRTY_SOURCE
  fi

  source_head=$(git -C "$source" rev-parse HEAD 2>/dev/null) || {
    log_error "$name has no commits."
    return $EXIT_GIT_USAGE
  }

  factory_exclude_worktrees "$source"

  local pair
  if ! pair=$(factory_ensure_integration "$source" "$name" "$slug" "$type"); then
    return $EXIT_GIT_USAGE
  fi
  integration="${pair%% *}"
  integration_sha="${pair##* }"

  worktree=$(factory_task_worktree "$slug" "$task" "$name")
  branch=$(factory_task_branch "$type" "$slug" "$task")

  if git -C "$source" show-ref --verify --quiet "refs/heads/$branch"; then
    log_error "Branch $branch already exists in $name but no manifest owns it. Run 'factory-git.sh abort $task' first."
    return $EXIT_GIT_SLUG_COLLISION
  fi

  mkdir -p "$(dirname "$worktree")"
  local add_output
  if ! add_output=$(git -C "$source" worktree add -b "$branch" "$worktree" "$integration_sha" 2>&1); then
    log_error "Could not create worktree for $name at $worktree"
    [ -n "$add_output" ] && log_error "  $add_output"
    return $EXIT_GIT_USAGE
  fi

  factory_hydrate_worktree "$source" "$worktree"

  base=$(factory_base_branch "$source") || base=""
  base_sha=$(git -C "$integration" rev-parse HEAD 2>/dev/null)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$source" "$source_head" "$integration" "$worktree" \
    "$base_sha" "$branch" "$type/$slug" "$base" "prepared"
}

cmd_prepare() {
  [ $# -ge 1 ] || { usage; return $EXIT_GIT_USAGE; }
  local task="$1"
  shift

  local repos_csv=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repos) repos_csv="${2:-}"; shift 2 ;;
      *) usage; return $EXIT_GIT_USAGE ;;
    esac
  done

  if [ -z "$repos_csv" ]; then
    log_error "prepare needs --repos with at least one repository name."
    return $EXIT_GIT_USAGE
  fi

  local rc
  factory_load_prd "$task"
  rc=$?
  [ $rc -eq 0 ] || return $rc

  local slug="$FACTORY_SLUG"
  local type="$FACTORY_TYPE"
  local manifest
  manifest=$(factory_manifest_path "$slug" "$task")

  # A new attempt must never inherit a previous attempt's PASS.
  rm -f "$(factory_verdict_path "$task")" 2>/dev/null || true

  if [ -f "$manifest" ]; then
    local intact=true
    local path
    while IFS= read -r path; do
      [ -d "$path" ] || { intact=false; break; }
    done < <(jq -r '.repos[].worktree' "$manifest" 2>/dev/null)
    if [ "$intact" = true ]; then
      log_info "$task is already prepared; reusing its worktrees."
      return 0
    fi
    log_warn "Discarding a stale manifest for $task before preparing again."
    factory_discard_task "$manifest" "$task"
  fi

  local rows=""
  local name
  local -a names=()
  IFS=',' read -r -a names <<< "$repos_csv"
  for name in "${names[@]}"; do
    name=$(printf '%s' "$name" | xargs)
    [ -n "$name" ] || continue
    local row
    row=$(prepare_one_repo "$task" "$slug" "$type" "$name") || {
      rc=$?
      # Roll back whatever this prepare already created.
      if [ -n "$rows" ]; then
        local tmp_manifest="$manifest"
        mkdir -p "$(dirname "$manifest")"
        printf '%s\n' "$rows" | jq -Rn \
          --arg task "$task" --arg prd "$FACTORY_PRD_ID" --arg slug "$slug" \
          --arg type "$type" '
          [ inputs | split("\t") | {
              name: .[0], source: .[1], source_head: .[2],
              integration_worktree: .[3], worktree: .[4], base_sha: .[5],
              task_branch: .[6], prd_branch: .[7], base_branch: .[8]
            } ] as $repos
          | { task_id: $task, prd: $prd, slug: $slug, type: $type,
              created_at: (now | todate), repos: $repos }' > "$tmp_manifest"
        factory_discard_task "$tmp_manifest" "$task"
      fi
      return $rc
    }
    rows+="$row"$'\n'
  done

  mkdir -p "$(dirname "$manifest")"
  printf '%s' "$rows" | jq -Rn \
    --arg task "$task" --arg prd "$FACTORY_PRD_ID" --arg slug "$slug" \
    --arg type "$type" '
    [ inputs | split("\t") | {
        name: .[0], source: .[1], source_head: .[2],
        integration_worktree: .[3], worktree: .[4], base_sha: .[5],
        task_branch: .[6], prd_branch: .[7], base_branch: .[8]
      } ] as $repos
    | { task_id: $task, prd: $prd, slug: $slug, type: $type,
        created_at: (now | todate), repos: $repos }' > "$manifest"

  log_success "$task prepared on $FACTORY_BRANCH"
  printf '  manifest: %s\n' "$manifest"
  printf '  repos:    %s\n' "$(jq -r '[.repos[].name] | join(", ")' "$manifest")"
  return 0
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

cmd_status() {
  [ $# -eq 1 ] || { usage; return $EXIT_GIT_USAGE; }
  local task="$1"

  local rc
  factory_load_prd "$task"; rc=$?
  [ $rc -eq 0 ] || return $rc

  local manifest
  manifest=$(factory_manifest_path "$FACTORY_SLUG" "$task")
  if [ ! -f "$manifest" ]; then
    log_error "No manifest for $task."
    return $EXIT_GIT_MANIFEST
  fi

  printf '%-24s %-28s %-10s %-7s %s\n' REPO BRANCH BASE AHEAD STATE
  local name worktree branch base_sha ahead state
  while IFS=$'\t' read -r name worktree branch base_sha; do
    if [ ! -d "$worktree" ]; then
      printf '%-24s %-28s %-10s %-7s %s\n' "$name" "$branch" "${base_sha:0:8}" - MISSING
      continue
    fi
    ahead=$(git -C "$worktree" rev-list --count "$base_sha..HEAD" 2>/dev/null || echo "?")
    state=$(git -C "$worktree" status --porcelain 2>/dev/null)
    [ -n "$state" ] && state="dirty" || state="clean"
    printf '%-24s %-28s %-10s %-7s %s\n' \
      "$name" "$branch" "${base_sha:0:8}" "$ahead" "$state"
  done < <(jq -r '.repos[] | [.name, .worktree, .task_branch, .base_sha] | @tsv' "$manifest")
}

# ---------------------------------------------------------------------------
# merge
# ---------------------------------------------------------------------------

cmd_merge() {
  [ $# -eq 1 ] || { usage; return $EXIT_GIT_USAGE; }
  require_host merge || return $EXIT_GIT_USAGE
  local task="$1"

  local rc
  factory_load_prd "$task"; rc=$?
  [ $rc -eq 0 ] || return $rc

  local manifest
  manifest=$(factory_manifest_path "$FACTORY_SLUG" "$task")
  if [ ! -f "$manifest" ]; then
    log_error "No manifest for $task; nothing to merge."
    return $EXIT_GIT_MANIFEST
  fi

  local verdict
  verdict=$(factory_verdict_path "$task")
  if [ ! -f "$verdict" ]; then
    log_error "No review verdict at $verdict; refusing to merge $task."
    return $EXIT_GIT_NO_VERDICT
  fi
  if ! jq -e '.verdict == "PASS"' "$verdict" >/dev/null 2>&1; then
    log_error "Verdict for $task is not PASS."
    return $EXIT_GIT_NO_VERDICT
  fi

  local name source worktree integration prd_branch base_sha head_sha v_base v_head source_head
  local -a merged_repos=()
  local -a merged_integrations=()
  local -a merged_pres=()

  # Validate everything before moving any branch.
  while IFS=$'\t' read -r name source source_head integration worktree base_sha prd_branch; do
    if [ ! -d "$worktree" ]; then
      log_error "$name: worktree is missing ($worktree)."
      return $EXIT_GIT_MANIFEST
    fi
    if [ ! -d "$integration" ]; then
      log_error "$name: integration worktree is missing ($integration)."
      return $EXIT_GIT_MANIFEST
    fi
    if [ "$(git -C "$source" rev-parse HEAD 2>/dev/null)" != "$source_head" ]; then
      log_error "$name: the operator checkout moved since prepare (expected ${source_head:0:8})."
      log_error "A coder must commit inside its worktree, not in workspace/$name."
      return $EXIT_GIT_SOURCE_MOVED
    fi
    if factory_repo_dirty "$source"; then
      log_error "$name: the operator checkout is dirty; refusing to merge."
      return $EXIT_GIT_SOURCE_MOVED
    fi

    head_sha=$(git -C "$worktree" rev-parse HEAD 2>/dev/null)
    v_base=$(jq -r --arg r "$name" '.reviewed[]? | select(.repo == $r) | .base_sha' "$verdict")
    v_head=$(jq -r --arg r "$name" '.reviewed[]? | select(.repo == $r) | .head_sha' "$verdict")
    if [ -z "$v_head" ] || [ "$v_head" != "$head_sha" ] || [ "$v_base" != "$base_sha" ]; then
      log_error "$name: verdict does not match the current commits."
      log_error "  reviewed base=${v_base:-none} head=${v_head:-none}"
      log_error "  current  base=${base_sha:0:8} head=${head_sha:0:8}"
      return $EXIT_GIT_VERDICT_STALE
    fi
  done < <(jq -r '.repos[] | [.name, .source, .source_head, .integration_worktree, .worktree, .base_sha, .prd_branch] | @tsv' "$manifest")

  # Merge each repo that has commits; remember where to roll back.
  while IFS=$'\t' read -r name integration worktree prd_branch; do
    local pre head
    pre=$(git -C "$integration" rev-parse HEAD 2>/dev/null)
    head=$(git -C "$worktree" rev-parse HEAD 2>/dev/null)

    if [ "$pre" = "$head" ] || [ -z "$(git -C "$worktree" rev-list --count "$pre..$head" 2>/dev/null)" ] \
       || [ "$(git -C "$worktree" rev-list --count "$pre..$head" 2>/dev/null)" = "0" ]; then
      continue
    fi

    if ! git -C "$integration" merge --no-ff --no-edit "$head" >/dev/null 2>&1; then
      git -C "$integration" merge --abort >/dev/null 2>&1 || true
      log_error "$name: merge conflict on $prd_branch; rolling back every repo."
      local i
      for i in "${!merged_integrations[@]}"; do
        git -C "${merged_integrations[$i]}" reset --hard "${merged_pres[$i]}" >/dev/null 2>&1 || true
        log_warn "  reset ${merged_repos[$i]} $prd_branch to ${merged_pres[$i]:0:8}"
      done
      return $EXIT_GIT_CONFLICT
    fi

    merged_repos+=("$name")
    merged_integrations+=("$integration")
    merged_pres+=("$pre")
    log_success "$name merged into $prd_branch"
  done < <(jq -r '.repos[] | [.name, .integration_worktree, .worktree, .prd_branch] | @tsv' "$manifest")

  factory_discard_task "$manifest" "$task"
  log_success "$task merged"
}

# ---------------------------------------------------------------------------
# abort
# ---------------------------------------------------------------------------

cmd_abort() {
  [ $# -eq 1 ] || { usage; return $EXIT_GIT_USAGE; }
  require_host abort || return $EXIT_GIT_USAGE
  local task="$1"

  local manifest=""
  if factory_load_prd "$task" >/dev/null 2>&1; then
    manifest=$(factory_manifest_path "$FACTORY_SLUG" "$task")
  fi

  if [ -z "$manifest" ] || [ ! -f "$manifest" ]; then
    # The manifest may be gone or unreadable; fall back to the directory.
    manifest=$(find "$(factory_root)" -maxdepth 4 -path "*/$task/.manifest.json" 2>/dev/null | head -1)
  fi

  if [ -n "$manifest" ] && [ -f "$manifest" ]; then
    factory_discard_task "$manifest" "$task"
    log_success "$task aborted; worktree and branch removed."
  else
    rm -f "$(factory_verdict_path "$task")" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/.agent/reports/$task.md" 2>/dev/null || true
    log_info "$task had nothing left to abort."
  fi

  # Prune administrative entries left by a crashed process.
  local repo
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    git -C "$repo" worktree prune >/dev/null 2>&1 || true
  done < <(factory_source_repos)
  return 0
}

# ---------------------------------------------------------------------------
# finish
# ---------------------------------------------------------------------------

cmd_finish() {
  [ $# -ge 1 ] || { usage; return $EXIT_GIT_USAGE; }
  local prd_id="$1"
  shift

  local push=false
  local push_only=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --push) push=true; shift ;;
      --push-only) push=true; push_only=true; shift ;;
      *) usage; return $EXIT_GIT_USAGE ;;
    esac
  done

  local prd="$SCRIPT_DIR/.agent/prd/$prd_id.md"
  if [ ! -f "$prd" ]; then
    log_error "PRD not found: $prd"
    return $EXIT_GIT_MANIFEST
  fi

  local slug type title branch
  slug=$(frontmatter_value "$prd" slug)
  type=$(factory_type "$(frontmatter_value "$prd" type)") || {
    log_error "$prd_id has an unknown type."
    return $EXIT_GIT_SLUG_MISSING
  }
  title=$(frontmatter_value "$prd" title)
  branch="$type/$slug"

  if ! factory_valid_slug "$slug"; then
    log_error "$prd_id has no valid slug."
    return $EXIT_GIT_SLUG_MISSING
  fi

  local integration_dir
  integration_dir="$(factory_slug_dir "$slug")/_integration"
  if [ ! -d "$integration_dir" ]; then
    log_error "No integration worktrees for $prd_id ($integration_dir)."
    return $EXIT_GIT_MANIFEST
  fi

  local name integration source base remote provider
  for integration in "$integration_dir"/*; do
    [ -d "$integration" ] || continue
    name=$(basename "$integration")
    source=$(factory_source_repo "$name")
    base=$(factory_base_branch "$source") || base="main"

    if [ ! -d "$source" ]; then
      log_warn "$name: source checkout is gone; skipping."
      continue
    fi

    local behind
    behind=$(git -C "$integration" rev-list --count "HEAD..$base" 2>/dev/null || echo "?")
    if [ "$behind" != "0" ] && [ "$behind" != "?" ]; then
      log_warn "$name: $base has $behind commit(s) not in $branch."
      log_warn "  run: git -C $source rebase $base $branch"
    fi

    remote=$(git -C "$source" remote get-url origin 2>/dev/null || true)
    printf '\n%s\n' "$name"
    if [ -z "$remote" ]; then
      log_warn "  no 'origin' remote; push skipped."
      continue
    fi

    # Detect provider from remote URL
    case "$remote" in
      *bitbucket.org*) provider="bitbucket" ;;
      *github.com*)    provider="github" ;;
      *)               provider="unknown" ;;
    esac

    printf '  git -C %s push -u origin %s\n' \
      "$(shell_quote "$source")" "$(shell_quote "$branch")"

    case "$provider" in
      bitbucket)
        printf '  # Bitbucket REST API (set BITBUCKET_API_TOKEN)\n'
        printf '  curl -X POST -H "Authorization: Bearer $BITBUCKET_API_TOKEN" \\\n'
        printf '    -H "Content-Type: application/json" \\\n'
        printf '    -d "{\"title\":\"%s\",\"description\":\"%s\",\"sourceBranch\":{\"name\":\"%s\"},\"destinationBranch\":{\"name\":\"%s\"},\"closeSourceBranch\":false}" \\\n' \
          "$type($slug): $title" "$(cat "$prd" | sed ':a;N;$!ba;s/\n/\\n/g; s/"/\\"/g')" "$branch" "$base"
        printf '    "https://api.bitbucket.org/2.0/repositories/%s/pullrequests"\n' \
          "$(echo "$remote" | sed -E 's/.*[:/]([^/]+)\/([^/.]+)(\.git)?$/\1\/\2/')"
        ;;
      github)
        printf '  gh -R %s pr create --base %s --head %s --title %s --body-file %s\n' \
          "$(shell_quote "$remote")" "$(shell_quote "$base")" "$(shell_quote "$branch")" \
          "$(shell_quote "$type($slug): $title")" "$(shell_quote "$prd")"
        ;;
      *)
        printf '  # Unknown provider; open PR manually\n'
        ;;
    esac

    if [ "$push" = false ]; then
      continue
    fi
    require_host "finish --push" || return $EXIT_GIT_USAGE

    if ! git -C "$source" push -u origin "$branch"; then
      log_error "$name: push failed."
      return $EXIT_GIT_USAGE
    fi

    if [ "$push_only" = false ]; then
      case "$provider" in
        bitbucket)
          if [ -z "${BITBUCKET_API_TOKEN:-}" ]; then
            log_warn "$name: BITBUCKET_API_TOKEN not set; PR not created."
          else
            local repo_slug
            repo_slug=$(echo "$remote" | sed -E 's/.*[:/]([^/]+)\/([^/.]+)(\.git)?$/\1\/\2/')
            local payload http_code
            payload=$(jq -n --arg title "$type($slug): $title" --rawfile desc "$prd" \
              --arg branch "$branch" --arg base "$base" \
              '{title: $title, description: $desc,
                source: {branch: {name: $branch}}, destination: {branch: {name: $base}},
                close_source_branch: false}') || payload=""
            if [ -z "$payload" ]; then
              log_warn "$name: jq unavailable; open the PR manually."
            else
              http_code=$(curl -s -o /tmp/opencode/bitbucket-pr-resp.json -w '%{http_code}' \
                -X POST -H "Authorization: Bearer ${BITBUCKET_API_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$payload" \
                "https://api.bitbucket.org/2.0/repositories/$repo_slug/pullrequests")
              case "$http_code" in
                200)
                  log_success "$name: Bitbucket PR created ($(cat /tmp/opencode/bitbucket-pr-resp.json | jq -r '.links.html.href // ""'))"
                  ;;
                *)
                  log_error "$name: Bitbucket PR create failed (HTTP $http_code): $(head -c 300 /tmp/opencode/bitbucket-pr-resp.json)"
                  ;;
              esac
            fi
          fi
          ;;
        github)
          if command -v gh >/dev/null 2>&1; then
            gh -R "$remote" pr create --base "$base" --head "$branch" \
              --title "$type($slug): $title" --body-file "$prd" || \
              log_warn "$name: gh pr create failed (a PR may already exist)."
          else
            log_warn "$name: gh not installed; open the PR manually."
          fi
          ;;
        *)
          log_warn "$name: unknown provider; open PR manually"
          ;;
      esac
    else
      log_info "$name: pushed branch $branch (--push-only, PR creation skipped)"
    fi
  done
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

main() {
  [ $# -ge 1 ] || { usage; return $EXIT_GIT_USAGE; }
  local cmd="$1"
  shift

  case "$cmd" in
    prepare) cmd_prepare "$@" ;;
    status)  cmd_status "$@" ;;
    merge)   cmd_merge "$@" ;;
    abort)   cmd_abort "$@" ;;
    finish)  cmd_finish "$@" ;;
    -h|--help|help) usage ;;
    *) usage ;;
  esac
}

main "$@"
exit $?
