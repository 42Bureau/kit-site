#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="/home/denisakimov/docker/kit_site"
repo_dir="$root_dir/repo"
compose_file="$repo_dir/deploy/compose.prod.yaml"
project_name="kit"
container_name="kit-site"
image_name="ghcr.io/42bureau/kit-site"
health_url="http://127.0.0.1:8101/"
state_file="$root_dir/.last-deployed-image"
failed_marker="$root_dir/.deploy-failed"

compose() {
  docker compose --project-name "$project_name" --file "$compose_file" "$@"
}

mark_failed() {
  printf '%s\n' "$target_image" > "$state_file.tmp"
  mv "$state_file.tmp" "$state_file"
  printf 'image=%s failed_at=%s\n' "$target_image" "$(date -Is)" > "$failed_marker"
}

loud_fail() {
  reason="$1"
  printf '\n============================================================\n' >&2
  printf 'DEPLOY FAILED (%s) image=%s\n' "$reason" "$target_image" >&2
  compose logs --tail=150 >&2 || true
  printf 'stopping %s so it does not serve broken code\n' "$container_name" >&2
  docker stop --time 10 "$container_name" >/dev/null 2>&1 || true
  printf 'state marked as deployed; cron will NOT retry until a new image or FORCE_DEPLOY=1\n' >&2
  printf 'manual rollback, if you want it: FORCE_DEPLOY=1 IMAGE_TAG=rollback docker compose --project-name %s --file %s up -d --force-recreate\n' "$project_name" "$compose_file" >&2
  printf '============================================================\n' >&2
}

start_if_stopped() {
  docker container inspect "$container_name" >/dev/null 2>&1 || return 0
  if [ "$(docker inspect --format '{{.State.Running}}' "$container_name")" = "true" ]; then
    return 0
  fi
  current_image="$(docker inspect --format '{{.Image}}' "$container_name")"
  if [ -f "$failed_marker" ] && grep -qF "image=$current_image" "$failed_marker" 2>/dev/null; then
    return 0
  fi
  printf '%s %s is stopped and no failed deploy is recorded, starting it\n' "$(date -Is)" "$container_name" >&2
  docker start "$container_name" >/dev/null 2>&1 || true
}

exec 9>"$root_dir/.deploy.lock"
if ! flock -n 9; then
  printf '%s another deploy holds %s, skipping\n' "$(date -Is)" "$root_dir/.deploy.lock" >&2
  exit 75
fi

for attempt in $(seq 1 6); do
  if docker pull "$image_name:latest" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -lt 6 ]; then
    sleep 10
  else
    printf '%s PULL FAILED image=%s:latest (registry unreachable?): %s is left as it is, cron will retry\n' "$(date -Is)" "$image_name" "$container_name" >&2
    start_if_stopped
    exit 1
  fi
done

target_image="$(docker image inspect --format '{{.Id}}' "$image_name:latest")"

running_image=""
if docker container inspect "$container_name" >/dev/null 2>&1; then
  running_image="$(docker inspect --format '{{.Image}}' "$container_name")"
fi

if [ "${FORCE_DEPLOY:-0}" != "1" ] && [ -n "$running_image" ] && [ "$running_image" = "$target_image" ]; then
  if [ -f "$failed_marker" ] && grep -qF "image=$target_image" "$failed_marker" 2>/dev/null; then
    printf '%s DEPLOY FAILED EARLIER (%s). Service may be stopped. Push a fix or run FORCE_DEPLOY=1.\n' "$(date -Is)" "$target_image" >&2
    exit 3
  fi
  if [ "$(docker inspect --format '{{.State.Running}}' "$container_name")" != "true" ]; then
    printf '%s %s has the current image but is stopped and no failed deploy is recorded, starting it\n' "$(date -Is)" "$container_name"
    docker start "$container_name" >/dev/null
    for attempt in $(seq 1 90); do
      if curl -fsS --max-time 3 "$health_url" >/dev/null 2>&1; then
        printf '%s started, healthy image=%s\n' "$(date -Is)" "$target_image"
        exit 0
      fi
      sleep 2
    done
    printf '%s started %s but the health check did not pass, will look again on the next tick\n' "$(date -Is)" "$container_name" >&2
    exit 1
  fi
  printf '%s up to date, %s already runs %s\n' "$(date -Is)" "$container_name" "$target_image"
  exit 0
fi

if [ -n "$running_image" ]; then
  docker tag "$running_image" "$image_name:rollback" >/dev/null 2>&1 || true
fi

if ! compose up -d --force-recreate; then
  mark_failed
  loud_fail "compose up"
  exit 1
fi

for attempt in $(seq 1 60); do
  if curl -fsS --max-time 3 "$health_url" >/dev/null 2>&1; then
    printf '%s\n' "$target_image" > "$state_file.tmp"
    mv "$state_file.tmp" "$state_file"
    rm -f "$failed_marker"
    printf '%s healthy image=%s\n' "$(date -Is)" "$target_image"
    exit 0
  fi
  sleep 2
done

mark_failed
loud_fail "health check"
exit 1