#!/bin/bash
# Factory git helpers for ralph.sh
# PRD frontmatter parsing, manifest read/write, branch naming, worktree setup
# Dependencies: constants.sh, logging.sh
#
# Layout (per PRD):
#   workspace/.worktrees/{slug}/_integration/{repo}   on {type}/{slug}
#   workspace/.worktrees/{slug}/TASK-{id}/{repo}      on {type}/{slug}/TASK-{id}
#
# The operator's checkout at workspace/{repo} is never moved by any of this.

FACTORY_PRDS=(feat fix refactor chore docs test perf)

# Root that holds every worktree. Sits under workspace/ because opencode denies
# external_directory outside it.
factory_root() {
  printf '%s/workspace/.worktrees' "$SCRIPT_DIR"
}

# Read one key from a Markdown file's YAML frontmatter.
# Only the leading block is scanned, so a `title:` in the body is ignored.
# Usage: value=$(frontmatter_value file.md slug)
frontmatter_value() {
  local file="$1"
  local key="$2"
  [ -f "$file" ] || return 1

  awk -v key="$key" '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR == 1 { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm {
      line = $0
      if (line ~ "^" key "[[:space:]]*:") {
        sub("^" key "[[:space:]]*:[[:space:]]*", "", line)
        gsub(/^["\047]|["\047]$/, "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
        exit
      }
    }
  ' "$file"
}

# Path to a task spec inside the repo.
# Usage: spec=$(task_spec_path TASK-003)
task_spec_path() {
  printf '%s/.agent/tasks/%s.json' "$SCRIPT_DIR" "$1"
}

