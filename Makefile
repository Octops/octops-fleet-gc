.PHONY: all build clean install get test up deploy-local down docker helm-package

## overridable Makefile variables
# test to run
TESTSET = .
# benchmarks to run
BENCHSET ?= .

# version (defaults to short git hash)
VERSION ?= $(shell git rev-parse --short HEAD)

# use correct sed for platform
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    SED := gsed
else
    SED := sed
endif

PKG_NAME=github.com/Octops/octops-fleet-gc

LDFLAGS := -X "${PKG_NAME}/internal/version.Version=${VERSION}"
LDFLAGS += -X "${PKG_NAME}/internal/version.BuildTS=$(shell date -u '+%Y-%m-%d %I:%M:%S')"
LDFLAGS += -X "${PKG_NAME}/internal/version.GitCommit=$(shell git rev-parse HEAD)"
LDFLAGS += -X "${PKG_NAME}/internal/version.GitBranch=$(shell git rev-parse --abbrev-ref HEAD)"

GO       := GO111MODULE=on GOPRIVATE=github.com/Octops GOSUMDB=off go
GOBUILD  := CGO_ENABLED=0 $(GO) build $(BUILD_FLAG)
GOTEST   := $(GO) test -gcflags='-l' -p 3

CURRENT_DIR := $(shell pwd)
FILES    := $(shell find internal cmd -name '*.go' -type f -not -name '*.pb.go' -not -name '*_generated.go' -not -name '*_test.go')
TESTS    := $(shell find internal cmd -name '*.go' -type f -not -name '*.pb.go' -not -name '*_generated.go' -name '*_test.go')

OCTOPS_BIN := bin/octops-fleet-gc

IMAGE_REPO=octops/octops-fleet-gc
DOCKER_IMAGE_TAG ?= octops/octops-fleet-gc:${VERSION}
RELEASE_TAG=0.0.1

default: clean build ## By default will cleanup dir $OCTOPS_BIN and will start project building with GOLANG.	

build: clean $(OCTOPS_BIN)

$(OCTOPS_BIN):
	CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags '$(LDFLAGS)' -a -installsuffix cgo -o $(OCTOPS_BIN) ./cmd

dist:
	CGO_ENABLED=0 GOOS=linux go build -ldflags '$(LDFLAGS)' -a -installsuffix cgo -o $(OCTOPS_BIN) ./cmd
	CGO_ENABLED=0 GOOS=darwin go build -ldflags '$(LDFLAGS)' -a -installsuffix cgo -o $(OCTOPS_BIN)-darwin ./cmd

clean:
	rm -f $(OCTOPS_BIN)*

get:
	$(GO) get ./...
	$(GO) mod verify
	$(GO) mod tidy

update:
	$(GO) get -u -v all
	$(GO) mod verify
	$(GO) mod tidy

fmt:
	gofmt -s -l -w $(FILES) $(TESTS)

lint:
	golangci-lint run

test:
	$(GO) clean -testcache
	$(GOTEST) -run=$(TESTSET) ./...
	@echo
	@echo Configured tests ran ok.

test-strict:
	$(GO) test -p 3 -run=$(TESTSET) -gcflags='-l -m' -race ./...
	@echo
	@echo Configured tests ran ok.

bench:
	DEBUG=0 $(GOTEST) -run=nothing -bench=$(BENCHSET) -benchmem ./...
	@echo
	@echo Configured benchmarks ran ok.

vendor:
	$(GO) mod vendor

docker:
	docker build -t $(DOCKER_IMAGE_TAG) .

buildx:
	docker buildx build --platform linux/arm64/v8,linux/amd64 --push --tag $(IMAGE_REPO):$(RELEASE_TAG) .

push: docker ## Docker build and push
	docker push $(DOCKER_IMAGE_TAG)

install:
	kubectl -n octops-system apply -f ./deploy/install.yaml

# This action creates and deploys a controller using Helm.
## vars for building a helm package
HELM_CHART_NAME=octops-fleet-gs
HELM_CHART_DIR=./deploy/helm
AWS_OCI=oci://$(AWS-ECR-PUBLIC-REPO)
VERSION_PACKAGE=$(shell sed -n -e 's/^version:\s* //p' $(HELM_CHART_DIR)/Chart.yaml)
##functions for building a helm package
define f_helm_template
	@echo "" && echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
	@cd $(HELM_CHART_DIR)
	@echo "[*] Processing helm template"
	@helm template $(HELM_CHART_DIR);
endef

define f_helm_install_dryrun
	@echo "" && echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
	@echo "[*] Processing helm install with dry-run "
	@helm install $(HELM_CHART_NAME) --dry-run --debug $(HELM_CHART_DIR);
endef

define f_helm_install
	@echo "" && echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
	@echo "[*] Processing helm install with dry-run "
	@helm upgrade --install $(HELM_CHART_NAME) --create-namespace -n octops-system --debug $(HELM_CHART_DIR);
endef

define f_helm_lint
	@echo "" && echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
	@echo "[*] Processing helm lint"
	@helm lint $(HELM_CHART_DIR);
endef

define f_helm_package
	@echo "" && echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
	@echo "[*] Processing helm package"
	@cat $(HELM_CHART_DIR)/Chart.yaml | grep 'version: '
	@helm package $(HELM_CHART_DIR)
endef

define f_upload_to_aws_ecr
	@echo "" && echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
	@echo "[ ] Login to ECR..."
	@aws sts get-caller-identity | jq
	@aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws
	@echo "[ ] Uploading to ECR..."
	@echo  $(AWS_OCI)
	@helm push $(HELM_CHART_NAME)-$(VERSION_PACKAGE).tgz $(AWS_OCI) && echo " -> Successfully uploaded!";
endef

helm-package: ## Verify configuration with all possible checks and PACKAGE
	$(call f_helm_template)
	$(call f_helm_install_dryrun)
	$(call f_helm_lint)
	$(call f_helm_package)

helm-upload-to-aws-ecr: helm-package ## Verify, package, upload to your aws ecr public repo\
it needs to set parameter "AWS-ECR-PUBLIC-REPO"\
Example: make helm-upload-to-aws-ecr AWS-ECR-PUBLIC-REPO=public.ecr.aws/*****
	$(call f_upload_to_aws_ecr)

helm-install: ## Verify configuration with all possible checks and INSTALL or UPDATE
	$(call f_helm_template)
	$(call f_helm_install_dryrun)
	$(call f_helm_lint)
	$(call f_helm_install)

help:
	@perl -pe 's/\\\n/ /' $(MAKEFILE_LIST) | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'	
