#!/usr/bin/env bash
# Run every headless test suite and fail on a non-zero exit, a timeout, or any
# script error in the output. A failed GDScript assertion can leave a suite
# waiting forever, so each one runs under a timeout.
#
#   tools/run_tests.sh                 # uses $GODOT, then `godot` on PATH, then the macOS app
#   GODOT=/path/to/godot tools/run_tests.sh
#   LOG_DIR=build/test-logs tools/run_tests.sh
set -u

cd "$(dirname "$0")/.."
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT="godot"
	elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
		GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
	else
		echo "Godot not found. Set GODOT=/path/to/godot." >&2
		exit 2
	fi
fi
LOG_DIR="${LOG_DIR:-$(mktemp -d)}"
SUITE_TIMEOUT="${SUITE_TIMEOUT:-300}"
mkdir -p "$LOG_DIR"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD="timeout $SUITE_TIMEOUT"
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_CMD="gtimeout $SUITE_TIMEOUT"
fi

echo "Importing project..."
"$GODOT" --headless --path . --import >"$LOG_DIR/import.log" 2>&1

failed=0
for suite in tests/test_*.gd; do
	name="$(basename "$suite" .gd)"
	log="$LOG_DIR/$name.log"
	$TIMEOUT_CMD "$GODOT" --headless --path . --script "res://$suite" >"$log" 2>&1
	code=$?
	if [ $code -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR:|Parse Error|Assertion failed" "$log"; then
		echo "FAIL  $name (exit $code)"
		grep -E -A3 "SCRIPT ERROR|^ERROR:|Parse Error|Assertion failed" "$log" | head -20 | sed 's/^/      /'
		failed=$((failed + 1))
	else
		echo "ok    $name"
	fi
done

echo "Logs: $LOG_DIR"
if [ $failed -ne 0 ]; then
	echo "$failed suite(s) failed" >&2
	exit 1
fi
echo "All suites passed"
