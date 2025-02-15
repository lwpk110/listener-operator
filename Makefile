
ORG_PATH=github.com/zncdatadev
PROJECT_NAME := listener-operator
BUILD_COMMIT := $(shell git rev-parse --short HEAD)
REPO_PATH=$(ORG_PATH)/$(PROJECT_NAME)

# build variables
BUILD_TIMESTAMP := $$(date +%Y-%m-%d-%H:%M)
BUILD_TIME_VAR := $(REPO_PATH)/internal/csi/version.BuildTime
GIT_COMMIT_VAR := $(REPO_PATH)/internal/csi/version.GitCommit
BUILD_VERSION_VAR := $(REPO_PATH)/internal/csi/version.BuildVersion
LDFLAGS ?= "-X $(BUILD_TIME_VAR)=$(BUILD_TIMESTAMP) -X $(GIT_COMMIT_VAR)=$(BUILD_COMMIT) -X $(BUILD_VERSION_VAR)=$(VERSION)"

# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 0.0.1

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

REGISTRY ?= quay.io/zncdata
PROJECT_NAME = listener-operator

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# zncdata.dev/listener-operator-bundle:$VERSION and zncdata.dev/listener-operator-catalog:$VERSION.
IMAGE_TAG_BASE ?= $(REGISTRY)/$(PROJECT_NAME)

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:v$(VERSION)

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.33.0

# Image URL to use all building/pushing image targets
IMG ?= $(IMAGE_TAG_BASE):v$(VERSION)
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
# ref: https://github.com/kubernetes-sigs/kubebuilder/releases in v3.11.0-v3.14.1 ENVTEST_K8S_VERSION support 1.26.1 and 1.27.1
ENVTEST_K8S_VERSION ?= 1.26.1

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build -o bin/manager cmd/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/main.go

# If you wish built the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64 ). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: test ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} -f build/Dockerfile .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

# PLATFORMS defines the target platforms for  the manager image be build to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - able to use docker buildx . More info: https://docs.docker.com/build/buildx/
# - have enable BuildKit, More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image for your registry (i.e. if you do not inform a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To properly provided solutions that supports more than one platform you should use this option.
PLATFORMS ?= linux/arm64,linux/amd64
.PHONY: docker-buildx
docker-buildx: test ## Build and push docker image for the manager for cross-platform support
	- $(CONTAINER_TOOL) buildx create --name project-v3-builder
	$(CONTAINER_TOOL) buildx use project-v3-builder
	- $(CONTAINER_TOOL) buildx build -f build/Dockerfile --push --platform=$(PLATFORMS) --tag ${IMG} .
	- $(CONTAINER_TOOL) buildx rm project-v3-builder
	rm Dockerfile.cross

##@ CSIDriver

CSIDRIVER_IMG ?= ${REGISTRY}/listener-csi-driver:v$(VERSION)

.PHONY: csi-build
csi-build: ## Build csi driver.
	go build -a -ldflags $(LDFLAGS) -o bin/csi-driver cmd/csi_driver/main.go

.PHONY: csi-run
csi-run: ## Run csi driver.
	go run ./cmd/csi-driver/main.go

.PHONY: csi-docker-build
csi-docker-build: ## Build docker image with the csi driver.
	$(CONTAINER_TOOL) build --build-arg LDFLAGS=$(LDFLAGS) --tag ${CSIDRIVER_IMG} -f build/csi-driver.Dockerfile .

.PHONY: csi-docker-push
csi-docker-push: ## Push docker image with the csi driver.
	$(CONTAINER_TOOL) push ${CSIDRIVER_IMG}


.PHONY: csi-docker-buildx
csi-docker-buildx: ## Build and push docker image for the csi driver for cross-platform support
	- $(CONTAINER_TOOL) buildx create --name project-v3-builder
	$(CONTAINER_TOOL) buildx use project-v3-builder
	$(CONTAINER_TOOL) buildx build --push --build-arg LDFLAGS=$(LDFLAGS) --platform=$(PLATFORMS) --tag ${CSIDRIVER_IMG} -f build/csi-driver.Dockerfile .
	- $(CONTAINER_TOOL) buildx rm project-v3-builder

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | $(KUBECTL) apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUBECTL ?= kubectl
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v5.3.0
CONTROLLER_TOOLS_VERSION ?= v0.13.0

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	test -s $(LOCALBIN)/kustomize || GOBIN=$(LOCALBIN) GO111MODULE=on go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	# after v0.0.0-20240320141353-395cfc7486e6, setup-envtest is require go >= 1.22.0
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@v0.0.0-20240320141353-395cfc7486e6

.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$${OS}_$${ARCH} ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

.PHONY: bundle
bundle: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

.PHONY: opm
OPM = ./bin/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.23.0/$${OS}-$${ARCH}-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:v$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

