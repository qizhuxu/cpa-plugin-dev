#!/usr/bin/env bash
# Verify that a plugin is loaded, registered and effective on a running CPA.
#
# Usage: verify-plugin.sh <plugin-id> [management-key] [base-url]
#
# Checks, in order:
#   1. the binary advertises dynamic-plugin support (X-CPA-SUPPORT-PLUGIN)
#   2. GET /v8/management/plugins returns the plugin
#   3. the status fields, which mean different things:
#        plugins_enabled    global switch
#        configured         the plugin has a config entry
#        enabled            per-plugin config switch
#        registered         library loaded and registration completed
#        effective_enabled  all of the above satisfied
#   4. the loaded path, so you can confirm it is the artifact you just built
set -euo pipefail

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

[ $# -ge 1 ] || usage
PLUGIN_ID="$1"
KEY="${2:-${MANAGEMENT_KEY:-}}"
BASE="${3:-${CPA_BASE_URL:-http://127.0.0.1:8317}}"

command -v curl >/dev/null || { echo "error: curl not found" >&2; exit 1; }

# Build curl arguments as an array. `${KEY:+-H "..."}` does NOT work: the
# quotes inside the expansion are not honoured and the header is split apart.
CURL_ARGS=(-sS -m 20)
[ -n "$KEY" ] && CURL_ARGS+=(-H "Authorization: Bearer $KEY")

echo "== CPA at $BASE, plugin '$PLUGIN_ID' =="
echo

# --- 1. build capability -----------------------------------------------------
echo "[1/4] binary plugin support"
HDRS=$(curl "${CURL_ARGS[@]}" -D - -o /dev/null "$BASE/v8/management/plugins" 2>&1 || true)
SUPPORT=$(printf '%s' "$HDRS" | tr -d '\r' \
  | grep -i '^X-CPA-SUPPORT-PLUGIN:' | awk '{print $2}' | head -n 1)
case "${SUPPORT:-}" in
  1) echo "      ok: binary supports dynamic plugins" ;;
  0) echo "      FAIL: binary was built without CGO; no plugin can load" >&2; exit 1 ;;
  *) echo "      warn: support header absent; host unreachable or an older build" ;;
esac
echo

# --- 2. plugin listing -------------------------------------------------------
echo "[2/4] GET /v8/management/plugins"
BODY_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/cpa-verify.$$.json")"
trap 'rm -f "$BODY_FILE"' EXIT
if ! curl "${CURL_ARGS[@]}" -o "$BODY_FILE" "$BASE/v8/management/plugins"; then
  echo "      FAIL: request failed. Check the management key and that the" >&2
  echo "      instance is running. A 404 usually means management.secret-key" >&2
  echo "      is empty and no fallback password is set." >&2
  exit 1
fi
if grep -q 'missing management key\|invalid management key' "$BODY_FILE" 2>/dev/null; then
  echo "      FAIL: management key rejected. Pass it as the second argument" >&2
  echo "      or set MANAGEMENT_KEY." >&2
  exit 1
fi
echo "      ok: $(wc -c < "$BODY_FILE" | tr -d ' ') bytes received"
echo

# --- 3. status fields --------------------------------------------------------
# Pick an interpreter that actually runs. On Windows, `command -v python3`
# often resolves to the Microsoft Store alias stub, which is not a real
# interpreter and exits non-zero.
PY=""
for _cand in python python3 py; do
  if command -v "$_cand" >/dev/null 2>&1 && "$_cand" -c "import json" >/dev/null 2>&1; then
    PY="$(command -v "$_cand")"
    break
  fi
done
if [ -z "$PY" ]; then
  echo "[3/4] status fields"
  echo "      warn: no python found; raw entry below"
  grep -o "\"id\": \"$PLUGIN_ID\".\{0,400\}" "$BODY_FILE" || true
  exit 0
fi

echo "[3/4] status fields for '$PLUGIN_ID'"
# The JSON is passed as a file path, never on stdin: a heredoc would replace
# the pipe and python would read the script instead of the payload.
"$PY" - "$BODY_FILE" "$PLUGIN_ID" <<'__PYEOF__'
import json, sys

path, pid = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception as exc:
    print("      FAIL: response is not JSON: %s" % exc)
    sys.exit(1)

print("      plugins_enabled = %s" % doc.get("plugins_enabled"))
print("      plugins_dir     = %s" % doc.get("plugins_dir"))

items = doc.get("plugins") or doc.get("items") or []
match = next((i for i in items if isinstance(i, dict) and i.get("id") == pid), None)

if match is None:
    print("      FAIL: plugin '%s' not found in the listing." % pid)
    known = ", ".join(str(i.get("id")) for i in items if isinstance(i, dict))
    print("      known ids: %s" % (known or "(none)"))
    print("      the library file name must equal the plugin id, and it must sit")
    print("      under plugins.dir (or plugins.dir/<GOOS>/<GOARCH>).")
    sys.exit(1)

for field in ("configured", "enabled", "registered", "effective_enabled"):
    print("      %-18s= %s" % (field, match.get(field)))
print("      path              = %s" % match.get("path"))

menus = match.get("menus") or []
if menus:
    print("      menus             = %s" % json.dumps(menus, ensure_ascii=False))

if match.get("registered") is True and match.get("effective_enabled") is True:
    print("      ok: loaded, registered and effective")
    sys.exit(0)

print("      FAIL: not effective yet")
if match.get("configured") is not True:
    print("             configured=false -> no plugins.configs entry for this id")
if match.get("registered") is not True:
    print("             registered=false -> the library was not loaded.")
    print("             check the file name, the extension for this platform,")
    print("             the file architecture, and plugins.dir")
if match.get("effective_enabled") is not True:
    print("             effective_enabled=false -> a switch is off. Both the")
    print("             global plugins.enabled and the per-plugin enabled must be true.")
sys.exit(1)
__PYEOF__
echo

# --- 4. resource pages -------------------------------------------------------
echo "[4/4] registered resource pages (unauthenticated by design)"
"$PY" - "$BODY_FILE" "$PLUGIN_ID" "$BASE" <<'__PYEOF2__'
import json, sys
path, pid, base = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as fh:
    doc = json.load(fh)
items = doc.get("plugins") or doc.get("items") or []
match = next((i for i in items if isinstance(i, dict) and i.get("id") == pid), None)
menus = (match or {}).get("menus") or []
if not menus:
    print("      (none registered)")
for m in menus:
    p = m.get("path") if isinstance(m, dict) else m
    if not isinstance(p, str) or not p:
        continue
    # The listing returns an already-absolute path. Registration takes a
    # relative one and the host expands it; do not prefix twice.
    if p.startswith("/v0/") or p.startswith("http"):
        url = base + p if p.startswith("/") else p
    else:
        url = base + "/v0/resource/plugins/" + pid + p
    print("      " + url)
__PYEOF2__

echo
echo "note: replacing the library on disk does NOT affect a running instance."
echo "      Windows locks loaded DLLs and the host loads from a shadow copy."
echo "      Reinstall via the management API or restart the service."
