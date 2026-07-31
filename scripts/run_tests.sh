#!/bin/sh
# Run fzf-lua tests. Arguments are nvim executables (space-separated), e.g.
# `./scripts/run_tests.sh nvim` or `./scripts/run_tests.sh "nvim nv"`.
# `JOBS=N` splits spec files across N parallel worker processes; default 1.
# `glob`, `filter`, `update_screenshots` pass through to the workers untouched.

set -u

JOBS="${JOBS:-1}"
case "$JOBS" in
  ''|*[!0-9]*) JOBS=1 ;;
esac

tmpdir=$(mktemp -d)
pids=""
overall=0

cleanup() {
  for p in $pids; do kill "$p" 2>/dev/null; done
  rm -rf "$tmpdir"
}
trap 'cleanup; exit 1' INT TERM

# Run one worker: $1 nvim exec, $2 newline-separated spec list (empty -> all),
# $3 optional log file (streams to stdout when omitted).
run_worker() {
  local_exec="$1"
  local_files="$2"
  local_log="${3:-}"
  base="$local_exec --headless --noplugin -u ./scripts/minimal_init.lua -l ./scripts/make_cli.lua"
  if [ -n "$local_log" ]; then
    if [ -n "$local_files" ]; then
      FZF_LUA_TEST_FILES="$local_files" $base >"$local_log" 2>&1
    else
      $base >"$local_log" 2>&1
    fi
  else
    if [ -n "$local_files" ]; then
      FZF_LUA_TEST_FILES="$local_files" $base
    else
      $base
    fi
  fi
}

for exec in "$@"; do
  printf '\n======\n\n'
  "$exec" --version | head -n 1
  echo ''
  pids=""

  if [ "$JOBS" -le 1 ] || [ -n "${glob:-}" ] || [ -n "${filter:-}" ]; then
    run_worker "$exec" ""
    [ $? -ne 0 ] && overall=1
    continue
  fi

  # Round-robin spec files across JOBS workers for load balance
  n=0
  for f in $(find tests -name '*_spec.lua' | sort); do
    printf '%s\n' "$f" >>"$tmpdir/bucket$(( n % JOBS ))"
    n=$(( n + 1 ))
  done
  if [ "$n" -eq 0 ]; then
    run_worker "$exec" ""
    [ $? -ne 0 ] && overall=1
    continue
  fi

  w=0
  while [ "$w" -lt "$JOBS" ]; do
    if [ -f "$tmpdir/bucket$w" ]; then
      run_worker "$exec" "$(cat "$tmpdir/bucket$w")" "$tmpdir/log$w" &
      pids="$pids $!"
    fi
    w=$(( w + 1 ))
  done

  for p in $pids; do
    if ! wait "$p"; then overall=1; fi
  done
  pids=""

  # Print worker logs in order for stable output
  w=0
  while [ "$w" -lt "$JOBS" ]; do
    if [ -f "$tmpdir/log$w" ]; then
      printf '%s\n' "--- worker $(( w + 1 )) ($(wc -l <"$tmpdir/bucket$w") files) ---"
      cat "$tmpdir/log$w"
    fi
    w=$(( w + 1 ))
  done
done

rm -rf "$tmpdir"
exit "$overall"
