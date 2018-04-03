FROM ruby:2.5-alpine

# update ruby library dependencies
WORKDIR /app
ADD . /app

#create folder and copy Gemfile, 
RUN apk add --no-cache build-base jq-dev git \
  && bundle
#if passed rake build gem


# push gem