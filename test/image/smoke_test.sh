#!/usr/bin/env bash
# Starts the production image and checks it end to end: the HEALTHCHECK turns healthy, /health answers,
# nothing runs as root, and a log rotation makes nginx reopen its logs.
# Usage: test/image/smoke_test.sh IMAGE
set -euo pipefail

image=${1:?usage: test/image/smoke_test.sh IMAGE}
name="smoke-test-$$"

fail() {
  printf '::error::%s\n' "$1"
  echo '--- HEALTHCHECK results'
  docker inspect --format '{{json .State.Health}}' "${name}" 2>&1
  echo '--- GET /health from inside the container'
  docker exec "${name}" /bin/busybox wget -O - http://127.0.0.1/health 2>&1 | tail -n 20
  echo '--- GET /health from the host'
  curl --silent --show-error --include --max-time 10 "${base}/health" 2>&1 | tail -n 20
  echo '--- processes'
  docker top "${name}" -o pid,uid,args 2>&1
  echo '--- container output'
  docker logs "${name}" 2>&1 | tail -n 50
  echo '--- /var/logs/nginx/error.log'
  docker exec "${name}" cat /var/logs/nginx/error.log 2>&1 | tail -n 50
  echo '--- /var/logs/passenger/passenger.log'
  docker exec "${name}" cat /var/logs/passenger/passenger.log 2>&1 | tail -n 50
  exit 1
}

cleanup() {
  docker rm --force "${name}" > /dev/null 2>&1 || echo "container ${name} was already removed"
}
trap cleanup EXIT

docker run --detach --name "${name}" --publish 127.0.0.1::80 "${image}" > /dev/null
mapping=$(docker port "${name}" 80/tcp)
port=${mapping##*:}
base="http://127.0.0.1:${port}"

echo "Waiting for the HEALTHCHECK of ${image} to report healthy..."
status=starting
for _ in $(seq 1 60); do
  running=$(docker inspect --format '{{.State.Running}}' "${name}")
  [[ "${running}" == true ]] || fail 'the container exited'
  status=$(docker inspect --format '{{.State.Health.Status}}' "${name}")
  [[ "${status}" == healthy ]] && break
  sleep 3
done
[[ "${status}" == healthy ]] || fail "the HEALTHCHECK never reported healthy (last status: ${status})"
echo 'healthy'

body=$(curl --fail --silent --show-error "${base}/health")
[[ "${body}" == '{"status":"OK"}' ]] || fail "unexpected /health body: ${body}"
echo "/health answers ${body}"

headers=$(curl --fail --silent --show-error --head "${base}/health")
server=$(printf '%s\n' "${headers}" | tr -d '\r' | sed -n 's/^[Ss]erver: //p')
[[ "${server}" == nginx ]] || fail "the Server header discloses more than the product name: ${server}"
echo "Server header: ${server}"

processes=$(docker top "${name}" -o pid,uid,args)
not_app=$(printf '%s\n' "${processes}" | awk 'NR > 1 && $2 != 10001')
[[ -z "${not_app}" ]] || fail "processes not running as uid 10001:
${not_app}"
echo 'every process runs as uid 10001'

# Regression: logrotate signalled /tmp/nginx.pid while nginx writes /tmp/nginx/nginx.pid, so nginx never
# reopened its logs and kept writing into the rotated (and compressed) file.
curl --fail --silent --show-error --output /dev/null "${base}/robots.txt?smoke=before-rotation"
docker exec "${name}" logrotate --force --state /var/logs/logrotate.status /etc/logrotate.conf
sleep 2
curl --fail --silent --show-error --output /dev/null "${base}/robots.txt?smoke=after-rotation"
sleep 1
access_log=$(docker exec "${name}" cat /var/logs/nginx/access.log)
[[ "${access_log}" == *after-rotation* ]] ||
  fail "nginx did not reopen access.log after the rotation; access.log holds: ${access_log}"
[[ "${access_log}" != *before-rotation* ]] || fail 'access.log was not rotated'
docker exec "${name}" ls /var/logs/nginx/access.log.1.gz > /dev/null || fail 'no rotated access.log.1.gz'
echo 'logrotate rotated access.log and nginx reopened it'

echo 'Smoke test passed'
