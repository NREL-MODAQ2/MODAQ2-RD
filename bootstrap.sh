#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# bootstrap.sh
#
# Clones a set of repositories (listed below) from their default remote and:
#   1) checks out the latest from origin/main
#   2) creates/switches to a target branch you specify (TARGET_BRANCH)
#
# Usage:
#   ./bootstrap.sh
#
# Optional environment overrides:
#   TARGET_BRANCH=my-feature ./bootstrap.sh
#   DEST_DIR=/path/to/workspace ./bootstrap.sh
# ------------------------------------------------------------------------------

TARGET_BRANCH="${TARGET_BRANCH:-clean-up-submodules}"   # branch you want to end on locally
BASE_BRANCH="${BASE_BRANCH:-main}"                      # branch to clone/pull from remote
DEST_DIR="${DEST_DIR:-$PWD/src}"           # where to clone repos

# If a repo uses "master" instead of "main", add it here (key=repo_name, value=branch)
declare -A REPO_BASE_BRANCH_OVERRIDE=(
  # ["some_repo"]="master"
)

REPOS=(
  "https://github.com/MODAQ2/m2_core.git"
  "https://github.com/MODAQ2/adnav_gnss_compass.git"
  "https://github.com/MODAQ2/rosbridge_server_m2.git"
  "https://github.com/MODAQ2/m2_hmi.git"
  "https://github.com/MODAQ2/m2_control.git"
  "https://github.com/MODAQ2/labjack_t8_ros2.git"
  "https://github.com/MODAQ2/ed582_driver.git"
  "https://github.com/MODAQ2/bag_recorder.git"
  "https://github.com/MODAQ2/bluespace_ai_xsens_ros_mti_driver.git"
)

die() { echo "Error: $*" >&2; exit 1; }

repo_dir_from_url() {
  local url="$1"
  local name
  name="$(basename "$url")"      # e.g. m2_core.git
  name="${name%.git}"            # e.g. m2_core
  printf "%s" "$name"
}

ensure_repo() {
  local url="$1"
  local dir="$2"

  if [[ -d "$dir/.git" ]]; then
    echo "==> Using existing repo: $dir"
    git -C "$dir" remote set-url origin "$url" >/dev/null 2>&1 || true
    git -C "$dir" fetch --prune origin
  else
    echo "==> Cloning: $url -> $dir"
    git clone "$url" "$dir"
  fi
}

checkout_latest_base_branch() {
  local dir="$1"
  local base_branch="$2"

  echo "==> Checkout latest origin/$base_branch in $dir"
  git -C "$dir" fetch --prune origin

  # Ensure the remote branch exists
  if ! git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
    die "$dir: remote branch origin/$base_branch does not exist"
  fi

  # Switch to base branch (create tracking if needed), then fast-forward
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$base_branch"; then
    git -C "$dir" switch "$base_branch"
  else
    git -C "$dir" switch -c "$base_branch" --track "origin/$base_branch"
  fi

  git -C "$dir" pull --ff-only origin "$base_branch"
}

switch_or_create_target_branch() {
  local dir="$1"
  local base_branch="$2"
  local target_branch="$3"

  if [[ "$target_branch" == "$base_branch" ]]; then
    echo "==> Target branch equals base branch ($base_branch); nothing to do in $dir"
    return 0
  fi

  echo "==> Switch/create target branch '$target_branch' from '$base_branch' in $dir"

  # If target branch exists locally, switch to it
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$target_branch"; then
    git -C "$dir" switch "$target_branch"
    return 0
  fi

  # If target branch exists on origin, track it; else create from base
  if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$target_branch"; then
    git -C "$dir" switch -c "$target_branch" --track "origin/$target_branch"
  else
    git -C "$dir" switch -c "$target_branch" "$base_branch"
  fi
}

main() {
  mkdir -p "$DEST_DIR"
  echo "Workspace: $DEST_DIR"
  echo "Base branch: $BASE_BRANCH"
  echo "Target branch: $TARGET_BRANCH"
  echo

  for url in "${REPOS[@]}"; do
    repo="$(repo_dir_from_url "$url")"
    dir="$DEST_DIR/$repo"

    base_branch="${REPO_BASE_BRANCH_OVERRIDE[$repo]:-$BASE_BRANCH}"

    echo "------------------------------------------------------------------------------"
    echo "Repo: $repo"
    echo "URL : $url"
    echo "Base: $base_branch"
    echo "Dest: $dir"

    ensure_repo "$url" "$dir"
    checkout_latest_base_branch "$dir" "$base_branch"
    switch_or_create_target_branch "$dir" "$base_branch" "$TARGET_BRANCH"

    echo "==> Done: $repo (on $(git -C "$dir" rev-parse --abbrev-ref HEAD))"
    echo
  done

  echo "All repositories processed."
}

main "$@"