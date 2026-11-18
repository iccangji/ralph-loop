#!/bin/bash
# Fixture test for scripts/factory-git.sh
# Runs prepare/status/merge/abort/finish against throwaway repos in a temp dir.
# Usage: scripts/tests/factory-git-test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${TMPDIR:-/tmp}/factory-git-test.$$"
FAILED=0

# Everything this script touches lives under $WORK. Pinning cwd there means a
# failed `cd` cannot make a stray `git commit` land in the caller's repo.
mkdir -p "$WORK"
cd "$WORK" || exit 1

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; FAILED=1; }

expect_code() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$actual" = "$expected" ]; then pass "$label"; else fail "$label (expected $expected, got $actual)"; fi
}

expect_true() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

# --- build fixture ---------------------------------------------------------

ROOT="$WORK/proj"
mkdir -p "$ROOT/scripts/lib" "$ROOT/.agent/prd" "$ROOT/.agent/tasks" \
         "$ROOT/.agent/reports" "$ROOT/workspace"

cp "$REPO_ROOT/scripts/factory-git.sh" "$ROOT/scripts/"
cp "$REPO_ROOT/scripts/lib/constants.sh" "$ROOT/scripts/lib/"
cp "$REPO_ROOT/scripts/lib/logging.sh" "$ROOT/scripts/lib/"
cp "$REPO_ROOT/scripts/lib/factory.sh" "$ROOT/scripts/lib/"
chmod +x "$ROOT/scripts/factory-git.sh"

make_repo() {
  local path="$1" content="$2"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name Test
  printf '%s\n' "$content" > "$path/file.txt"
  git -C "$path" add file.txt
  git -C "$path" commit -q -m "init"
  git -C "$path" remote add origin "git@example.com:test/$(basename "$path").git"
}

make_repo "$ROOT/workspace/api" "api"
make_repo "$ROOT/workspace/web" "web"

cat > "$ROOT/.agent/prd/PRD-901.md" <<'EOF'
---
id: "PRD-901"
slug: "demo-feature"
type: "feat"
title: "Demo Feature"
created_at: "2026-11-18T10:00:00Z"
---

# Demo Feature
EOF

cat > "$ROOT/.agent/tasks/TASK-901.json" <<'EOF'
{"id":"TASK-901","title":"Demo","prd":".agent/prd/PRD-901.md","depends_on":[],
 "steps":["change file.txt"],"acceptance_criteria":["file.txt changed"]}
EOF

cat > "$ROOT/.agent/prd/PRD-902.md" <<'EOF'
---
id: "PRD-902"
title: "Legacy Without Slug"
created_at: "2026-11-18T10:00:00Z"
---

# Legacy
EOF

cat > "$ROOT/.agent/tasks/TASK-902.json" <<'EOF'
{"id":"TASK-902","title":"Legacy","prd":".agent/prd/PRD-902.md","depends_on":[],
 "steps":[],"acceptance_criteria":[]}
EOF
FG="$ROOT/scripts/factory-git.sh"
export RALPH_HOST=1

# --- prepare ---------------------------------------------------------------

"$FG" prepare TASK-901 --repos api,web >/dev/null 2>&1
expect_code 0 $? "prepare succeeds"

expect_true "api PRD branch created" git -C "$ROOT/workspace/api" show-ref --verify --quiet refs/heads/feat/demo-feature
expect_true "web PRD branch created" git -C "$ROOT/workspace/web" show-ref --verify --quiet refs/heads/feat/demo-feature
expect_true "api task branch created" git -C "$ROOT/workspace/api" show-ref --verify --quiet refs/heads/feat/demo-feature-TASK-901
expect_true "task worktree exists" test -d "$ROOT/workspace/.worktrees/demo-feature/TASK-901/api"
expect_true "integration worktree exists" test -d "$ROOT/workspace/.worktrees/demo-feature/_integration/api"
expect_true "manifest records both repos" \
  test "$(jq -r '.repos | length' "$ROOT/workspace/.worktrees/demo-feature/TASK-901/.manifest.json")" = 2
expect_true "source checkout still on main" \
  test "$(git -C "$ROOT/workspace/api" rev-parse --abbrev-ref HEAD)" = main

# prepare is idempotent
"$FG" prepare TASK-901 --repos api,web >/dev/null 2>&1
expect_code 0 $? "prepare is idempotent"

# --- status ----------------------------------------------------------------

