#!/bin/sh
set -eu
umask 077

fail() { echo "TURN configuration error: $1" >&2; exit 1; }
[ ${#TURN_SHARED_SECRET} -ge 32 ] || fail 'TURN_SHARED_SECRET must contain at least 32 characters.'
case "$TURN_SHARED_SECRET" in *[!a-zA-Z0-9_-]*) fail 'Use a hex or URL-safe random shared secret.' ;; esac
case "${TURN_REALM:-nobarsync.local}" in *[!a-zA-Z0-9.-]*) fail 'Invalid TURN_REALM.' ;; esac
printf '%s\n' "${TURN_EXTERNAL_IP:-}" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1}' || fail 'Set TURN_EXTERNAL_IP to a reachable IPv4 address (not the ngrok hostname).'
for port in "${TURN_MIN_PORT:-49160}" "${TURN_MAX_PORT:-49200}"; do
  case "$port" in ''|*[!0-9]*) fail 'Relay ports must be integers.' ;; esac
  [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || fail 'Relay ports must be between 1024 and 65535.'
done
[ "${TURN_MIN_PORT:-49160}" -le "${TURN_MAX_PORT:-49200}" ] || fail 'Invalid relay port range.'

cat /etc/coturn/nobarsync.conf > /tmp/turnserver.conf
cat >> /tmp/turnserver.conf <<EOF
realm=${TURN_REALM:-nobarsync.local}
server-name=${TURN_REALM:-nobarsync.local}
static-auth-secret=$TURN_SHARED_SECRET
external-ip=$TURN_EXTERNAL_IP
min-port=${TURN_MIN_PORT:-49160}
max-port=${TURN_MAX_PORT:-49200}
EOF
if [ "${TURN_TLS_ENABLED:-false}" = true ]; then
  [ -r /certs/fullchain.pem ] && [ -r /certs/privkey.pem ] || fail 'TLS requires readable fullchain.pem and privkey.pem in infra/turn/certs.'
  printf '\ntls-listening-port=5349\ncert=/certs/fullchain.pem\npkey=/certs/privkey.pem\nno-dtls\n' >> /tmp/turnserver.conf
else
  printf '\nno-tls\nno-dtls\n' >> /tmp/turnserver.conf
fi
exec turnserver -c /tmp/turnserver.conf
