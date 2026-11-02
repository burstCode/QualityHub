#!/usr/bin/env bash
set -Eeuo pipefail

# Run as the deployment user, with Docker access and repository read access.
revision=${1:?Usage: bash scripts/deploy.sh COMMIT_SHA BRANCH}
branch=${2:?Expected branch: master or develop}
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'Expected a full commit SHA.' >&2; exit 1; }
[[ "$branch" == master || "$branch" == develop ]] || { echo 'Unsupported deployment branch.' >&2; exit 1; }
root=${QUALITYHUB_DIR:-/home/burstlimit/apps/qualityhub}
cd "$root"
[[ -f deploy/.env ]] || { echo 'Missing deploy/.env.' >&2; exit 1; }
[[ -z $(git status --porcelain --untracked-files=normal) ]] || {
  echo 'Server checkout has local changes. Preserve/reconcile them before deploying.' >&2
  git status --short
  exit 1
}

docker info >/dev/null
git fetch origin "refs/heads/$branch:refs/remotes/origin/$branch"
git merge-base --is-ancestor "$revision" "origin/$branch"
old_revision=$(git rev-parse HEAD)
# Deploy only the current tip of this branch, not an old queued revision.
if [[ $(git rev-parse "origin/$branch") != "$revision" ]]; then
  echo "A newer revision exists on $branch; skipping stale job."
  exit 0
fi
# The checkout is clean; switch safely even when the two branches diverge.
git switch --detach "$revision"

compose=(docker compose --project-directory "$root/deploy" -f "$root/deploy/compose.yaml")
"${compose[@]}" config --quiet
"${compose[@]}" up -d --wait --wait-timeout 120

# Bind-mounted files do not change the Compose service definition.
if ! git diff --quiet "$old_revision" "$revision" -- deploy/prometheus; then
  "${compose[@]}" restart prometheus
fi
if ! git diff --quiet "$old_revision" "$revision" -- deploy/grafana; then
  "${compose[@]}" restart grafana
fi
"${compose[@]}" up -d --wait --wait-timeout 120
curl --fail --silent --show-error --retry 10 --retry-connrefused --retry-delay 2 --max-time 10 \
  --output /dev/null http://127.0.0.1:5050/login
"${compose[@]}" ps
echo "Deployed $branch at $revision"