# PRD file a task points at, resolved from its spec.
# Usage: prd=$(task_prd_file TASK-003)
task_prd_file() {
  local spec
  spec=$(task_spec_path "$1")
  [ -f "$spec" ] || return 1

  local prd
  prd=$(jq -r '.prd // empty' "$spec" 2>/dev/null)
  [ -n "$prd" ] || return 1

  case "$prd" in
    /*) printf '%s' "$prd" ;;
    *) printf '%s/%s' "$SCRIPT_DIR" "$prd" ;;
  esac
}

# Validate the semantic slug used in branch names.
# Usage: if factory_valid_slug "$slug"; then ...
factory_valid_slug() {
  local slug="$1"
  [ -n "$slug" ] || return 1
  [ ${#slug} -le 40 ] || return 1
  printf '%s' "$slug" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
}

# Normalize a PRD type, defaulting to feat and rejecting unknown ones.
factory_type() {
  local type="${1:-feat}"
  local known

  for known in "${FACTORY_PRDS[@]}"; do
    if [ "$type" = "$known" ]; then
      printf '%s' "$type"
      return 0
    fi
  done
  return 1
}

# Load and validate the PRD that owns a task.
# Populates: FACTORY_PRD_FILE, FACTORY_PRD_ID, FACTORY_SLUG, FACTORY_TYPE,
#            FACTORY_TITLE, FACTORY_BRANCH
# Usage: factory_load_prd TASK-003
factory_load_prd() {
  local task="$1"
  local prd

  prd=$(task_prd_file "$task") || {
    log_error "$task has no readable 'prd' field in its spec."
    return $EXIT_GIT_MANIFEST
  }
  [ -f "$prd" ] || {
    log_error "PRD file not found: $prd"
    return $EXIT_GIT_MANIFEST
  }

  FACTORY_PRD_FILE="$prd"
  FACTORY_PRD_ID=$(frontmatter_value "$prd" id)
  FACTORY_TITLE=$(frontmatter_value "$prd" title)
  FACTORY_SLUG=$(frontmatter_value "$prd" slug)
  local raw_type
  raw_type=$(frontmatter_value "$prd" type)

  if [ -z "$FACTORY_PRD_ID" ]; then
    FACTORY_PRD_ID=$(basename "$prd" .md)
  fi

  if ! factory_valid_slug "$FACTORY_SLUG"; then
    log_error "$(basename "$prd") has no valid slug; add 'slug: <kebab-case>' to its frontmatter."
    return $EXIT_GIT_SLUG_MISSING
  fi

  if ! FACTORY_TYPE=$(factory_type "$raw_type"); then
    log_error "$(basename "$prd") has unknown type '$raw_type'; expected one of: ${FACTORY_PRDS[*]}"
    return $EXIT_GIT_SLUG_MISSING
  fi

  # A slug must identify exactly one PRD; reusing it would merge two PRDs.
  local other
  while IFS= read -r other; do
    [ -n "$other" ] || continue
    [ "$other" = "$prd" ] && continue
    if [ "$(frontmatter_value "$other" slug)" = "$FACTORY_SLUG" ]; then
      log_error "slug '$FACTORY_SLUG' is already used by $(basename "$other")."
      return $EXIT_GIT_SLUG_COLLISION
    fi
  done < <(find "$SCRIPT_DIR/.agent/prd" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)

  FACTORY_BRANCH="$FACTORY_TYPE/$FACTORY_SLUG"
  return 0
}

# Worktree paths for one task, derived from its slug and id.
factory_slug_dir() {
  printf '%s/%s' "$(factory_root)" "$1"
}

factory_integration_worktree() {
  printf '%s/_integration/%s' "$(factory_slug_dir "$1")" "$2"
}

factory_task_root() {
  printf '%s/%s' "$(factory_slug_dir "$1")" "$2"
}

factory_task_worktree() {
  printf '%s/%s/%s' "$(factory_slug_dir "$1")" "$2" "$3"
}

# Task branches are siblings of the PRD branch, not children: git cannot hold
# both refs/heads/feat/x and refs/heads/feat/x/TASK-1.
factory_task_branch() {
  printf '%s/%s-%s' "$1" "$2" "$3"
}

factory_manifest_path() {
  printf '%s/.manifest.json' "$(factory_task_root "$1" "$2")"
}

factory_verdict_path() {
  printf '%s/.agent/reports/%s.review.json' "$SCRIPT_DIR" "$1"
}

# Absolute path of a workspace repo by name. `.` and `workspace` both mean the
# single-repo layout where workspace/ itself is the repository.
# Usage: source=$(factory_source_repo simple-notes-api)
factory_source_repo() {
  local name="$1"
  case "$name" in
    .|workspace) printf '%s/workspace' "$SCRIPT_DIR" ;;
    *) printf '%s/workspace/%s' "$SCRIPT_DIR" "$name" ;;
  esac
}

# Resolve the branch a PRD branches from: RALPH_BASE_BRANCH, then main, then
# master. Only local branches count; a stale remote ref would silently branch
# off commits nobody has.
# Usage: base=$(factory_base_branch "$repo")
factory_base_branch() {
  local repo="$1"
  local candidate
  local -a candidates=()

  [ -n "${RALPH_BASE_BRANCH:-}" ] && candidates+=("$RALPH_BASE_BRANCH")
  candidates+=(main master)

  for candidate in "${candidates[@]}"; do
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# Keep worktrees out of `git status` without touching the tracked .gitignore.
# Usage: factory_exclude_worktrees "$repo"
factory_exclude_worktrees() {
  local repo="$1"
  local exclude="$repo/.git/info/exclude"

  # Linked worktrees have a .git file, not a directory.
  [ -d "$repo/.git" ] || return 0
  mkdir -p "$repo/.git/info" || return 0
  touch "$exclude" || return 0

  grep -qxF '.worktrees/' "$exclude" 2>/dev/null && return 0
  printf '.worktrees/\n' >> "$exclude"
}

# Link node_modules and copy env files into a fresh worktree. Git carries
# neither, and a coder that cannot install dependencies fails every task.
# Env files are copied, never linked, so a task cannot edit operator secrets.
# Usage: factory_hydrate_worktree "$source" "$worktree"
factory_hydrate_worktree() {
  local source="$1"
  local worktree="$2"
  [ -d "$worktree" ] || return 0

  if [ -d "$source/node_modules" ] && [ ! -e "$worktree/node_modules" ]; then
    ln -s "$source/node_modules" "$worktree/node_modules" 2>/dev/null || true
  fi

  local env_file
  for env_file in "$source"/.env "$source"/.env.*; do
    [ -f "$env_file" ] || continue
    [ -e "$worktree/$(basename "$env_file")" ] && continue
    cp "$env_file" "$worktree/$(basename "$env_file")" 2>/dev/null || true
  done
}

# True when the repo has uncommitted changes, including untracked files.
factory_repo_dirty() {
  local repo="$1"
  [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]
}

# Create or reuse the integration worktree that owns the PRD branch.
# Echoes the worktree path and the PRD branch tip SHA on success.
# Usage: read -r path sha < <(factory_ensure_integration "$repo" "$name" "$slug" "$type")
factory_ensure_integration() {
  local repo="$1"
  local name="$2"
  local slug="$3"
  local type="$4"
  local branch="$type/$slug"
  local path

  path=$(factory_integration_worktree "$slug" "$name")

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    local base
    base=$(factory_base_branch "$repo") || {
      log_error "$name has neither '$branch' nor a main/master base branch."
      return $EXIT_GIT_USAGE
    }
    git -C "$repo" branch "$branch" "$base" >/dev/null 2>&1 || return $EXIT_GIT_USAGE
  fi

  if [ ! -d "$path" ]; then
    mkdir -p "$(dirname "$path")"
    git -C "$repo" worktree add "$path" "$branch" >/dev/null 2>&1 || return $EXIT_GIT_USAGE
  fi

  printf '%s %s\n' "$path" "$(git -C "$path" rev-parse HEAD 2>/dev/null)"
}

# Write the task manifest. Args are the values collected by cmd_prepare.
# Usage: factory_write_manifest <<< "$json"
factory_write_manifest() {
  local path="$1"
  local json="$2"
  mkdir -p "$(dirname "$path")" || return 1
  printf '%s\n' "$json" > "$path"
}

# Read one field from the manifest for a repo entry.
# Usage: sha=$(factory_manifest_field "$manifest" simple-notes-api base_sha)
factory_manifest_field() {
  local manifest="$1"
  local repo="$2"
  local field="$3"
  jq -r --arg r "$repo" --arg f "$field" \
    '(.repos[] | select(.name == $r) | .[$f]) // empty' "$manifest" 2>/dev/null
}

factory_manifest_exists() {
  [ -f "$(factory_manifest_path "$2" "$1")" ]
}

# Task ids are the only naming input a task needs; every path is derived.
factory_task_slug() {
  local task="$1"
  factory_load_prd "$task" >/dev/null || return 1
  printf '%s' "$FACTORY_SLUG"
}

factory_task_prd_id() {
  local task="$1"
  factory_load_prd "$task" >/dev/null || return 1
  printf '%s' "$FACTORY_PRD_ID"
}

# Remove every trace of a task: worktrees, task branches, manifest, task dir,
# verdict, and report. Never touches the PRD branch or the integration worktree.
# Usage: factory_discard_task "$manifest" TASK-003
factory_discard_task() {
  local manifest="$1"
  local task="$2"

  if [ -f "$manifest" ]; then
    local name source worktree branch
    while IFS=$'\t' read -r name source worktree branch; do
      [ -n "$name" ] || continue
      if [ -d "$worktree" ]; then
        git -C "$source" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
      fi
      git -C "$source" branch -D "$branch" >/dev/null 2>&1 || true
    done < <(jq -r '.repos[] | [.name, .source, .worktree, .task_branch] | @tsv' "$manifest" 2>/dev/null)

    rm -rf "$(dirname "$manifest")"
  fi

  rm -f "$(factory_verdict_path "$task")" 2>/dev/null || true
  rm -f "$SCRIPT_DIR/.agent/reports/$task.md" 2>/dev/null || true
}

# Workspace repos, one path per line. Worktrees are skipped because their .git
# is a file, and a nested repo would otherwise be treated as a source.
factory_source_repos() {
  local ws="$SCRIPT_DIR/workspace"
  local gitdir

  if [ -d "$ws/.git" ]; then
    printf '%s\n' "$ws"
    return 0
  fi

  find "$ws" -maxdepth 2 -name .git -type d 2>/dev/null | while IFS= read -r gitdir; do
    dirname "$gitdir"
  done
}

# A run that crashes leaves worktrees and branches behind. No task can be live
# before the loop starts, so discarding every manifest at boot is safe.
# Usage: factory_cleanup_orphans
factory_cleanup_orphans() {
  local manifest task slug

  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    task=$(jq -r '.task_id // empty' "$manifest" 2>/dev/null)
    slug=$(jq -r '.slug // empty' "$manifest" 2>/dev/null)
    if [ -z "$task" ] || [ -z "$slug" ]; then
      log_warn "Ignoring unreadable manifest: $manifest"
      continue
    fi
    log_warn "Discarding orphaned task $task from a previous run."
    factory_discard_task "$manifest" "$task"
  done < <(find "$(factory_root)" -maxdepth 3 -name .manifest.json 2>/dev/null)

  local repo
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    git -C "$repo" worktree prune >/dev/null 2>&1 || true
  done < <(factory_source_repos)
}

# Selection runs across every PRD. Interleaving is allowed, but more than one
# live PRD means more than one branch in flight, which is worth saying out loud.
# Usage: factory_warn_multiple_prds
factory_warn_multiple_prds() {
  local tasks_index="$SCRIPT_DIR/.agent/tasks.json"
  [ -f "$tasks_index" ] || return 0

  local prds
  prds=$(
    jq -r '.[] | select(.status == "pending") | .id' "$tasks_index" 2>/dev/null \
      | while IFS= read -r id; do
          jq -r '.prd // empty' "$SCRIPT_DIR/.agent/tasks/$id.json" 2>/dev/null
        done \
      | sort -u
  )

  local count
  count=$(printf '%s\n' "$prds" | grep -c . || true)
  if [ "$count" -gt 1 ]; then
    log_warn "Pending tasks span $count PRDs; their branches will interleave."
  fi
}

# Print `finish` (or run it with --push if AUTO_PUBLISH=true) for every PRD
# whose tasks are all completed and which has a PRD branch.
# Usage: factory_finish_completed_prds [push_flag]
factory_finish_completed_prds() {
  local push="${1:-false}"
  local prd prd_name slug spec id status all_done printed=0

  for prd in "$SCRIPT_DIR"/.agent/prd/*.md; do
    [ -f "$prd" ] || continue
    prd_name=$(basename "$prd" .md)
    slug=$(frontmatter_value "$prd" slug)
    factory_valid_slug "$slug" || continue
    [ -d "$(factory_slug_dir "$slug")/_integration" ] || continue

    all_done=true
    while IFS= read -r spec; do
      [ -n "$spec" ] || continue
      if [ "$(jq -r '.prd // empty' "$spec" 2>/dev/null)" != ".agent/prd/$prd_name.md" ]; then
        continue
      fi
      id=$(jq -r '.id // empty' "$spec" 2>/dev/null)
      status=$(jq -r --arg id "$id" '.[] | select(.id == $id) | .status' \
        "$SCRIPT_DIR/.agent/tasks.json" 2>/dev/null)
      if [ "$status" != "completed" ]; then
        all_done=false
        break
      fi
    done < <(find "$SCRIPT_DIR/.agent/tasks" -maxdepth 1 -name '*.json' -type f 2>/dev/null | sort)

    [ "$all_done" = true ] || continue

    if [ "$printed" -eq 0 ]; then
      echo ""
      if [ "$push" = true ]; then
        log_info "Publishing completed PRD branches:"
      else
        log_info "PRD branches are ready to publish:"
      fi
      printed=1
    fi

    if [ "$push" = true ]; then
      RALPH_HOST=1 "$SCRIPT_DIR/scripts/factory-git.sh" finish "$prd_name" --push || true
    else
      "$SCRIPT_DIR/scripts/factory-git.sh" finish "$prd_name" 2>/dev/null || true
    fi
  done
}

# Backwards-compatible alias: print-only
factory_print_finish_commands() {
  factory_finish_completed_prds false
}

