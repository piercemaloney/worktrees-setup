# Git worktree setup (two "desks")

## Overview

I use **one main clone** and **two persistent worktrees** ("desks") to work on multiple tasks concurrently—each desk has its own working dir, editor index, and dev servers, but all share the same Git object store.

## Layout

```
~/Desktop/backend          # main clone (owns .git)
~/Desktop/_wt/
  desk-1/                  # worktree 1
  desk-2/                  # worktree 2
```

## Branch model

- Each desk stays on a long-lived local branch that **tracks `origin/main`**:

  - `desk-1` → `main-desk-1`
  - `desk-2` → `main-desk-2`

- I do day-to-day work on these desk branches and "promote" feature branches with Git Spice when ready.

## One-time creation (already done)

```bash
cd ~/Desktop/backend
git fetch --all --prune
mkdir -p ../_wt
git worktree add ../_wt/desk-1 -b main-desk-1 origin/main
git -C ../_wt/desk-1 branch --set-upstream-to=origin/main main-desk-1
git worktree add ../_wt/desk-2 -b main-desk-2 origin/main
git -C ../_wt/desk-2 branch --set-upstream-to=origin/main main-desk-2
```

Additionally, to have these functions available in your shell:

```bash
mkdir -p ~/.zshrc.d
touch ~/.zshrc.d/worktrees.zsh
```

And then add the following to your `~/.zshrc`:

```bash
# functions
for f in ~/.zshrc.d/*.zsh(N); do
  source "$f"
done
```

## Helpers (in `~/.zshrc.d/worktrees.zsh`)

Paste the following functions in your `~/.zshrc.d/worktrees.zsh`.

### `gotomain` — jump to the right "main" for the current dir

```bash
gotomain() {
  local root wt_name target_branch
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repo"; return 1; }
  wt_name="$(basename "$root")"
  [[ "$wt_name" =~ ^desk-([A-Za-z0-9._-]+)$ ]] && target_branch="main-$wt_name" || target_branch="main"
  # optional safety: refuse if checked out in another worktree
  local in_use_path
  in_use_path="$(git worktree list --porcelain | awk -v b="refs/heads/$target_branch" '/^worktree /{p=$2} /^branch /{if($2==b)print p}')"
  [[ -n "$in_use_path" && "$in_use_path" != "$root" ]] && { echo "✖ '$target_branch' is in $in_use_path"; return 1; }
  git switch "$target_branch" || { echo "Could not switch to '$target_branch' (create it first)."; return 1; }
  git status -sb
}
```

### `nb` — create a new branch with Git Spice tracking

```bash
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
```

## Daily workflow

- **Open desks**

  ```bash
  cd ~/Desktop/_wt/desk-1    # on main-desk-1
  cd ~/Desktop/_wt/desk-2    # on main-desk-2
  ```

- **Sync a desk with `main`**

  ```bash
  gotomain
  git pull --ff-only     # or: git pull --rebase
  ```

- **Start a feature from a desk**

  ```bash
  # while on main-desk-1
  nb piercemaloney/ai-1380
  ```

- **Return to desk's "main"**

  ```bash
  gotomain
  ```

## Why this works

- **Concurrency:** two isolated working dirs let tools (Claude/VS Code) index/run independently.
- **Simplicity:** I rarely add/remove worktrees; I just switch branches within each desk.
- **Safety:** Git enforces **branch exclusivity** across worktrees (a branch can be checked out in only one).

## Maintenance

```bash
git worktree list         # see all desks
git worktree prune        # clean stale entries if folders were deleted manually
git fetch --all --prune   # keep refs tidy
```

## Gotchas

- If Git says a branch is "already checked out," it's active in another desk—switch that desk away first.
- Avoid nesting worktrees inside the main repo; keep them as siblings in `~/Desktop/_wt`.
