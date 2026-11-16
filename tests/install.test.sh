#!/usr/bin/env bash
# install.sh in a throwaway HOME: link vs copy, refresh, the --ensure safety net,
# and the two refusals. Touches nothing outside its temp dir and needs no shell.
#   tests/install.test.sh
set -uo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
id=nixfred.menubar-overload
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok    $1"; }
no() { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { if "${@:2}"; then ok "$1"; else no "$1"; fi; }

# A checkout on local disk (the temp dir), and a PATH with jq but no omarchy
# commands, so select_bar takes its "no shell running" branch.
src="$work/checkout"; mkdir -p "$src"
cp -a "$repo/install.sh" "$repo/$id" "$src/"
bin="$work/bin"; mkdir -p "$bin"
for t in bash env jq stat readlink diff cp mv rm mkdir ln dirname mktemp cat; do
  p=$(command -v "$t") && ln -s "$p" "$bin/$t"
done
run() { local home=$1; shift; env -i HOME="$home" PATH="$bin" bash "$src/install.sh" "$@"; }
fresh() { local h="$work/home.$1"; mkdir -p "$h/.config/omarchy"; echo '{"bar":{"id":"pi.bar"}}' >"$h/.config/omarchy/shell.json"; echo "$h"; }
plug() { echo "$1/.config/omarchy/plugins/$id"; }

h=$(fresh link); run "$h" >/dev/null 2>&1
check "local checkout is linked" test -L "$(plug "$h")"
run "$h" >/dev/null 2>&1; check "second run keeps the link" test -L "$(plug "$h")"

h=$(fresh copy); mkdir -p "$(dirname "$(plug "$h")")"; cp -a "$src/$id" "$(plug "$h")"
run "$h" --ensure >/dev/null 2>&1; rc=$?
check "--ensure accepts an installed copy" test "$rc" -eq 0
check "--ensure selects the bar" test "$(jq -r .bar.id "$h/.config/omarchy/shell.json")" = "$id"
check "--ensure leaves the copy a directory" test -d "$(plug "$h")" -a ! -L "$(plug "$h")"

echo "stale" >"$(plug "$h")/manifest.json"
run "$h" --ensure >/dev/null 2>&1
check "--ensure does not refresh a stale copy" test "$(cat "$(plug "$h")/manifest.json")" = stale
run "$h" >/dev/null 2>&1
check "a plain run refreshes a stale copy" diff -rq "$src/$id" "$(plug "$h")"
check "refresh leaves no temp dirs" test "$(ls "$(dirname "$(plug "$h")")" | wc -l)" -eq 1

h=$(fresh file); mkdir -p "$(dirname "$(plug "$h")")"; echo x >"$(plug "$h")"
run "$h" >/dev/null 2>&1; rc=$?
check "a stray file is refused" test "$rc" -ne 0

h=$(fresh elsewhere); mkdir -p "$(dirname "$(plug "$h")")" "$work/other"; ln -s "$work/other" "$(plug "$h")"
run "$h" >/dev/null 2>&1; rc=$?
check "a link to somewhere else is refused" test "$rc" -ne 0

# The copy-instead-of-link branch, by pretending the checkout is on NFS.
h=$(fresh nfs); rm "$bin/stat"
printf '#!%s\n[ "$1" = -f ] && { echo nfs; exit 0; }\nexec %s "$@"\n' "$(command -v bash)" "$(command -v stat)" >"$bin/stat"; chmod +x "$bin/stat"
run "$h" >/dev/null 2>&1
check "a checkout on a network filesystem is copied" test -d "$(plug "$h")" -a ! -L "$(plug "$h")"
check "the copy matches the checkout" diff -rq "$src/$id" "$(plug "$h")"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
