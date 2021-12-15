VERSION := $(shell sh -c 'cat VERSION')

clean_pkg: 
	@rm -rf pkg/* docker/*.gem 

clean_gems:
	@rm -rf docker/gem/ docker/gems/

clean: clean_pkg clean_gems
	@rm -rf docker/licenses

build: clean_pkg 
	@bundle exec rake build

.PHONY: docker
docker:
	@docker buildx build --no-cache --pull --platform linux/amd64 -o type=image,name=splunk/fluentd-hec:$(VERSION),push=false --build-arg VERSION=$(VERSION) . -f docker/Dockerfile

docker-rebuild:
	@docker buildx build --platform linux/amd64 -o type=image,name=splunk/fluentd-hec:$(VERSION),push=false --build-arg VERSION=$(VERSION) . -f docker/Dockerfile
	
unit-test:
	@bundle exec rake test

install-deps:
	@gem install bundler
	@bundle update --bundler
	@bundle install

unpack: build
	@cp pkg/fluent-plugin-*.gem docker
	@mkdir -p docker/gem
	@rm -rf docker/gem/*
	@gem unpack docker/fluent-plugin-*.gem --target docker/gem
	@cd docker && bundle install
