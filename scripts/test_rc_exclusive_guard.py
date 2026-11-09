#!/usr/bin/env python3
"""Test the RC exclusive-start guard with mocked Supervisor replies.

No device or running App is touched. Mocked /stats replies model stopped,
running, and unverified states; an unknown result must always block startup.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "scripts/rc_exclusive_guard.sh"
code = GUARD.read_text()
begin = code.index("check_stable_stopped() {")
end = code.index('\nacknowledged=', begin)
fn = code[begin:end]
assert "app_not_running_error" in fn
assert 'while sleep 5; do' in code
assert 'if ! check_stable_stopped; then' in code

mock = r'''
curl() {
    case "$*" in
        *"/addons/"*"/info"*)
            printf '{"result":"ok","data":{"state":"%s"}}' "$MOCK_STATE" ;;
        *"/addons/"*"/stats"*)
            if [ "$MOCK_STATS_HTTP" = "fail" ]; then return 7; fi
            if [ "$MOCK_STATS_HTTP" = "400" ]; then
                printf '{"result":"error","error_key":"%s"}\n400' "$MOCK_ERROR_KEY"
            else
                printf '{"result":"ok","data":{"cpu_percent":12}}\n%s' "$MOCK_STATS_HTTP"
            fi ;;
        *"/addons"*)
            printf '{"result":"ok","data":{"addons":[{"slug":"98b55775_sbc5_control_center"}]}}' ;;
        *) return 2 ;;
    esac
}
'''

def allowed(state: str, http: str, key: str = "app_not_running_error", token="x") -> bool:
    program = mock + "\n" + fn + "\ncheck_stable_stopped\n"
    import os
    env = {**os.environ, "SUPERVISOR_TOKEN": token,
           "MOCK_STATE": state, "MOCK_STATS_HTTP": http, "MOCK_ERROR_KEY": key}
    result = subprocess.run(["bash", "-c", program], env=env,
                            text=True, capture_output=True, timeout=8)
    assert result.returncode in (0, 1), (result.returncode, result.stderr)
    return result.returncode == 0

assert allowed("error", "400")  # crashed/errored but Docker definitely not running
assert allowed("stopped", "400")
for state, status, key in [
    ("error", "200", "app_not_running_error"),
    ("error", "401", "app_not_running_error"),
    ("error", "fail", "app_not_running_error"),
    ("error", "400", "app_not_found_error"),
    ("started", "400", "app_not_running_error"),
    ("startup", "400", "app_not_running_error"),
    ("unknown", "400", "app_not_running_error"),
    ("stopped", "200", "app_not_running_error"),
]:
    assert not allowed(state, status, key), (state, status, key)
assert not allowed("error", "400", token="")
print("SBC5 RC Supervisor/Docker exclusivity guard: PASS")
