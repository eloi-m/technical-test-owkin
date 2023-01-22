#!/bin/bash
set -e

# have to use legacy iptables otherwise the script fails
update-alternatives --set iptables /usr/sbin/iptables-legacy

# Source for this script : https://github.com/r-bird/dind-python-3.9-slim-buster

echo "==> Launching the Docker daemon..."
CMD=$*
if [ "$CMD" == '' ];then
  dind dockerd $DOCKER_EXTRA_OPTS
  check_docker
else
  dind dockerd $DOCKER_EXTRA_OPTS &
  while(! docker info > /dev/null 2>&1); do
      echo "==> Waiting for the Docker daemon to come online..."
      sleep 1
  done
  echo "==> Docker Daemon is up and running!"
  echo "==> Running CMD $CMD!"
  exec "$CMD"
fi
