#!/bin/sh
# Test fixture: sleeps for an hour. Used to verify SIGTERM → SIGKILL escalation
# in ProcessSpawner / ProcessRegistry.killAll().
exec sleep 3600
