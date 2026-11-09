#!/bin/bash
# RC is experimental: never start alongside a stable SBC5 controller.
# Startup/runtime safety guard; not a host-wide hardware mutex.
set -u

check_stable_stopped() {
  [ -n "$SUPERVISOR_TOKEN" ] || return 1
  local addons slug info state
  addons="$(curl -fsS --max-time 8 -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons 2>/dev/null)" || return 1
  printf '%s' "$addons" | jq -e '.data.addons | type == "array"' >/dev/null 2>&1 || return 1
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    info="$(curl -fsS --max-time 8 -H "Authorization: Bearer $SUPERVISOR_TOKEN" "http://supervisor/addons/$slug/info" 2>/dev/null)" || return 1
    state="$(printf '%s' "$info" | jq -r '.data.state // empty' 2>/dev/null)"
    case "$state" in
      stopped) ;;
      *) echo "SBC5 RC BLOCKED: Stable App $slug state=$state" >&2; return 1 ;;
    esac
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
