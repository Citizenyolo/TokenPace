#!/usr/bin/env bash
set -u

echo "=== Running Validation Tests ==="
exit_1=0

HARNESS_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/harness_test_XXXXXXXX")
cleanup_harness() {
    rm -rf -- "$HARNESS_ROOT"
}
trap cleanup_harness 0 2 15 1

echo "1. Validating syntax (bash -n)..."
if bash -n install.sh; then echo "PASS: bash -n"; else echo "FAIL: bash -n"; exit_1=1; fi

echo "2. Fail-closed fixture extraction..."
awk '
BEGIN { output=1; found=0 }
/^xcodebuild -project/ { found++; output=0; exit }
{ if(output) print }
END { if(found != 1) exit 1 }
' install.sh > "$HARNESS_ROOT/staging_base.sh"

if [ $? -ne 0 ]; then
    echo "FAIL: Could not extract exactly one boundary"
    exit 1
fi

sed -e 's/if ! command -v xcodegen/if false/g' "$HARNESS_ROOT/staging_base.sh" > "$HARNESS_ROOT/tmp1.sh"
sed -e 's/if ! command -v xcodebuild/if false/g' "$HARNESS_ROOT/tmp1.sh" > "$HARNESS_ROOT/tmp2.sh"
sed -e 's/xcodegen generate/#xcodegen generate/g' "$HARNESS_ROOT/tmp2.sh" > "$HARNESS_ROOT/staging_safe.sh"

if grep -E -q "^(xcodebuild|codesign|launchctl|killall|lsregister|cp)" "$HARNESS_ROOT/staging_safe.sh"; then
    echo "FAIL: Fixture contains real operations"
    exit 1
fi
echo "PASS: Fixture extracted safely"

echo "3. Validating unique/private allocation and success cleanup..."
cat << 'TEST2' > "$HARNESS_ROOT/test2.sh"
#!/usr/bin/env bash
source "$1/staging_safe.sh"
echo "BUILD_DIR=$BUILD_DIR"
exit 0
TEST2
chmod +x "$HARNESS_ROOT/test2.sh"

export TMPDIR="$HARNESS_ROOT/tmp"
mkdir -p "$TMPDIR"
touch "$TMPDIR/sentinel"

OUTPUT1=$("$HARNESS_ROOT/test2.sh" "$HARNESS_ROOT")
EXIT1=$?
BUILD_DIR1=$(echo "$OUTPUT1" | grep "^BUILD_DIR=" | cut -d'=' -f2)

OUTPUT2=$("$HARNESS_ROOT/test2.sh" "$HARNESS_ROOT")
BUILD_DIR2=$(echo "$OUTPUT2" | grep "^BUILD_DIR=" | cut -d'=' -f2)

if [ "$EXIT1" -eq 0 ]; then echo "PASS: Success status is 0"; else echo "FAIL: Status $EXIT1"; exit_1=1; fi
if [ -n "$BUILD_DIR1" ] && [ -n "$BUILD_DIR2" ] && [ "$BUILD_DIR1" != "$BUILD_DIR2" ]; then echo "PASS: Unique allocations"; else echo "FAIL: Non-unique allocation"; exit_1=1; fi
if [ -n "$BUILD_DIR1" ] && [ ! -d "$BUILD_DIR1" ]; then echo "PASS: Cleanup successful"; else echo "FAIL: Cleanup failed"; exit_1=1; fi
if [ -f "$TMPDIR/sentinel" ]; then echo "PASS: Sentinel preserved"; else echo "FAIL: Sentinel lost"; exit_1=1; fi

echo "4. Validating permissions (700)..."
cat << 'PERMTEST' > "$HARNESS_ROOT/test_perm.sh"
#!/usr/bin/env bash
source "$1/staging_safe.sh"
if stat --version 2>/dev/null | grep -q GNU; then
    stat -c "%a" "$BUILD_DIR" > "$1/perm.txt"
else
    stat -f "%Lp" "$BUILD_DIR" > "$1/perm.txt"
fi
exit 0
PERMTEST
chmod +x "$HARNESS_ROOT/test_perm.sh"
"$HARNESS_ROOT/test_perm.sh" "$HARNESS_ROOT"
PERMS=$(cat "$HARNESS_ROOT/perm.txt")
if [ "$PERMS" = "700" ]; then echo "PASS: Private permissions (700)"; else echo "FAIL: Permissions $PERMS"; exit_1=1; fi

echo "5. Validating TMPDIR with spaces..."
export TMPDIR="$HARNESS_ROOT/tmp with spaces"
mkdir -p "$TMPDIR"
OUTPUT_SPACES=$("$HARNESS_ROOT/test2.sh" "$HARNESS_ROOT")
BUILD_DIR_SPACES=$(echo "$OUTPUT_SPACES" | grep "^BUILD_DIR=" | cut -d'=' -f2)
if [ -n "$BUILD_DIR_SPACES" ] && [[ "$BUILD_DIR_SPACES" == "$TMPDIR/"* ]]; then echo "PASS: Handles spaces"; else echo "FAIL: Spaces failed"; exit_1=1; fi
if [ -n "$BUILD_DIR_SPACES" ] && [ ! -d "$BUILD_DIR_SPACES" ]; then echo "PASS: Cleanup with spaces"; else echo "FAIL: Cleanup failed"; exit_1=1; fi

