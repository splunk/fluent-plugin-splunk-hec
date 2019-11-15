FROM fluent/fluentd:v1.7.0-debian-1.0
LABEL maintainer="Splunk Inc. <DataEdge@splunk.com>"
# Use root account to use apt
USER root

COPY *.gem /tmp/

RUN buildDeps="sudo make gcc g++ libc-dev" \
 && apt-get update \
 && apt-get install -y --no-install-recommends $buildDeps \
 && apt-get install -y jq \
 && gem install -N fluent-plugin-systemd -v "1.0.2" \
 && gem install -N fluent-plugin-concat -v "2.2.2" \
 && gem install -N fluent-plugin-prometheus -v "1.3.0" \
 && gem install -N fluent-plugin-jq -v "0.5.1" \
 && gem install -N fluent-plugin-kubernetes_metadata_filter -v "2.1.2" \
 && gem install -N oj -v "3.5.1" \
 && gem install -N /tmp/*.gem \
 && gem sources --clear-all \
 && SUDO_FORCE_REMOVE=yes \
    apt-get purge -y --auto-remove \
                  -o APT::AutoRemove::RecommendsImportant=false \
                  $buildDeps \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem
