BACKEND?=docker
CONCURRENCY?=1
CI_ARGS?=

# Abs path only. It gets copied in chroot in pre-seed stages
export LUET?=/usr/bin/luet
export ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
DESTINATION?=$(ROOT_DIR)/build
TARGET?=targets
COMPRESSION?=gzip
CLEAN?=false
export TREE?=tree
BUILD_ARGS?=--pull --image-repository sabayonarm/luetcache
SUDO?=

.PHONY: all
all: deps build

.PHONY: deps
deps:
	@echo "Installing luet"
	go get -u github.com/mudler/luet
	go get -u github.com/MottainaiCI/mottainai-cli

.PHONY: clean
clean:
	$(SUDO) rm -rf build/ *.tar *.metadata.yaml

.PHONY: build
build: clean
	mkdir -p $(ROOT_DIR)/build
	$(SUDO) $(LUET) build $(BUILD_ARGS) --clean=$(CLEAN) --tree=$(TREE)  `cat $(ROOT_DIR)/$(TARGET) | xargs echo` --destination $(ROOT_DIR)/build --backend $(BACKEND) --concurrency $(CONCURRENCY) --compression $(COMPRESSION)

.PHONY: build-all
build-all: clean
	mkdir -p $(ROOT_DIR)/build
	$(SUDO) $(LUET) build $(BUILD_ARGS) --clean=$(CLEAN) --tree=$(TREE) --all --destination $(ROOT_DIR)/build --backend $(BACKEND) --concurrency $(CONCURRENCY) --compression $(COMPRESSION)

.PHONY: rebuild
rebuild:
	$(SUDO) $(LUET) build $(BUILD_ARGS) --clean=$(CLEAN) --tree=$(TREE) `cat $(ROOT_DIR)/$(TARGET) | xargs echo` --destination $(ROOT_DIR)/build --backend $(BACKEND) --concurrency $(CONCURRENCY) --compression $(COMPRESSION)

.PHONY: rebuild-all
rebuild-all:
	$(SUDO) $(LUET) build $(BUILD_ARGS) --clean=$(CLEAN) --tree=$(TREE) --all --destination $(ROOT_DIR)/build --backend $(BACKEND) --concurrency $(CONCURRENCY) --compression $(COMPRESSION)

.PHONY: create-repo
create-repo:
	$(SUDO) $(LUET) create-repo --tree "$(TREE)" \
    --output $(DESTINATION) \
    --packages $(DESTINATION) \
    --name "luet-entropy-repo" \
    --descr "Luet Entropy Repo" \
    --urls "http://localhost:8000" \
    --tree-compression gzip \
    --tree-filename tree.tar \
    --meta-compression gzip \
    --type http


.PHONY: serve-repo
serve-repo:
	LUET_NOLOCK=true $(LUET) serve-repo --port 8000 --dir $(ROOT_DIR)/build

.PHONY: validate
validate:
	$(ROOT_DIR)/scripts/validate.sh

.PHONY: auto-bump
auto-bump:
	$(ROOT_DIR)/scripts/auto-bump.sh

.PHONY: auto-clean
auto-clean:
	$(ROOT_DIR)/scripts/auto-clean.sh

.PHONY: changes
changes:
	$(ROOT_DIR)/scripts/build-changes.sh
