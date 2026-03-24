#!/bin/sh
set -e

# Strictly default to UTC Timezone internally (REQ-TZ-001)
export TZ=UTC

# Ensure required run-time directories exist
mkdir -p /var/logs/nginx
mkdir -p /var/logs/passenger
mkdir -p /tmp/nginx
mkdir -p /etc/crontabs
mkdir -p /tmp/passenger
chmod 1777 /tmp

# Ensure correct logrotate crontab is set
# Cron will execute /usr/sbin/logrotate -f /etc/logrotate.conf at midnight
echo "0 0 * * * /usr/sbin/logrotate /etc/logrotate.conf" > /etc/crontabs/root

# Start cron daemon in background (-b) and log to /var/logs/crond.log
crond -b -L /var/logs/crond.log

# Start Nginx in the foreground (daemon off is in nginx.conf)
exec /opt/nginx/sbin/nginx -c /opt/nginx/conf/nginx.conf
