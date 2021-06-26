FROM registry.access.redhat.com/ubi8/ruby-27

ARG VERSION
ARG NODEJS_VERSION

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
  #  && npm install -g n \
   && yum remove -y nodejs npm \
  #  && n ${NODEJS_VERSION} \
   && gem install bundler \
   && gem unpack /tmp/*.gem --target gem \
   && bundle install 

 RUN groupadd -r $FLUENT_USER && \
   useradd -r -g $FLUENT_USER $FLUENT_USER && \
   mkdir -p /fluentd/log /fluentd/etc /fluentd/plugins &&\
   chown -R $FLUENT_USER /fluentd && chgrp -R $FLUENT_USER /fluentd

USER $FLUENT_USER
CMD bundle exec fluentd -c /fluentd/etc/fluent.conf