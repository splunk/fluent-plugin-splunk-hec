VERSION := $(shell sh -c 'cat VERSION')

clean_pkg: 
	@rm -rf pkg/* docker/*.gem 

clean_gems:
	@rm -rf docker/gem/ docker/gems/

clean: clean_pkg clean_gems
	@rm -rf docker/licenses

build: clean_pkg 
	@bundle exec rake build

docker: install-deps build
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

unpack: build
	@cp pkg/fluent-plugin-*.gem docker
	@gem unpack docker/fluent-plugin-*.gem --target docker/gem
	@cd docker && bundle install
