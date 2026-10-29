#!/bin/sh
set -eu

# Strictly default to UTC Timezone internally (REQ-TZ-001)
export TZ=UTC

# Rails needs secret_key_base in production (Active Record builds its message verifiers when it loads), and the
# image ships no credentials master key. SECRET_KEY_BASE is taken from the environment; without one, this container
# generates its own (the API keeps no signed or encrypted state across restarts). Passenger passes the environment
# of nginx to the application.
if [ -z "${SECRET_KEY_BASE:-}" ]; then
    SECRET_KEY_BASE=$(/usr/local/bin/ruby -rsecurerandom -e 'print SecureRandom.hex(64)')
    export SECRET_KEY_BASE
fi

# The runtime directories ship with the image (owned by the unprivileged account); they are recreated
# when /var/logs or /tmp is a fresh volume.
mkdir -p /var/logs/nginx /var/logs/passenger /tmp/nginx /tmp/passenger

# Rotates the logs every day at midnight UTC (REQ-LOG-002). The container runs unprivileged, and BusyBox
# crond can only run jobs as root, so the schedule is a loop that sleeps until the next midnight.
rotate_logs_at_midnight() {
    while true; do
        now=$(date +%s)
        sleep $((86400 - now % 86400))
        logrotate --state /var/logs/logrotate.status /etc/logrotate.conf ||
            echo "logrotate failed with status $?" >&2
    done
}
rotate_logs_at_midnight >> /var/logs/logrotate.log 2>&1 &

# Start Nginx in the foreground (daemon off is in nginx.conf)
exec /opt/nginx/sbin/nginx -c /opt/nginx/conf/nginx.conf