STATUS=$("$FG" status TASK-901 2>&1)
if printf '%s' "$STATUS" | grep -q "feat/demo-feature-TASK-901"; then
  pass "status lists the task branch"
else
  fail "status lists the task branch"
fi

# --- merge guards ----------------------------------------------------------

"$FG" merge TASK-901 >/dev/null 2>&1
expect_code 12 $? "merge without a verdict is refused"

# coder commits inside the worktrees
API_TASK="$ROOT/workspace/.worktrees/demo-feature/TASK-901/api"
WEB_TASK="$ROOT/workspace/.worktrees/demo-feature/TASK-901/web"
printf 'api changed\n' >> "$API_TASK/file.txt"
git -C "$API_TASK" add file.txt && git -C "$API_TASK" commit -q -m "feat: api change"
API_HEAD=$(git -C "$API_TASK" rev-parse HEAD)

# commit the operator checkout to simulate a coder working in the wrong place
git -C "$ROOT/workspace/web" checkout -q -b side
printf 'web changed\n' >> "$WEB_TASK/file.txt"
git -C "$WEB_TASK" add file.txt && git -C "$WEB_TASK" commit -q -m "feat: web change"
WEB_HEAD=$(git -C "$WEB_TASK" rev-parse HEAD)
git -C "$ROOT/workspace/web" checkout -q main

BASE_API=$(jq -r '.repos[] | select(.name=="api") | .base_sha' \
  "$ROOT/workspace/.worktrees/demo-feature/TASK-901/.manifest.json")
BASE_WEB=$(jq -r '.repos[] | select(.name=="web") | .base_sha' \
  "$ROOT/workspace/.worktrees/demo-feature/TASK-901/.manifest.json")

cat > "$ROOT/.agent/reports/TASK-901.review.json" <<EOF
{"task_id":"TASK-901","verdict":"PASS",
 "reviewed":[{"repo":"api","base_sha":"$BASE_API","head_sha":"$API_HEAD"}],
 "defects":[]}
EOF

"$FG" merge TASK-901 >/dev/null 2>&1
expect_code 13 $? "verdict missing a repo is rejected"

cat > "$ROOT/.agent/reports/TASK-901.review.json" <<EOF
{"task_id":"TASK-901","verdict":"PASS",
 "reviewed":[
   {"repo":"api","base_sha":"$BASE_API","head_sha":"0000000000000000000000000000000000000000"},
   {"repo":"web","base_sha":"$BASE_WEB","head_sha":"$WEB_HEAD"}],
 "defects":[]}
EOF

"$FG" merge TASK-901 >/dev/null 2>&1
expect_code 13 $? "stale head sha is rejected"

cat > "$ROOT/.agent/reports/TASK-901.review.json" <<EOF
{"task_id":"TASK-901","verdict":"PASS",
 "reviewed":[
   {"repo":"api","base_sha":"$BASE_API","head_sha":"$API_HEAD"},
   {"repo":"web","base_sha":"$BASE_WEB","head_sha":"$WEB_HEAD"}],
 "defects":[]}
EOF

# --- merge success ---------------------------------------------------------

"$FG" merge TASK-901 >/dev/null 2>&1
expect_code 0 $? "merge succeeds with a matching verdict"

expect_true "PRD branch has a merge commit" \
  test "$(git -C "$ROOT/workspace/.worktrees/demo-feature/_integration/api" rev-list --merges --count feat/demo-feature)" = 1
expect_true "PRD branch contains the task change" \
  grep -q "api changed" "$ROOT/workspace/.worktrees/demo-feature/_integration/api/file.txt"
expect_true "task worktree removed after merge" \
  test ! -d "$ROOT/workspace/.worktrees/demo-feature/TASK-901"
expect_true "task branch deleted after merge" \
  bash -c "! git -C '$ROOT/workspace/api' show-ref --verify --quiet refs/heads/feat/demo-feature-TASK-901"
expect_true "verdict deleted after merge" test ! -f "$ROOT/.agent/reports/TASK-901.review.json"
expect_true "operator checkout untouched" \
  test "$(git -C "$ROOT/workspace/api" rev-parse HEAD)" != "$API_HEAD"

# --- abort -----------------------------------------------------------------

cat > "$ROOT/.agent/tasks/TASK-903.json" <<'EOF'
{"id":"TASK-903","title":"Abort me","prd":".agent/prd/PRD-901.md","depends_on":[],
 "steps":[],"acceptance_criteria":[]}
EOF

