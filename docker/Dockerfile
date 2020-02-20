FROM registry.access.redhat.com/ubi8/ruby-25

ARG VERSION

MAINTAINER DataEdge DataEdge@splunk.com

LABEL name="Splunk Connect for Kubernetes Logging container" \
      maintainer="DataEdge@splunk.com" \
      vendor="Splunk Inc." \
      version=${VERSION} \
      release=${VERSION} \
      summary="Splunk Connect for Kubernetes Logging container" \
      description="Splunk Connect for Kubernetes Logging container"

ENV FLUENT_USER fluent

USER root

COPY *.gem /tmp/
COPY licenses /licenses

RUN wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
      chmod +x ./jq && \
      cp jq /usr/bin

COPY Gemfile* ./
RUN gem install bundler \
   && bundle install \
   && bundle exec gem install /tmp/*.gem

 RUN groupadd -r $FLUENT_USER && \
   useradd -r -g $FLUENT_USER $FLUENT_USER && \
   mkdir -p /fluentd/log fluentd/etc /fluentd/plugins &&\
   chown -R $FLUENT_USER /fluentd && chgrp -R $FLUENT_USER /fluentd

USER $FLUENT_USER
CMD exec fluentd -c /fluentd/etc/fluent.conf