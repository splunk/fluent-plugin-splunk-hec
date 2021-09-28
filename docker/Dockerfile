FROM registry.access.redhat.com/ubi8/ruby-27

ARG VERSION

LABEL name="Splunk Connect for Kubernetes Logging container" \
      maintainer="DataEdge@splunk.com" \
      vendor="Splunk Inc." \
      version=${VERSION} \
      release=${VERSION} \
      summary="Splunk Connect for Kubernetes Logging container" \
      description="Splunk Connect for Kubernetes Logging container"

ENV VERSION=${VERSION}
ENV FLUENT_USER fluent

USER root

COPY *.gem /tmp/
COPY licenses /licenses

RUN dnf install -y jq

COPY Gemfile* ./
RUN yum update -y \
   && yum remove -y nodejs npm \
   && gem install bundler \
   && gem unpack /tmp/*.gem --target gem \
   && bundle install \
   && rpm -e --nodeps python3-urllib3-* python3-requests-* python3-libxml2-* python3-dmidecode-* subscription-manager-* libwebp-* libwebp-devel-* file-libs-* glib2-* libjpeg-turbo-devel-* libjpeg-turbo-* mariadb-connector-c-config-* mariadb-connector-c-* mariadb-connector-c-devel-* rsync-* sqlite-libs-* sqlite-devel-* sqlite-* libxml2-* libxml2-devel-* oniguruma-* libX11-* libX11-common-* libX11-devel-* libX11-xcb-* lz4-libs-* nettle-* libsolv-* libgcrypt-* jq-* git-* bsdtar-* openssh-clients-* libtiff-devel-* libtiff-* json-c-* binutils-* dbus-daemon-* tar-* qt5-srpm-macros-* perl-parent-* 

RUN groupadd -r $FLUENT_USER && \
   useradd -r -g $FLUENT_USER $FLUENT_USER && \
   mkdir -p /fluentd/log /fluentd/etc /fluentd/plugins &&\
   chown -R $FLUENT_USER /fluentd && chgrp -R $FLUENT_USER /fluentd

USER $FLUENT_USER
CMD bundle exec fluentd -c /fluentd/etc/fluent.conf