#!/usr/bin/env bash
# Verify that a plugin is loaded, registered and effective on a running CPA.
#
# Usage: verify-plugin.sh <plugin-id> [management-key] [base-url]
#
# Checks, in order:
#   1. the binary advertises dynamic-plugin support (httpX-CPA-SUPPORT-PLUGIN)
#   2. GET /v8/management/plugins returns the plugin
#   3. the four status fields, which mean different things:
#        plugins_enabled    global switch
#        enabled            per-plugin config switch
#        registered         library loaded and registration completed
#        effective_enabled  all three satisfied
#   4. the loaded path, so you can confirm it is the artifact you just built
set -euo pipefail

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

[ $# -ge 1 ] || usage
PLUGIN_ID="$1"
KEY="${2:-${MANAGEMENT_KEY:-}}"
BASE="${3:-${CPA_BASE_URL:-http://127.0.0.1:8317}}"

command -v curl >/dev/null || { echo "error: curl not found" >&2; exit 1; }

echo "== CPA at $BASE, plugin '$PLUGIN_ID' =="
echo

# --- 1. build capability -----------------------------------------------------
echo "[1/4] binary plugin support"
HDRS=$(curl -sS -m 15 -D - -o /dev/null "$BASE/v8/management/plugins" \
  ${KEY:+-H "Authorization: Bearer $KEY"} 2>&1 || true)
SUPPORT=$(printf '%s' "$HDRS" | grep -i 'CPA-SUPPORT-PLUGIN' | tr -d '\r' | awk '{print $2}')
case "$SUPPORT" in
  1) echo "      ok: binary supports dynamic plugins" ;;
  0) echo "      FAIL: binary was built without CGO; no plugin can load" >&2; exit 1 ;;
  *) echo "      warn: support header absent (older build or unreachable host)" ;;
esac
echo

# --- 2. plugin listing -------------------------------------------------------
echo "[2/4] GET /v8/management/plugins"
BODY=$(curl -sS -m 20 "$BASE/v8/management/plugins" \
  ${KEY:+-H "Authorization: Bearer $KEY"} 2>&1) || {
    echo "      FAIL: request failed. Check the management key and that the" >&2
    echo "      instance is running. A 404 usually means management.secret-key" >&2
    echo "      is empty and no fallback password is set." >&2
    exit 1
  }
if printf '%s' "$BODY" | grep -q 'missing management key\|invalid management key'; then
  echo "      FAIL: management key rejected. Pass it as the second argument" >&2
  echo "      or set MANAGEMENT_KEY." >&2
  exit 1
fi
echo "      ok: $(printf '%s' "$BODY" | wc -c) bytes received"
echo

# --- 3. status fields --------------------------------------------------------
echo "[3/4] status fields for '$PLUGIN_ID'"
if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PY=$(command -v python3 || command -v python)
  printf '%s' "$BODY" | "$PY" - "$PLUGIN_ID" <<'PYEOF'
import json, sys
pid = sys.argv[1]
try:
    doc = json.load(sys.stdin)
except Exception as exc:
    print("      FAIL: response is not JSON: %s" % exc)
    sys.exit(1)

def pick(doc, *names):
    for n in names:
        if isinstance(doc, dict) and n in doc:
            return doc[n]
    return None

print("      plugins_enabled   = %s" % pick(doc, "plugins_enabled", "pluginsEnabled"))
print("      plugins_dir       = %s" % pick(doc, "plugins_dir", "pluginsDir"))

items = pick(doc, "plugins", "items") or []
if isinstance(items, dict):
    items = [dict(v, id=k) if isinstance(v, dict) else {"id": k} for k, v in items.items()]

match = None
for it in items:
    if not isinstance(it, dict):
        continue
    if pick(it, "id", "ID", "plugin_id") == pid:
        match = it
        break

if match is None:
    print("      FAIL: plugin '%s' not found in the listing." % pid)
    print("      known ids: %s" % ", ".join(
        str(pick(i, "id", "ID", "plugin_id")) for i in items if isinstance(i, dict)) or "(none)")
    print("      the library file name must equal the plugin id, and it must sit")
    print("      under plugins.dir (or plugins.dir/<GOOS>/<GOARCH>).")
    sys.exit(1)

for f in ("enabled", "registered", "effective_enabled"):
    print("      %-18s= %s" % (f, pick(match, f, f.replace("_", ""))))
print("      path              = %s" % pick(match, "path", "Path"))

eff = pick(match, "effective_enabled", "effectiveEnabled")
reg = pick(match, "registered")
if eff is True and reg is True:
    print("      ok: loaded, registered and effective")
    sys.exit(0)
print("      FAIL: not effective yet")
if reg is not True:
    print("             registered=false -> the library was not loaded.")
    print("             check file name, extension for this platform, and plugins.dir")
if eff is not True:
    print("             effective_enabled=false -> a switch is off. Both the global")
    print("             plugins.enabled and the per-plugin enabled must be true.")
sys.exit(1)
PYEOF
  RC=$?
else
  echo "      warn: no python found; falling back to grep (less precise)"
  printf '%s' "$BODY" | grep -o "\"$PLUGIN_ID\"[^}]*}" || true
  RC=0
fi
echo

# --- 4. resources ------------------------------------------------------------
echo "[4/4] registered resource pages (unauthenticated by design)"
if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PY=$(command -v python3 || command -v python)
  printf '%s' "$BODY" | "$PY" - "$PLUGIN_ID" "$BASE" <<'PYEOF'
import json, sys
pid, base = sys.argv[1], sys.argv[2]
doc = json.load(sys.stdin)
items = doc.get("plugins") or doc.get("items") or []
if isinstance(items, dict):
    items = [dict(v, id=k) for k, v in items.items()]
for it in items:
    if isinstance(it, dict) and (it.get("id") or it.get("ID")) == pid:
        menus = it.get("menus") or it.get("menu") or it.get("resources") or []
        if not menus:
            print("      (none registered)")
        for m in menus:
            p = m.get("path") if isinstance(m, dict) else m
            print("      %s/v0/resource/plugins/%s%s" % (base, pid, p))
        break
PYEOF
fi

echo
echo "note: replacing the library on disk does NOT affect a running instance."
echo "      Windows locks loaded DLLs and the host loads from a shadow copy."
echo "      Reinstall via the management API or restart the service."
