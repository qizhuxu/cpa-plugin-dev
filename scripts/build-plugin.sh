#!/usr/bin/env bash
# Build a CLIProxyAPI plugin for the current platform.
#
# Usage: build-plugin.sh <plugin-dir> [go|c|rust]
#
# Mirrors the per-language build rules in examples/plugin/Makefile:
#   go   -> go build -buildmode=c-shared
#   c    -> cmake configure + build a SHARED library
#   rust -> cargo build --release --locked (crate-type = ["cdylib"])
set -euo pipefail

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

[ $# -ge 1 ] || usage
PLUGIN_DIR="$(cd "$1" && pwd)"
LANG="${2:-}"

# Detect the language from the files present when not given.
if [ -z "$LANG" ]; then
  if [ -f "$PLUGIN_DIR/go.mod" ]; then LANG=go
  elif [ -f "$PLUGIN_DIR/Cargo.toml" ]; then LANG=rust
  elif [ -f "$PLUGIN_DIR/CMakeLists.txt" ]; then LANG=c
  else
    echo "error: cannot detect language in $PLUGIN_DIR; pass go, c or rust" >&2
    exit 1
  fi
fi

PLUGIN_ID="$(basename "$PLUGIN_DIR")"
BIN_DIR="$PLUGIN_DIR/bin"
mkdir -p "$BIN_DIR"

# Extension rules from internal/pluginhost/platform.go
# Decide the extension from uname first. Testing MSYSTEM or WINDIR alone can
# misfire: under WSL those can leak in through WSLENV and a Linux build would
# be named .dll.
case "$(uname -s)" in
  Darwin)                       EXT=dylib ;;
  Linux|FreeBSD|OpenBSD|NetBSD) EXT=so ;;
  *)
    if [ -n "${MSYSTEM:-}" ] || [ -n "${WINDIR:-}" ] || [ -n "${OS:-}" ]; then
      EXT=dll
    else
      EXT=so
    fi
    ;;
esac

echo "building '$PLUGIN_ID' ($LANG) -> $BIN_DIR/$PLUGIN_ID.$EXT"

case "$LANG" in
  go)
    ( cd "$PLUGIN_DIR" && go build -buildmode=c-shared -o "$BIN_DIR/$PLUGIN_ID.$EXT" . )
    # The generated header is not needed for distribution.
    [ -f "$BIN_DIR/$PLUGIN_ID.h" ] && mv "$BIN_DIR/$PLUGIN_ID.h" "$BIN_DIR/$PLUGIN_ID.h.unused"
    ;;
  c)
    BUILD_DIR="$PLUGIN_DIR/build"
    cmake -S "$PLUGIN_DIR" -B "$BUILD_DIR" \
      -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$BIN_DIR" >/dev/null
    cmake --build "$BUILD_DIR"
    ;;
  rust)
    ( cd "$PLUGIN_DIR" && CARGO_TARGET_DIR="$PLUGIN_DIR/build/rust" cargo build --release --locked )
    # cdylib output is lib<name>.so / .dylib, or <name>.dll on Windows.
    SRC=$(find "$PLUGIN_DIR/build/rust/release" -maxdepth 1 -type f \
      \( -name "*.so" -o -name "*.dylib" -o -name "*.dll" \) | head -n 1)
    [ -n "$SRC" ] || { echo "error: no cdylib artifact found" >&2; exit 1; }
    cp "$SRC" "$BIN_DIR/$PLUGIN_ID.$EXT"
    ;;
  *) echo "error: unsupported language '$LANG'" >&2; exit 1 ;;
esac

ARTIFACT="$BIN_DIR/$PLUGIN_ID.$EXT"
[ -f "$ARTIFACT" ] || { echo "error: build produced no $ARTIFACT" >&2; exit 1; }

echo
echo "artifact: $ARTIFACT"
echo "place it at <cpa>/plugins/$PLUGIN_ID.$EXT"
echo "  or at <cpa>/plugins/<GOOS>/<GOARCH>/$PLUGIN_ID.$EXT for a platform-specific slot"
