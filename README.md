# Git worktree setup (two "desks")

## Overview

I use **one main clone** and **two persistent worktrees** ("desks") to work on multiple tasks concurrently—each desk has its own working dir, editor index, and dev servers, but all share the same Git object store.

On top of that, I use **Git Spice** for branch stacking and PR management, plus a couple of shell helpers:

- `nb` – create a new tracked branch from staged changes (one commit)
- `sb` – submit the current branch via `gs branch submit` with a clean title and empty-ish body

---

## Layout

```text
~/Desktop/backend          # main clone (owns .git)
~/Desktop/_wt/
  desk-1/                  # worktree 1
  desk-2/                  # worktree 2
````

---

## Branch model

* Each desk stays on a long-lived local branch that **tracks `origin/main`**:

  * `desk-1` → `main-desk-1`
  * `desk-2` → `main-desk-2`

* I do day-to-day work on these desk branches and spin off stacked feature branches with Git Spice when ready.

---

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
# load helper functions
for f in ~/.zshrc.d/*.zsh(N); do
  source "$f"
done
```

---

## Helpers (in `~/.zshrc.d/worktrees.zsh`)

Paste the following functions in `~/.zshrc.d/worktrees.zsh`.

### `gotomain` — jump to the right "main" for the current desk

```bash
gotomain() {
  local root wt_name target_branch

  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "gotomain: not in a git repo"
    return 1
  }

  wt_name="$(basename "$root")"

  if [[ "$wt_name" =~ ^desk-([A-Za-z0-9._-]+)$ ]]; then
    # desk-1 -> main-desk-1, desk-2 -> main-desk-2, etc.
    target_branch="main-$wt_name"
  else
    target_branch="main"
  fi

  # safety: refuse if that branch is checked out in another worktree
  local in_use_path
  in_use_path="$(git worktree list --porcelain \
    | awk -v b="refs/heads/$target_branch" '
        /^worktree /{p=$2}
        /^branch /{if ($2 == b) print p}
      ')"

  if [[ -n "$in_use_path" && "$in_use_path" != "$root" ]]; then
    echo "✖ '$target_branch' is already checked out in: $in_use_path"
    return 1
  fi

  git switch "$target_branch" || {
    echo "gotomain: could not switch to '$target_branch' (create it first?)"
    return 1
  }

  git status -sb
}
```

### `nb` — create a new branch with a single commit, tracked by Git Spice

`nb` assumes you’ve staged whatever you want to go into the *first commit* on the new branch.

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

  # remember the branch we started on (for stack behavior)
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

### `sb` — submit the current branch with a clean title & empty description

`sb` wraps `gs branch submit` so you always get:

* **Title** = the latest commit subject on the current branch.
* **Body** = effectively empty (just a single space, to stop Git Spice from auto-filling the huge commit timeline).

```bash
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
  if ! title="$(git log -1 --pretty=%s 2>/dev/null)"; then
    echo "sb: failed to read last commit on '$branch'" >&2
    return 1
  fi

  if [[ -z "$title" ]]; then
    echo "sb: last commit on '$branch' has an empty subject; refusing to submit" >&2
    return 1
  fi

  echo "sb: submitting '$branch' with title: \"$title\" and (effectively) empty description"

  # Use a single space for body, not an empty string,
  # so git-spice treats it as "provided" and does not auto-fill.
  gs --no-prompt branch submit \
    --branch "$branch" \
    --title "$title" \
    --body " " \
    "$@"
}
```

You can still pass additional flags to `gs branch submit` via `sb`, e.g.:

```bash
sb --draft
sb --update-only
```

---

## Daily workflow

* **Open desks**

  ```bash
  cd ~/Desktop/_wt/desk-1    # typically on main-desk-1
  cd ~/Desktop/_wt/desk-2    # typically on main-desk-2
  ```

* **Sync a desk with `main`**

  ```bash
  gotomain
  git pull --ff-only     # or: git pull --rebase
  ```

* **Start a feature from a desk**

  ```bash
  # 1) On a desk's main branch
  gotomain

  # 2) Stage changes for the initial commit
  git add path/to/files...

  # 3) Create a new gs-tracked branch and one commit from staged changes
  nb piercemaloney/ai-1380
  ```

* **Submit a branch via Git Spice**

  ```bash
  # from the feature branch
  sb
  # => PR title = last commit subject
  # => PR body  = effectively empty
  ```

* **Return to a desk's "main"**

  ```bash
  gotomain
  ```

---

## Why this works

* **Concurrency:** two isolated working dirs let tools (VS Code, dev servers, etc.) run independently.
* **Simplicity:** I rarely add/remove worktrees; I just switch branches within each desk.
* **Safety:** Git enforces **branch exclusivity** across worktrees (a branch can be checked out in only one worktree).
* **PR ergonomics:** `nb` + `sb` give a predictable “one commit per new branch, clean PR title/body” flow on top of Git Spice’s stacking model.

---

## Maintenance

```bash
git worktree list         # see all desks
git worktree prune        # clean stale entries if folders were deleted manually
git fetch --all --prune   # keep refs and remotes tidy
```

---

## Gotchas

* If Git says a branch is "already checked out," it's active in another desk—switch that desk away first.
* Avoid nesting worktrees inside the main repo; keep them as siblings in `~/Desktop/_wt`.
* `sb` always uses the **latest commit subject** on the current branch. If you want a different PR title, amend the commit or pass `--title` manually.

```
::contentReference[oaicite:0]{index=0}
```
