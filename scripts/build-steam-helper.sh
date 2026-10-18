#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
compiler="${MINGW_CC:-x86_64-w64-mingw32-gcc}"
if ! command -v "$compiler" >/dev/null 2>&1; then
  echo "Install mingw-w64 (for example, brew install mingw-w64) to build the Windows Steam helper." >&2
  exit 1
fi
source="Sources/SpicedRum/Resources/ThirdParty/steamwebhelper-wrapper.c"
output="Sources/SpicedRum/Resources/ThirdParty/steamwebhelper-wrapper.exe"
temporary="${TMPDIR:-/tmp}/steamwebhelper-wrapper-$$.exe"
trap 'rm -f "$temporary"' EXIT
"$compiler" -municode -O2 -Wall -Wextra -static -mwindows "$source" -lshell32 -o "$temporary"
file "$temporary" | grep -q 'PE32+ executable.*x86-64'
mv "$temporary" "$output"
echo "Built $output"
