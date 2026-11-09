#!/bin/bash
# RC is experimental: never start alongside a stable SBC5 controller.
# Startup/runtime safety guard; not a host-wide hardware mutex.
set -u

check_stable_stopped() {
  [ -n "$SUPERVISOR_TOKEN" ] || return 1
  local addons slug info state probe code body
  addons="$(curl -fsS --max-time 8 -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons 2>/dev/null)" || return 1
  printf '%s' "$addons" | jq -e '.data.addons | type == "array"' >/dev/null 2>&1 || return 1
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    info="$(curl -fsS --max-time 8 -H "Authorization: Bearer $SUPERVISOR_TOKEN" "http://supervisor/addons/$slug/info" 2>/dev/null)" || return 1
    state="$(printf '%s' "$info" | jq -r '.data.state // empty' 2>/dev/null)"
    case "$state" in
      stopped|error) ;;
      *) echo "SBC5 RC BLOCKED: Stable App $slug state=$state" >&2; return 1 ;;
    esac

    # Supervisor may report state=error after a manual stop (SIGTERM 143).
    # Do NOT trust that cached state as evidence that the container is stopped.
    # /stats checks App.is_running() against Docker, and returns HTTP 400 with
    # error_key=app_not_running_error ONLY when the app is not running.
    # Fail closed on 200, malformed output, permission errors, timeouts, etc.
    probe="$(curl -sS --max-time 8 -w '\n%{http_code}' -H "Authorization: Bearer $SUPERVISOR_TOKEN" "http://supervisor/addons/$slug/stats?one_shot" 2>/dev/null)" || return 1
    code="${probe##*
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
\n'}"
    body="${probe%
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
  while sleep 15; do
    if ! check_stable_stopped; then
      echo "SBC5 RC WATCHDOG: Stable started or Supervisor state unknown; stopping RC." >&2
      kill -TERM "$rc_main_pid" 2>/dev/null || true
      exit 1
    fi
  done
}
watch_stable &
exec /run.sh "$@"
\n'*}"
    if [ "$code" != "400" ] || ! printf '%s' "$body" | jq -e '.result == "error" and .error_key == "app_not_running_error"' >/dev/null 2>&1; then
      echo "SBC5 RC BLOCKED: Stable App $slug state=$state; Docker stopped state NOT confirmed (stats HTTP $code)." >&2
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
  while sleep 15; do
    if ! check_stable_stopped; then
      echo "SBC5 RC WATCHDOG: Stable started or Supervisor state unknown; stopping RC." >&2
      kill -TERM "$rc_main_pid" 2>/dev/null || true
      exit 1
    fi
  done
}
watch_stable &
exec /run.sh "$@"
