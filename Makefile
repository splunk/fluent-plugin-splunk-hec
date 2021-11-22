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
	@docker build --no-cache --pull --build-arg VERSION=$(VERSION) -t splunk/fluentd-hec:$(VERSION) . -f docker/Dockerfile

docker-rebuild:
	@docker build --build-arg VERSION=$(VERSION) -t splunk/fluentd-hec:$(VERSION) ./docker
	
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


export KUBE_VERSION=v1.20.7
export KIND_NAME="fpsh-${KUBE_VERSION}"

GIT_COMMIT?=$(shell git rev-parse HEAD)

kind-delete:
	kind delete clusters ${KIND_NAME}

kind-create:
	kind get clusters | grep ${KIND_NAME} || kind create cluster --name ${KIND_NAME} --image "kindest/node:${KUBE_VERSION}"
	kubectl config use-context kind-${KIND_NAME}

kind: kind-create kind-context
	-kubectl create ns splunk
	kubectl -n splunk apply -f ci_scripts/k8s-splunk.yml

kind-context:
	kubectl config use-context kind-${KIND_NAME}


kind-load:
	docker tag splunk/fluentd-hec:1.3.0-beta local.dev/fluentd-hec:1.3.0-beta
	kind load docker-image local.dev/fluentd-hec:1.3.0-beta --name federated-splunk-connect-v1.17.5
	kubectl -n splunk-system patch daemonset splunk-kubernetes-logging --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value":"Never"}]'
	kubectl -n splunk-system patch daemonset splunk-kubernetes-logging --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"local.dev/fluentd-hec:1.3.0-beta"}]'
	kubectl -n splunk-system rollout restart daemonset
	sleep 10
	kubectl -n splunk-system get pod
