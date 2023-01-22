# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# [START cloudrun_fuse_dockerfile]
# Use the official lightweight Python image.
# https://hub.docker.com/_/python
FROM python:3.9-slim-buster

# Install system dependencies
RUN set -e; \
    apt-get update -y && apt-get install -y \
    tini \
    curl \
    gnupg \
    vim \
    lsb-release; \
    gcsFuseRepo=gcsfuse-`lsb_release -c -s`; \
    echo "deb http://packages.cloud.google.com/apt $gcsFuseRepo main" | \
    tee /etc/apt/sources.list.d/gcsfuse.list; \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    apt-key add -; \
    apt-get update; \
    apt-get install -y gcsfuse \
    && apt-get clean

# Set fallback mount directory
ENV MNT_DIR /data

# Copy local code to the container image.
ENV APP_HOME /app
WORKDIR $APP_HOME
COPY requirements.txt ./requirements.txt
COPY gcsfuse_run.sh ./gcsfuse_run.sh

# Install production dependencies.
RUN pip install -r requirements.txt

# Ensure the script is executable
RUN chmod +x /app/gcsfuse_run.sh

# Source for this Dockerfile : https://github.com/r-bird/dind-python-3.9-slim-buster

############
## Docker ##
############
ARG DOCKER_CHANNEL=stable
ARG DOCKER_VERSION=20.10.8

RUN apt-get update && apt-get install -y --no-install-recommends \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg2 \
  software-properties-common
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   ${DOCKER_CHANNEL}"
RUN apt-get update && apt-get install -y --no-install-recommends docker-ce=5:${DOCKER_VERSION}~3-0~debian-buster && \
  docker -v && \
  dockerd -v

####################
## Docker Compose ##
####################
ARG DOCKER_COMPOSE_VERSION=1.29.2
RUN curl -L https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-Linux-x86_64 > /usr/local/bin/docker-compose && \
  chmod +x /usr/local/bin/docker-compose

#################
## DIND Script ##
#################
ARG DIND_COMMIT=deda3d4933d3c0bd57f2cef672da5d28fc653706
ENV DOCKER_EXTRA_OPTS '--storage-driver=overlay'
RUN curl -fL -o /usr/local/bin/dind "https://raw.githubusercontent.com/moby/moby/${DIND_COMMIT}/hack/dind" && \
	chmod +x /usr/local/bin/dind

VOLUME /var/lib/docker
EXPOSE 2375

COPY . ./
RUN chmod +x /app/dind_run.sh

ENTRYPOINT  ["./dind_run.sh"]

CMD ["/app/gcsfuse_run.sh"]