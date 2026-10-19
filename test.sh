#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SH="$ROOT/backup.sh"

SANDBOX="$ROOT/virtual_log"

if [ ! -d "$SANDBOX" ]; then
    echo "Error: Disk $SANDBOX not found. Please mount it first."
    exit 1
fi

rm -rf "$SANDBOX"/* 2>/dev/null
trap 'chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"/*' EXIT

PASS=0
FAIL=0

check() {
    local msg=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  (Passed) $msg"
        PASS=$((PASS + 1))
    else
        echo "  (Failed) $msg"
        FAIL=$((FAIL + 1))
    fi
}

make_logs() {
    local dir="$1" count="$2" size_mb="$3"
    mkdir -p "$dir"
    for i in $(seq -w 1 "$count"); do
        dd if=/dev/zero of="$dir/app $i.log" bs=1M count="$size_mb" status=none 2>/dev/null
        touch -d "$i days ago" "$dir/app $i.log"
    done
}

run_backup() {
    local log_dir="$1" bak_dir="$2" n="$3" m="$4"
    OUT=$(BACKUP_DIR="$bak_dir" "$BACKUP_SH" "$log_dir" "$n" "$m" 2>&1)
    RC=$?
    echo "$OUT" | grep "Used:" || true
}

test_below_threshold() {
    local d="$SANDBOX/t1"
    make_logs "$d/log" 1 20
    
    run_backup "$d/log" "$d/bak" 90 3
    
    check "return code 0" test "$RC" -eq 0
    check "archive NOT created" test -z "$(ls -A "$d/bak" 2>/dev/null)"
    check "all 1 file intact" test "$(ls -1 "$d/log" | wc -l)" -eq 1
}

test_above_threshold() {
    local d="$SANDBOX/t2"
    make_logs "$d/log" 6 20
    mkdir -p "$d/bak"
    
    run_backup "$d/log" "$d/bak" 5 3
    
    local arch=$(ls "$d/bak"/backup_*.tar.gz 2>/dev/null | head -n 1)
    check "return code 0" test "$RC" -eq 0
    check "archive created" test -n "$arch"
    check "exactly 3 files in archive" test "$(tar -tzf "$arch" | wc -l)" -eq 3
    check "3 files left in folder" test "$(ls -1 "$d/log" | wc -l)" -eq 3
}

test_oldest_first() {
    local d="$SANDBOX/t3"
    make_logs "$d/log" 6 20
    mkdir -p "$d/bak"
    
    touch -d "2026-10-01 10:00:00" "$d/log/app 05.log"
    touch -d "2026-10-02 10:00:00" "$d/log/app 02.log"
    touch -d "2026-10-03 10:00:00" "$d/log/app 06.log"
    touch -d "2026-10-15 10:00:00" "$d/log/app 01.log"
    
    run_backup "$d/log" "$d/bak" 5 3
    local arch=$(ls "$d/bak"/backup_*.tar.gz 2>/dev/null | head -n 1)
    
    check "archive created" test -n "$arch"
    check "app 05 in archive" bash -c "tar -tzf '$arch' | grep -q 'app 05.log'"
    check "app 02 in archive" bash -c "tar -tzf '$arch' | grep -q 'app 02.log'"
    check "app 06 in archive" bash -c "tar -tzf '$arch' | grep -q 'app 06.log'"
    check "app 05 removed" test ! -e "$d/log/app 05.log"
    check "app 01 NOT deleted" test -f "$d/log/app 01.log"
}

test_archive_failure() {
    local d="$SANDBOX/t4"
    make_logs "$d/log" 6 20
    mkdir -p "$d/bak"
    chmod 555 "$d/bak"
    
    run_backup "$d/log" "$d/bak" 5 3
    chmod 755 "$d/bak"
    
    check "error code != 0" test "$RC" -ne 0
    check "all 6 files intact" test "$(ls -1 "$d/log" | wc -l)" -eq 6
}

test_custom_args() {
    local d="$SANDBOX/t5"
    make_logs "$d/log" 6 20
    mkdir -p "$d/bak"
    
    run_backup "$d/log" "$d/bak" 5 2
    local arch=$(ls "$d/bak"/backup_*.tar.gz 2>/dev/null | head -n 1)
    
    check "return code 0" test "$RC" -eq 0
    check "archive created" test -n "$arch"
    check "exactly 2 files in archive" test "$(tar -tzf "$arch" | wc -l)" -eq 2
    check "4 files left in folder" test "$(ls -1 "$d/log" | wc -l)" -eq 4
}

test_edge_cases() {
    local d="$SANDBOX/t6"
    mkdir -p "$d/log/sub" "$d/bak"
    
    run_backup "" "$d/bak" 80 3
    check "no path: exit 1" test "$RC" -eq 1
    
    run_backup "$d/nope" "$d/bak" 80 3
    check "missing dir: exit 1" test "$RC" -eq 1
    
    run_backup "$d/log" "$d/bak" 5 3
    check "only a subfolder: exit 0" test "$RC" -eq 0
    check "subfolder not archived" test -z "$(ls -A "$d/bak")"
}

run_test() { 
    echo; 
    echo " $1"; 
    "$1"; 
    rm -rf "$SANDBOX"/* 
}

echo "Testing on real 1GB disk: $SANDBOX"
run_test test_below_threshold
run_test test_above_threshold
run_test test_oldest_first
run_test test_archive_failure
run_test test_custom_args
run_test test_edge_cases

echo
echo "Total: passed $PASS, failed $FAIL"
exit $((FAIL > 0))
