VERSION := $(shell sh -c 'cat VERSION')

clean: 
	@rm -rf pkg/* docker/gem/ docker/gems/ docker/*.gem docker/licenses

build: clean 
	@bundle exec rake build

docker: build install-deps
	@cp pkg/fluent-plugin-*.gem docker
	@mkdir -p docker/licenses
	@cp -rp LICENSE docker/licenses/
	@docker build --no-cache --pull --build-arg VERSION=$(VERSION) -t splunk/fluentd-hec:$(VERSION) ./docker

unit-test:
	@bundle exec rake test

install-deps:
	@gem install bundler
	@bundle update --bundler
	@bundle install