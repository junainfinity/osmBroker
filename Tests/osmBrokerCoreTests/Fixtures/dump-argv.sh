#!/bin/sh
# Test fixture: prints each argv on its own line, prefixed with "argv: ".
# Used to verify SPAWN-1 — the prompt must never appear in argv.
i=0
for arg in "$@"; do
  printf 'argv: %s\n' "$arg"
  i=$((i+1))
done
printf 'argc: %d\n' "$i"
exit 0