"$FG" prepare TASK-903 --repos api >/dev/null 2>&1
expect_code 0 $? "second task prepares"
"$FG" abort TASK-903 >/dev/null 2>&1
expect_code 0 $? "abort succeeds"
expect_true "abort removed the worktree" test ! -d "$ROOT/workspace/.worktrees/demo-feature/TASK-903"
expect_true "abort deleted the task branch" \
  bash -c "! git -C '$ROOT/workspace/api' show-ref --verify --quiet refs/heads/feat/demo-feature-TASK-903"

# --- conflict --------------------------------------------------------------

cat > "$ROOT/.agent/tasks/TASK-904.json" <<'EOF'
{"id":"TASK-904","title":"Conflict","prd":".agent/prd/PRD-901.md","depends_on":[],
 "steps":[],"acceptance_criteria":[]}
EOF

"$FG" prepare TASK-904 --repos api,web >/dev/null 2>&1
API_INTEG="$ROOT/workspace/.worktrees/demo-feature/_integration/api"
WEB_INTEG="$ROOT/workspace/.worktrees/demo-feature/_integration/web"

# Two tasks that edit the same line differently guarantee a conflict when the
# second is merged. Simulate by committing to web directly on the PRD branch,
# then have the task branch touch the same line.
printf 'conflicting line from integration\n' > "$WEB_INTEG/conflict.txt"
git -C "$WEB_INTEG" add conflict.txt && git -C "$WEB_INTEG" commit -q -m "chore: integration edit"

TASK904_WEB="$ROOT/workspace/.worktrees/demo-feature/TASK-904/web"
TASK904_API="$ROOT/workspace/.worktrees/demo-feature/TASK-904/api"
printf 'conflicting line from task\n' > "$TASK904_WEB/conflict.txt"
git -C "$TASK904_WEB" add conflict.txt && git -C "$TASK904_WEB" commit -q -m "feat: task edit"
WEB_TASK_HEAD=$(git -C "$TASK904_WEB" rev-parse HEAD)
printf 'harmless\n' >> "$TASK904_API/file.txt"
git -C "$TASK904_API" add file.txt && git -C "$TASK904_API" commit -q -m "feat: harmless api edit"
API_TASK_HEAD=$(git -C "$TASK904_API" rev-parse HEAD)

BASE2_API=$(jq -r '.repos[] | select(.name=="api") | .base_sha' \
  "$ROOT/workspace/.worktrees/demo-feature/TASK-904/.manifest.json")
BASE2_WEB=$(jq -r '.repos[] | select(.name=="web") | .base_sha' \
  "$ROOT/workspace/.worktrees/demo-feature/TASK-904/.manifest.json")

cat > "$ROOT/.agent/reports/TASK-904.review.json" <<EOF
{"task_id":"TASK-904","verdict":"PASS",
 "reviewed":[
   {"repo":"api","base_sha":"$BASE2_API","head_sha":"$API_TASK_HEAD"},
   {"repo":"web","base_sha":"$BASE2_WEB","head_sha":"$WEB_TASK_HEAD"}],
 "defects":[]}
EOF

API_PRE=$(git -C "$API_INTEG" rev-parse feat/demo-feature)
"$FG" merge TASK-904 >/dev/null 2>&1
expect_code 11 $? "conflict is reported"

expect_true "api PRD branch rolled back" \
  test "$(git -C "$API_INTEG" rev-parse feat/demo-feature)" = "$API_PRE"
expect_true "task worktree survives a failed merge" \
  test -d "$ROOT/workspace/.worktrees/demo-feature/TASK-904/web"

"$FG" abort TASK-904 >/dev/null 2>&1

# --- finish ----------------------------------------------------------------

OUT=$("$FG" finish PRD-901 2>&1)
expect_code 0 $? "finish exits zero"
if printf '%s' "$OUT" | grep -q "push -u origin 'feat/demo-feature'"; then
  pass "finish prints the push command"
else
  fail "finish prints the push command"
fi
if printf '%s' "$OUT" | grep -q "feat(demo-feature): Demo Feature"; then
  pass "finish prints the PR title"
else
  fail "finish prints the PR title"
fi

# --- validation ------------------------------------------------------------

"$FG" prepare TASK-902 --repos api >/dev/null 2>&1
expect_code 15 $? "PRD without a slug is refused"

env -u RALPH_HOST "$FG" merge TASK-901 >/dev/null 2>&1
expect_code 10 $? "merge without RALPH_HOST is refused"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "all checks passed"
  exit 0
fi
echo "some checks failed"
exit 1
