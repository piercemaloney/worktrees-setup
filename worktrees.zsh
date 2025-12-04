# gotomain: switch to the "main" branch for this worktree
# - if repo root dir is desk-<x>  -> switch to main-desk-<x>
# - otherwise                     -> switch to main
gotomain() {
  # must be inside a git repo
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repo"; return 1; }

  local wt_name target_branch
  wt_name="$(basename "$root")"

  if [[ "$wt_name" =~ ^desk-([A-Za-z0-9._-]+)$ ]]; then
    # wt_name is "desk-<x>" -> target is "main-desk-<x>"
    target_branch="main-$wt_name"
  else
    target_branch="main"
  fi

  # optional safety: avoid switching if that branch is in another worktree
  local in_use_path
  in_use_path="$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$target_branch" '
    /^worktree /{p=$2} /^branch /{if($2==b){print p}}
  ')"
  if [[ -n "$in_use_path" && "$in_use_path" != "$root" ]]; then
    echo "✖ '$target_branch' is already checked out at: $in_use_path"
    return 1
  fi

  # just try to switch; if it doesn't exist locally, fail loudly
  git switch "$target_branch" || {
    echo "Could not switch to '$target_branch'. Does it exist locally?"
    echo "Tip: create it first (tracking origin/main) from your main clone:"
    echo "  git branch $target_branch origin/main"
    return 1
  }

  git status -sb
}


# nb <new-branch-name>
# - requires that you already have staged changes
# - creates a new branch from current HEAD
# - gs b track  (tracks the new branch)
# - gs cc       (commits the currently staged changes)
# - gs us o main (stacks onto main) ONLY if invoked from main/main-desk-1/main-desk-2
nb() {
  # require a branch name
  if [[ -z "$1" ]]; then
    echo "usage: nb <new-branch-name>"
    return 1
  fi

  # ensure we're in a git repo
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "nb: not inside a git repository"
    return 1
  fi

  local newb="$1"
  # remember the branch we started on (for the stack rule)
  local start_branch
  start_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1

  # fail early if there are no staged changes
  if git diff --cached --quiet; then
    echo "nb: no staged changes to commit."
    echo "    Stage what you want on '$start_branch' (git add ...) and then run: nb $newb"
    return 1
  fi

  # guard: don't clobber existing branch name
  if git rev-parse --verify --quiet "$newb" >/dev/null; then
    echo "nb: branch '$newb' already exists"
    return 1
  fi

  # create/switch to the new branch
  git switch -c "$newb" || return 1

  # track the new branch with git-spice
  if ! gs b track; then
    echo "nb: 'gs b track' failed"
    return 1
  fi

  # commit the currently staged changes BEFORE messing with the stack
  if ! gs cc; then
    echo "nb: 'gs cc' failed"
    return 1
  fi

  # only stack onto main if we *invoked* nb from one of these mains
  case "$start_branch" in
    main|main-desk-1|main-desk-2)
      if ! gs us o main; then
        echo "nb: 'gs us o main' failed"
        return 1
      fi
      ;;
    *) : ;; # do nothing
  esac

  echo "✅ Created '$newb' from '$start_branch'$( [[ "$start_branch" =~ ^(main|main-desk-1|main-desk-2)$ ]] && echo ', stacked onto main' )."
}


# sb <optional branch name>
# - grabs latest commit subject on branch
# - calls `gs bs` with args setting PR title to commit name
sb() {
  # ensure we're in a git repo
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "sb: not inside a git repository" >&2
    return 1
  fi

  # current branch
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1

  # last commit subject for this branch
  local title
  title="$(git log -1 --pretty=%s 2>/dev/null)" || title="WIP"

  if [[ -z "$title" ]]; then
    echo "sb: no commits on '$branch', nothing to submit" >&2
    return 1
  fi

  echo "sb: submitting '$branch' with title: \"$title\" and (effectively) empty description"

  # NOTE: use a single space for body, not an empty string,
  # so git-spice treats it as "provided" and doesn't try to auto-fill.
  gs --no-prompt branch submit \
    --branch "$branch" \
    --title "$title" \
    --body " " \
    "$@"
}
