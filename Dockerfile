FROM ruby:2.5-alpine

WORKDIR /app
ADD . /app

RUN apk add --no-cache build-base jq-dev git \
  && bundle