.PHONY: catalog-build
catalog-build: opm ## Build a catalog manifests.
	mkdir -p catalog
	@if test -x ./catalog.Dockerfile; then \
		opm generate dockerfile catalog; \
	fi
	opm alpha render-template semver semver.yaml -o yaml > catalog/catalog.yaml

.PHONY: catalog-docker-build
catalog-docker-build: ## Build a catalog image.
	$(CONTAINER_TOOL) build -t ${CATALOG_IMG} -f catalog.Dockerfile .

# Push the catalog image.
.PHONY: catalog-docker-push
catalog-docker-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)

.PHONY: catalog-docker-buildx
catalog-docker-buildx: ## Build and push a catalog image for cross-platform support
	- $(CONTAINER_TOOL) buildx create --name project-v3-builder
	$(CONTAINER_TOOL) buildx use project-v3-builder
	- $(CONTAINER_TOOL) buildx build -f catalog.Dockerfile --push --tag ${CATALOG_IMG} .
	- $(CONTAINER_TOOL) buildx rm project-v3-builder

##@ E2E

# kind
KIND_VERSION ?= v0.22.0

KINDTEST_K8S_VERSION ?= 1.26.14

KIND_IMAGE ?= kindest/node:v${KINDTEST_K8S_VERSION}

KIND_KUBECONFIG ?= ./kind-kubeconfig-$(KINDTEST_K8S_VERSION) 
KIND_CLUSTER_NAME ?= ${PROJECT_NAME}-$(KINDTEST_K8S_VERSION) 

.PHONY: kind
KIND = $(LOCALBIN)/kind
kind: ## Download kind locally if necessary.
ifeq (,$(shell which $(KIND)))
ifeq (,$(shell which kind 2>/dev/null))
	@{ \
	set -e ;\
	go install sigs.k8s.io/kind@$(KIND_VERSION) ;\
	}
KIND = $(GOBIN)/bin/kind
else
KIND = $(shell which kind)
endif
endif

OLM_VERSION ?= v0.27.0

# Create a kind cluster, install ingress-nginx, and wait for it to be available.
.PHONY: kind-create
kind-create: kind ## Create a kind cluster.
	$(KIND) create cluster --config test/e2e/kind-config.yaml --image $(KIND_IMAGE) --name $(KIND_CLUSTER_NAME) --kubeconfig $(KIND_KUBECONFIG) --wait 120s
	# make kind-setup KUBECONFIG=$(KIND_KUBECONFIG)

.PHONY: kind-setup
kind-setup: kind ## setup kind cluster base environment
	@echo "\nSetup kind cluster base environment, install ingress-nginx and OLM"
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	kubectl -n ingress-nginx wait deployment ingress-nginx-controller --for=condition=available --timeout=300s
	curl -sSL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/$(OLM_VERSION)/install.sh | bash -s $(OLM_VERSION)

.PHONY: kind-delete
kind-delete: kind ## Delete a kind cluster.
	$(KIND) delete cluster --name $(KIND_CLUSTER_NAME)

# chainsaw

CHAINSAW_VERSION ?= v0.1.8

.PHONY: chainsaw
CHAINSAW = $(LOCALBIN)/chainsaw
chainsaw: ## Download chainsaw locally if necessary.
ifeq (,$(shell which $(CHAINSAW)))
ifeq (,$(shell which chainsaw 2>/dev/null))
	@{ \
	set -e ;\
	go install github.com/kyverno/chainsaw@$(CHAINSAW_VERSION) ;\
	}
CHAINSAW = $(GOBIN)/chainsaw
else
CHAINSAW = $(shell which chainsaw)
endif
endif

# chainsaw setup logical
# - Build the operator docker image
# - Load the operator docker image into the kind cluster. When create
#   operator deployment, it will use the image in the kind cluster.
# - Rebuild the bundle. If override VERSION / REGISTRY or other variables,
#   we need to rebuild the bundle to use the new image, or other changes.
.PHONY: chainsaw-setup
chainsaw-setup: manifests kustomize ## Run the chainsaw setup
	@echo "\nSetup chainsaw test environment"
	make docker-build
	make csi-docker-build
	$(KIND) --name $(KIND_CLUSTER_NAME) load docker-image $(IMG) $(CSIDRIVER_IMG)
	make deploy KUBECONFIG=$(KIND_KUBECONFIG)

.PHONY: chainsaw-test
chainsaw-test: chainsaw ## Run the chainsaw test
	$(CHAINSAW) test --cluster cluster-1=$(KIND_KUBECONFIG) --test-dir ./test/e2e

.PHONY: chainsaw-cleanup
chainsaw-cleanup: manifests kustomize ## Run the chainsaw cleanup
	make undeploy KUBECONFIG=$(KIND_KUBECONFIG)
