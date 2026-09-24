#!/usr/bin/env bash
# Runs the tests with coverage and enforces a line-coverage floor on the SwiftLocalStorage library.
# Produces:
#   .build/coverage/coverage.lcov   - lcov file (Codecov / editors)
#   .build/coverage/report.txt      - per-file llvm-cov report
#   .build/coverage/summary.md      - Markdown summary (CI job summary)
#   .build/coverage/total.txt       - line-coverage percentage, e.g. "96.06"
# Usage: bash scripts/coverage.sh            (floor defaults to 90)
#        COVERAGE_FLOOR=95 bash scripts/coverage.sh
set -euo pipefail

FLOOR="${COVERAGE_FLOOR:-90}"
OUT=".build/coverage"
mkdir -p "$OUT"

swift test --enable-code-coverage

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$(find "$BIN_PATH/codecov" -name 'default.profdata' | head -1)"
XCTEST="$(find "$BIN_PATH" -name '*.xctest' | head -1)"
BIN="$XCTEST/Contents/MacOS/$(basename "$XCTEST" .xctest)"

# Only measure the shipping library, not tests or dependencies.
IGNORE='(Tests|\.build|checkouts)'

xcrun llvm-cov export -format=lcov -instr-profile "$PROFDATA" "$BIN" \
  -ignore-filename-regex="$IGNORE" > "$OUT/coverage.lcov"
xcrun llvm-cov report -instr-profile "$PROFDATA" "$BIN" \
  -ignore-filename-regex="$IGNORE" > "$OUT/report.txt"

PCT="$(awk '/^TOTAL/ {print $(NF-3)}' "$OUT/report.txt" | tr -d '%')"
echo "$PCT" > "$OUT/total.txt"

{
  echo "## Code coverage"
  echo
  echo "**Line coverage: ${PCT}%** (library target only, floor ${FLOOR}%)"
  echo
  echo '```'
  cat "$OUT/report.txt"
  echo '```'
} > "$OUT/summary.md"

echo "Line coverage: ${PCT}% (floor ${FLOOR}%)"
if awk -v p="$PCT" -v f="$FLOOR" 'BEGIN { exit !(p < f) }'; then
  echo "error: line coverage ${PCT}% is below the ${FLOOR}% floor" >&2
  exit 1
fi
