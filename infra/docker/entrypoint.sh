#!/bin/sh
set -eu
if [ "${NOBARSYNC_ROLE:-api}" != "worker" ]; then
  /app/bin/nobarsync eval "NobarSync.Release.migrate()"
fi
exec /app/bin/nobarsync start
