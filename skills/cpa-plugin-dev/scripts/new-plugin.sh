#!/usr/bin/env bash
# Scaffold a new CLIProxyAPI plugin from the bundled skeletons.
#
# Usage: new-plugin.sh <plugin-id> [go|c|rust] [output-dir]
#
# The plugin id becomes the dynamic library file name, the config key and a
# path segment under /v0/resource/plugins/<id>/, so it must satisfy the host
# rule from internal/pluginhost/platform.go:
#   [A-Za-z0-9][A-Za-z0-9._-]{0,127}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS="$SKILL_ROOT/assets"

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

[ $# -ge 1 ] || usage
PLUGIN_ID="$1"
LANG="${2:-go}"
OUT_DIR="${3:-.}"

case "$LANG" in
  go|c|rust) ;;
  *) echo "error: language must be go, c or rust (got '$LANG')" >&2; exit 1 ;;
esac

if ! printf '%s' "$PLUGIN_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'; then
  echo "error: plugin id '$PLUGIN_ID' violates [A-Za-z0-9][A-Za-z0-9._-]{0,127}" >&2
  echo "       the id becomes the library file name and the config key" >&2
  exit 1
fi

TARGET="$OUT_DIR/$PLUGIN_ID"
if [ -e "$TARGET" ]; then
  echo "error: $TARGET already exists; refusing to overwrite" >&2
  exit 1
fi

AUTHOR="${PLUGIN_AUTHOR:-$(git config user.name 2>/dev/null || echo author)}"
REPO="${PLUGIN_REPOSITORY:-https://github.com/owner/$PLUGIN_ID}"
PROVIDER="${PLUGIN_PROVIDER:-$PLUGIN_ID}"

mkdir -p "$TARGET"
cp -R "$ASSETS/skeleton-$LANG/." "$TARGET/"

# Replace placeholders in every text file. C and Rust skeletons carry the
# official example ids rather than placeholders, so they get a second pass.
replace_all() {
  local from="$1" to="$2"
  # -i differs between GNU and BSD sed; write to a temp file instead.
  find "$TARGET" -type f \( -name '*.go' -o -name '*.c' -o -name '*.rs' \
    -o -name '*.tmpl' -o -name '*.yaml' -o -name '*.toml' -o -name 'Makefile' \
    -o -name '*.txt' \) -print0 | while IFS= read -r -d '' f; do
      sed "s|$from|$to|g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
}

replace_all '__PLUGIN_ID__'   "$PLUGIN_ID"
replace_all '__AUTHOR__'      "$AUTHOR"
replace_all '__REPOSITORY__'  "$REPO"
replace_all '__PROVIDER_KEY__' "$PROVIDER"
replace_all 'example-simple-c'    "$PLUGIN_ID"
replace_all 'example-simple-rust' "$PLUGIN_ID"

# The Go module file is a template so the scaffold does not depend on the
# module being resolvable at copy time.
if [ -f "$TARGET/go.mod.tmpl" ]; then
  mv "$TARGET/go.mod.tmpl" "$TARGET/go.mod"
fi

echo "scaffolded $LANG plugin '$PLUGIN_ID' at $TARGET"
echo
echo "next steps:"
echo "  1. trim the declared capabilities to what you will implement"
echo "     (references/capabilities.md lists the valid keys)"
echo "  2. build:  scripts/build-plugin.sh $TARGET $LANG"
echo "  3. place:  copy the artifact into <cpa>/plugins/"
echo "  4. verify: scripts/verify-plugin.sh $PLUGIN_ID"
