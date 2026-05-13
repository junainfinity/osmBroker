#!/bin/sh
# Test fixture: reads stdin, echoes each line back to stdout prefixed with
# "echo: ". Exits cleanly on EOF.
# Used by SpawnerTests to verify stdin → stdout round-tripping.
while IFS= read -r line; do
  printf 'echo: %s\n' "$line"
done
exit 0
