FROM ruby:3.1.4-buster as builder

ADD ./ /app/
WORKDIR /app
RUN gem install bundler
RUN bundle update --bundler
RUN bundle install

RUN bundle exec rake build -t -v

FROM registry.access.redhat.com/ubi9/ruby-31

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

COPY --from=builder /app/pkg/fluent-plugin-*.gem /tmp/

RUN mkdir /licenses
COPY --from=builder /app/LICENSE /licenses/LICENSE

RUN dnf install -y jq

COPY --from=builder /app/docker/Gemfile* ./
RUN yum update -y \
   && yum remove -y nodejs npm \
   && gem install bundler \
   && gem uninstall -i /usr/share/gems bundler \
   && gem unpack /tmp/*.gem --target gem \
   && bundle install \
   && yum groupremove -y "Development Tools" \
   && rpm -e --nodeps python3-urllib3-* python3-requests-* python3-libxml2-* python3-dmidecode-* subscription-manager-* libwebp-* libwebp-devel-*  libjpeg-turbo-devel-* libjpeg-turbo-* mariadb-connector-c-config-* mariadb-connector-c-* mariadb-connector-c-devel-* rsync-* libX11-* libX11-common-* libX11-devel-* libX11-xcb-* dbus-daemon-* tar-* qt5-srpm-macros-* perl-parent-*  git-* bsdtar-* openssh-clients-* binutils-* libtiff-devel-* libtiff-* python3-pip-wheel || true

RUN groupadd -r $FLUENT_USER && \
   useradd -r -g $FLUENT_USER $FLUENT_USER && \
   mkdir -p /fluentd/log /fluentd/etc /fluentd/plugins &&\
   chown -R $FLUENT_USER /fluentd && chgrp -R $FLUENT_USER /fluentd && \
   chmod +t /tmp

USER $FLUENT_USER
CMD bundle exec fluentd -c /fluentd/etc/fluent.conf