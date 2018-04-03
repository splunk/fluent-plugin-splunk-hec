FROM ruby:2.4-alpine

# update ruby library dependencies
WORKDIR /app
ADD . /app

#create folder and copy Gemfile, 
RUN apk add --no-cache build-base jq-dev git \
  && bundle \
  && rake

#copy lib/fluent/plugin

# copytest

# rake test

#if passed rake build gem


# push gem