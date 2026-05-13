#!/bin/sh
# Test fixture for FakeEchoAdapter.
# Reads the entire prompt from stdin, then echoes each word on its own line
# with a tiny delay so we exercise streaming.
input=$(cat)
for word in $input; do
  printf '%s\n' "$word"
done
exit 0
