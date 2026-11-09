#!/bin/bash
# SBC5 RC safety: allow a single active fan controller.
# Both the Supervisor app state and the Docker-running probe must agree.
set -u

check_stable_stopped() {
  [[ -v SUPERVISOR_TOKEN ]] || return 1
  [ -n "$SUPERVISOR_TOKEN" ] || return 1

  local addons slug info state probe code body
  addons="$(curl -fsS --max-time 8 -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons 2>/dev/null)" || return 1
  printf '%s' "$addons" | jq -e '.result == "ok" and (.data.addons | type == "array")' >/dev/null 2>&1 || return 1

  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    info="$(curl -fsS --max-time 8 -H "Authorization: Bearer $SUPERVISOR_TOKEN" "http://supervisor/addons/$slug/info" 2>/dev/null)" || return 1
    state="$(printf '%s' "$info" | jq -r '.data.state // empty' 2>/dev/null)"
    case "$state" in
      stopped|error) ;;
      *) echo "SBC5 RC BLOCKED: Stable App $slug state=$state" >&2; return 1 ;;
    esac

    # Error can remain after manual stop with exit code 143.
    # Never accept a cached Supervisor app state alone as proof of stopped.
    # /stats checks Docker.is_running; accept only its explicit not-running
    # error_key. Any success, 401/403, timeout, malformed JSON blocks RC.
    probe="$(curl -sS --max-time 8 -w '\n%{http_code}' -H "Authorization: Bearer $SUPERVISOR_TOKEN" "http://supervisor/addons/$slug/stats?one_shot" 2>/dev/null)" || return 1
    code="$(printf '%s\n' "$probe" | tail -n 1)"
    body="$(printf '%s\n' "$probe" | sed '$d')"
    if [ "$code" != "400" ] || ! printf '%s' "$body" | jq -e '.result == "error" and .error_key == "app_not_running_error"' >/dev/null 2>&1; then
      echo "SBC5 RC BLOCKED: Stable App $slug state=$state; stopped container not confirmed (stats HTTP $code)." >&2
      return 1
    fi
  done < <(printf '%s' "$addons" | jq -r '.data.addons[] | .slug // empty | select(endswith("_sbc5_control_center"))')
  return 0
}

acknowledged="$(jq -r '.rc_exclusive_ack // false' /data/options.json 2>/dev/null || true)"
if [ "$acknowledged" != "true" ]; then
  echo "SBC5 RC BLOCKED: enable rc_exclusive_ack only after stopping Stable SBC5 and making a backup." >&2
  exit 1
fi
if ! check_stable_stopped; then
  echo "SBC5 RC BLOCKED: unable to verify Stable SBC5 is stopped." >&2
  exit 1
fi

rc_main_pid="$$"
watch_stable() {
  while sleep 5; do
    if ! check_stable_stopped; then
      echo "SBC5 RC WATCHDOG: Stable started or Supervisor state unknown; stopping RC." >&2
      kill -TERM "$rc_main_pid" 2>/dev/null || true
      exit 1
    fi
  done
}
watch_stable &
exec /run.sh "$@"
