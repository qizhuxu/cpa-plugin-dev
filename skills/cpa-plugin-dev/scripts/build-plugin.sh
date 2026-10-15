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
    # A freshly scaffolded plugin has no go.sum, and go build refuses without
    # one. That is exactly the new-plugin.sh -> build-plugin.sh path, so tidy
    # first when go.sum is absent.
    ( cd "$PLUGIN_DIR"
      if [ ! -f go.sum ]; then
        echo "  no go.sum yet; resolving modules with go mod tidy"
        go mod tidy
      fi
      go build -buildmode=c-shared -o "$BIN_DIR/$PLUGIN_ID.$EXT" .
    )
    # The generated header is not needed for distribution.
    [ -f "$BIN_DIR/$PLUGIN_ID.h" ] && mv "$BIN_DIR/$PLUGIN_ID.h" "$BIN_DIR/$PLUGIN_ID.h.unused"
    ;;
  c)
    if command -v cmake >/dev/null 2>&1; then
      BUILD_DIR="$PLUGIN_DIR/build"
      cmake -S "$PLUGIN_DIR" -B "$BUILD_DIR" \
        -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$BIN_DIR" >/dev/null
      cmake --build "$BUILD_DIR"
    else
      # No cmake. The skeleton is a single translation unit, so compile it
      # directly rather than failing. CC overrides the compiler; on Windows
      # that matters, because some MinGW builds link DLLs the loader rejects
      # (see pitfalls.md item 13).
      SRC="$(find "$PLUGIN_DIR/src" -name '*.c' 2>/dev/null | head -n 1)"
      [ -n "$SRC" ] || { echo "error: no .c file under $PLUGIN_DIR/src" >&2; exit 1; }
      CC_BIN="${CC:-}"
      if [ -z "$CC_BIN" ]; then
        for _c in cc gcc clang; do
          if command -v "$_c" >/dev/null 2>&1; then CC_BIN="$_c"; break; fi
        done
      fi
      [ -n "$CC_BIN" ] || {
        echo "error: neither cmake nor a C compiler is available" >&2
        echo "       install cmake, or set CC to a working compiler" >&2
        exit 1
      }
      case "$(uname -s)" in
        Darwin) SHARED_FLAG="-dynamiclib" ;;
        *)      SHARED_FLAG="-shared" ;;
      esac
      echo "  no cmake; compiling directly with $CC_BIN"
      "$CC_BIN" "$SHARED_FLAG" -fPIC -O2 -o "$BIN_DIR/$PLUGIN_ID.$EXT" "$SRC"
    fi
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
