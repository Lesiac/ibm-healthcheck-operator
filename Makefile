# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Specify whether this repo is build locally or not, default values is '1';
# If set to 1, then you need to also set 'DOCKER_USERNAME' and 'DOCKER_PASSWORD'
# environment variables before build the repo.
BUILD_LOCALLY ?= 1

# Image URL to use all building/pushing image targets;
# Use your own docker registry and image name for dev/test by overridding the
# IMAGE_REPO, IMAGE_NAME and RELEASE_TAG environment variable.
IMAGE_REPO ?= quay.io/opencloudio
IMAGE_NAME ?= ibm-healthcheck-operator

# Github host to use for checking the source tree;
# Override this variable ue with your own value if you're working on forked repo.
GIT_HOST ?= github.com/IBM

PWD := $(shell pwd)
BASE_DIR := $(shell basename $(PWD))

# Keep an existing GOPATH, make a private one if it is undefined
GOPATH_DEFAULT := $(PWD)/.go
export GOPATH ?= $(GOPATH_DEFAULT)
GOBIN_DEFAULT := $(GOPATH)/bin
export GOBIN ?= $(GOBIN_DEFAULT)
TESTARGS_DEFAULT := "-v"
export TESTARGS ?= $(TESTARGS_DEFAULT)
DEST := $(GOPATH)/src/$(GIT_HOST)/$(BASE_DIR)
VERSION ?= $(shell git describe --exact-match 2> /dev/null || \
                 git describe --match=$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)

LOCAL_OS := $(shell uname)
ifeq ($(LOCAL_OS),Linux)
    TARGET_OS ?= linux
    XARGS_FLAGS="-r"
else ifeq ($(LOCAL_OS),Darwin)
    TARGET_OS ?= darwin
    XARGS_FLAGS=
else
    $(error "This system's OS $(LOCAL_OS) isn't recognized/supported")
endif

ARCH := $(shell uname -m)
LOCAL_ARCH := "amd64"
ifeq ($(ARCH),x86_64)
    LOCAL_ARCH="amd64"
else ifeq ($(ARCH),ppc64le)
    LOCAL_ARCH="ppc64le"
else ifeq ($(ARCH),s390x)
    LOCAL_ARCH="s390x"
else
    $(error "This system's ARCH $(ARCH) isn't recognized/supported")
endif

all: fmt check test coverage build images

ifeq (,$(wildcard go.mod))
ifneq ("$(realpath $(DEST))", "$(realpath $(PWD))")
    $(error Please run 'make' from $(DEST). Current directory is $(PWD))
endif
endif

include common/Makefile.common.mk

############################################################
# work section
############################################################
$(GOBIN):
	@echo "create gobin"
	@mkdir -p $(GOBIN)

work: $(GOBIN)

############################################################
# format section
############################################################

# All available format: format-go format-python
# Default value will run all formats, override these make target with your requirements:
#    eg: fmt: format-go format-protos
fmt: format-go format-python

############################################################
# check section
############################################################

check: lint

# All available linters: lint-dockerfiles lint-scripts lint-yaml lint-copyright-banner lint-go lint-python lint-helm lint-markdown
# Default value will run all linters, override these make target with your requirements:
#    eg: lint: lint-go lint-yaml
# The MARKDOWN_LINT_WHITELIST variable can be set with comma separated urls you want to whitelist
lint: lint-all

############################################################
# test section
############################################################

test:
	@go test ${TESTARGS} ./...

############################################################
# coverage section
############################################################

coverage:
	@common/scripts/codecov.sh ${BUILD_LOCALLY}

############################################################
# build section
############################################################

build: build-amd64 build-ppc64le build-s390x

build-amd64:
	@echo "Building the ${IMAGE_NAME} amd64 binary..."
	@GOARCH=amd64 common/scripts/gobuild.sh build/_output/bin/$(IMAGE_NAME) ./cmd/manager

build-ppc64le:
	@echo "Building the ${IMAGE_NAME} ppc64le binary..."
	@GOARCH=ppc64le common/scripts/gobuild.sh build/_output/bin/$(IMAGE_NAME)-ppc64le ./cmd/manager

build-s390x:
	@echo "Building the ${IMAGE_NAME} s390x binary..."
	@GOARCH=s390x common/scripts/gobuild.sh build/_output/bin/$(IMAGE_NAME)-s390x ./cmd/manager

############################################################
# image section
############################################################

ifeq ($(BUILD_LOCALLY),0)
    export CONFIG_DOCKER_TARGET = config-docker
endif

build-image: build-image-amd64 build-image-ppc64le build-image-s390x

build-image-amd64: build-amd64
	@docker build -t $(IMAGE_REPO)/$(IMAGE_NAME)-amd64:$(VERSION) -f build/Dockerfile .

build-image-ppc64le: build-ppc64le
	@docker run --rm --privileged multiarch/qemu-user-static:register --reset
	@docker build -t $(IMAGE_REPO)/$(IMAGE_NAME)-ppc64le:$(VERSION) -f build/Dockerfile.ppc64le .

build-image-s390x: build-s390x
	@docker run --rm --privileged multiarch/qemu-user-static:register --reset
	@docker build -t $(IMAGE_REPO)/$(IMAGE_NAME)-s390x:$(VERSION) -f build/Dockerfile.s390x .

push-image-amd64: $(CONFIG_DOCKER_TARGET) build-image-amd64
	@docker push $(IMAGE_REPO)/$(IMAGE_NAME)-amd64:$(VERSION)

push-image-ppc64le: $(CONFIG_DOCKER_TARGET) build-image-ppc64le
	@docker push $(IMAGE_REPO)/$(IMAGE_NAME)-ppc64le:$(VERSION)

push-image-s390x: $(CONFIG_DOCKER_TARGET) build-image-s390x
	@docker push $(IMAGE_REPO)/$(IMAGE_NAME)-s390x:$(VERSION)

############################################################
# multiarch-image section
############################################################

images: push-image-amd64 push-image-ppc64le push-image-s390x multiarch-image

multiarch-image:
	@curl -L -o /tmp/manifest-tool https://github.com/estesp/manifest-tool/releases/download/v1.0.0/manifest-tool-linux-amd64
	@chmod +x /tmp/manifest-tool
	/tmp/manifest-tool push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(IMAGE_REPO)/$(IMAGE_NAME)-ARCH:$(VERSION) --target $(IMAGE_REPO)/$(IMAGE_NAME) --ignore-missing
	/tmp/manifest-tool push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(IMAGE_REPO)/$(IMAGE_NAME)-ARCH:$(VERSION) --target $(IMAGE_REPO)/$(IMAGE_NAME):$(VERSION) --ignore-missing

############################################################
# clean section
############################################################
clean:
	@rm -rf build/_output

.PHONY: all work fmt check coverage lint test build image images multiarch-image clean
