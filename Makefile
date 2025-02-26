VERSION := $(shell cat VERSION.txt)
PREFIX?=$(shell pwd)
EXAMPLES_DIR := examples

## Tools
BINDIR := $(PREFIX)/bin
export GOBIN :=$(BINDIR)
export PATH := $(GOBIN):$(PATH)
SEMBUMP := $(BINDIR)/sembump

all: init fmt validate tflint tfsec

.PHONY: init
init: ## Initialize a Terraform working directory
	@echo "+ $@"
	@terraform init

.PHONY: fmt
fmt: ## Rewrites Terraform files to canonical format
	@echo "+ $@"
	@terraform fmt -check=true -recursive

.PHONY: validate
validate: ## Validates the Terraform files
	@echo "+ $@"
	@AWS_REGION=eu-west-1 terraform validate

.PHONY: tflint
tflint: ## Runs tflint on all Terraform files
	@echo "+ $@"
	@tflint -f compact || exit 1

.PHONY: tfsec
tfsec: ## Runs tfsec on all Terraform files
	@echo "+ $@"
	@tfsec . --exclude-downloaded-modules --concise-output || exit 1

.PHONY: test
test: ## Runs all terratests
	@echo "+ $@"
	@cd test && go test -v -count=1 -timeout 30m

.PHONY: documentation
documentation: ## Generates README.md from static snippets and Terraform variables
	@echo "+ $@"
	terraform-docs markdown table . > docs/part2.md
	cat docs/*.md > README.md
	terraform-docs markdown table modules/deployment > docs/deployment/part2.md
	cat docs/deployment/*.md > modules/deployment/README.md

$(SEMBUMP):
	GO111MODULE=off go get -u github.com/jessfraz/junk/sembump

.PHONY: bump-version
BUMP ?= patch
bump-version: $(SEMBUMP) ## Bump the version in the version file. Set BUMP to [ patch | major | minor ].
	@echo "+ $@"
	$(eval NEW_VERSION = $(shell $(BINDIR)/sembump --kind $(BUMP) $(VERSION)))
	@echo "Bumping VERSION.txt from $(VERSION) to $(NEW_VERSION)"
	echo $(NEW_VERSION) > VERSION.txt
	@echo "Updating links in README.md"
	sed -i '' s/$(subst v,,$(VERSION))/$(subst v,,$(NEW_VERSION))/g docs/part1.md

.PHONY: check-git-clean
check-git-clean:
	@echo "+ $@"
	@git diff-index --quiet HEAD || (echo "There are uncomitted changes"; exit 1)

.PHONY: check-git-branch
check-git-branch: check-git-clean
	@echo "+ $@"
	git fetch --all --tags --prune
	git checkout main

release: check-git-branch bump-version documentation ## Releases a new module version
	@echo "+ $@"
	git add VERSION.txt README.md docs/part1.md
	git commit -vsam "Bump version to $(NEW_VERSION)"
	git tag -a $(NEW_VERSION) -m "$(NEW_VERSION)"
	git push origin $(NEW_VERSION)
	git push
	# create GH release if GITHUB_TOKEN is set
	if [ ! -z "${GITHUB_TOKEN}" ] ; then 												\
    	curl 																		\
    		-H "Authorization: token ${GITHUB_TOKEN}" 								\
    		-X POST 																\
    		-H "Accept: application/vnd.github.v3+json"								\
    		https://api.github.com/repos/moritzzimmer/terraform-aws-lambda/releases \
    		-d "{\"tag_name\":\"$(NEW_VERSION)\",\"generate_release_notes\":true}"; 									\
	fi;

.PHONY: help
help: ## Display this help screen
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