echo "6. Validating unset / empty TMPDIR fallback..."
for test_tmpdir in "unset" "empty"; do
    if [ "$test_tmpdir" = "unset" ]; then unset TMPDIR; else export TMPDIR=""; fi
    OUTPUT_FALLBACK=$("$HARNESS_ROOT/test2.sh" "$HARNESS_ROOT")
    BUILD_DIR_FALLBACK=$(echo "$OUTPUT_FALLBACK" | grep "^BUILD_DIR=" | cut -d'=' -f2)
    if [ -n "$BUILD_DIR_FALLBACK" ] && [[ "$BUILD_DIR_FALLBACK" == "/tmp/"* ]]; then echo "PASS: Fallback to /tmp ($test_tmpdir)"; else echo "FAIL: Fallback failed ($test_tmpdir)"; exit_1=1; fi
    if [ -n "$BUILD_DIR_FALLBACK" ] && [ ! -d "$BUILD_DIR_FALLBACK" ]; then echo "PASS: Cleanup fallback ($test_tmpdir)"; else echo "FAIL: Cleanup failed"; exit_1=1; fi
done

export TMPDIR="$HARNESS_ROOT/tmp"
echo "7. Validating mktemp failure (doesn't delete unrelated path)..."
cat << 'FAILTEST' > "$HARNESS_ROOT/test_mktemp.sh"
#!/usr/bin/env bash
mktemp() { return 1; }
export -f mktemp
source "$1/staging_safe.sh"
echo "BUILD_DIR=$BUILD_DIR"
exit 0
FAILTEST
chmod +x "$HARNESS_ROOT/test_mktemp.sh"
OUTPUT_MFAIL=$("$HARNESS_ROOT/test_mktemp.sh" "$HARNESS_ROOT")
BUILD_DIR_MFAIL=$(echo "$OUTPUT_MFAIL" | grep "^BUILD_DIR=" | cut -d'=' -f2)
if [ -z "$BUILD_DIR_MFAIL" ]; then echo "PASS: mktemp failure empty path"; else echo "FAIL: path not empty ($BUILD_DIR_MFAIL)"; exit_1=1; fi
if [ -f "$TMPDIR/sentinel" ]; then echo "PASS: Sentinel preserved on mktemp failure"; else echo "FAIL: Sentinel lost on mktemp failure"; exit_1=1; fi

echo "8. Validating non-zero failure cleanup and status preservation..."
cat << 'TESTFAIL' > "$HARNESS_ROOT/test_fail.sh"
#!/usr/bin/env bash
source "$1/staging_safe.sh"
echo "BUILD_DIR=$BUILD_DIR"
exit 42
TESTFAIL
chmod +x "$HARNESS_ROOT/test_fail.sh"
OUTPUT_FAIL=$("$HARNESS_ROOT/test_fail.sh" "$HARNESS_ROOT")
EXIT_FAIL=$?
BUILD_DIR_FAIL=$(echo "$OUTPUT_FAIL" | grep "^BUILD_DIR=" | cut -d'=' -f2)

if [ "$EXIT_FAIL" -eq 42 ]; then echo "PASS: Failure status preserved (42)"; else echo "FAIL: Status not preserved ($EXIT_FAIL)"; exit_1=1; fi
if [ -n "$BUILD_DIR_FAIL" ] && [ ! -d "$BUILD_DIR_FAIL" ]; then echo "PASS: Cleanup successful on failure"; else echo "FAIL: Cleanup failed"; exit_1=1; fi

echo "9. Validating catchable interruption (SIGTERM)..."
cat << 'TESTTERM' > "$HARNESS_ROOT/test_term.sh"
#!/usr/bin/env bash
source "$1/staging_safe.sh"
echo "BUILD_DIR=$BUILD_DIR"
kill -TERM $$
sleep 10
exit 0
TESTTERM
chmod +x "$HARNESS_ROOT/test_term.sh"

OUTPUT_TERM=$("$HARNESS_ROOT/test_term.sh" "$HARNESS_ROOT")
EXIT_TERM=$?
BUILD_DIR_TERM=$(echo "$OUTPUT_TERM" | grep "^BUILD_DIR=" | cut -d'=' -f2)

if [ "$EXIT_TERM" -eq 143 ]; then echo "PASS: Status preserved on SIGTERM (143)"; else echo "FAIL: expected 143, got $EXIT_TERM"; exit_1=1; fi
if [ -n "$BUILD_DIR_TERM" ] && [ ! -d "$BUILD_DIR_TERM" ]; then echo "PASS: Cleanup successful on SIGTERM"; else echo "FAIL: Cleanup failed"; exit_1=1; fi

echo "10. Validating rm failure preserves original exit status..."
cat << 'TESTRM' > "$HARNESS_ROOT/test_rm.sh"
#!/usr/bin/env bash
rm() { return 1; }
export -f rm
source "$1/staging_safe.sh"
echo "BUILD_DIR=$BUILD_DIR"
exit 42
TESTRM
chmod +x "$HARNESS_ROOT/test_rm.sh"
OUTPUT_RM=$("$HARNESS_ROOT/test_rm.sh" "$HARNESS_ROOT")
EXIT_RM=$?
if [ "$EXIT_RM" -eq 42 ]; then echo "PASS: Status preserved on rm failure (42)"; else echo "FAIL: Status not preserved ($EXIT_RM)"; exit_1=1; fi

echo "=== All Tests Completed ==="
if [ "$exit_1" = "1" ]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
