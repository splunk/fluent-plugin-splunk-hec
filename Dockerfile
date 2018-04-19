FROM ruby:2.5-alpine

WORKDIR /app
ADD . /app

RUN apk add --no-cache build-base \
  && bundle \
  && gem build fluent-plugin-splunk-hec.gemspec

CMD ["/bin/sh"]