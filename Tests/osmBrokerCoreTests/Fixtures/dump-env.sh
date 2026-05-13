#!/bin/sh
# Test fixture: dumps env vars as KEY=VALUE lines.
# Used to verify SPAWN-5 — child env is explicit, no broker secrets leaked.
env
exit 0
