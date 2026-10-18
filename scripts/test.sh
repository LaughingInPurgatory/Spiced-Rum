#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="${SPICED_RUM_BUILD_DIR:-${TMPDIR:-/tmp}/spiced-rum-build}"
export CLANG_MODULE_CACHE_PATH="$build_dir/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/cache/swift"
swift test --disable-sandbox --build-system native --scratch-path "$build_dir" --cache-path "$build_dir/cache" "$@"
