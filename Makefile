SWIPL=LANG=C.UTF-8 $(SWIPL_DIR)swipl
RONN_FILE=docs/terminusdb.1.ronn
ROFF_FILE=docs/terminusdb.1
TARGET=terminusdb
ENTERPRISE=false

RUST_SOURCE_DIR := src/rust
RUST_FILES = src/rust/Cargo.toml src/rust/Cargo.lock $(shell find src/rust/terminusdb-community/src/ -type f -name '*.rs')
PROLOG_FILES = $(shell find ./ -not -path './rust/*' \( -name '*.pl' -o -name '*.ttl' -o -name '*.json' \))

ifeq ($(shell uname), Darwin)
	RUST_LIB_NAME := libterminusdb_dylib.dylib
	RUST_LIB_TARGET_NAME := librust.dylib
else
	RUST_LIB_NAME := libterminusdb_dylib.so
	RUST_LIB_TARGET_NAME := librust.so
endif

RUST_LIBRARY_FILE:=src/rust/target/release/$(RUST_LIB_NAME)
ENTERPRISE_RUST_LIBRARY_FILE:=terminusdb-enterprise/rust/target/release/$(RUST_LIB_NAME)
RUST_TARGET:=src/rust/$(RUST_LIB_TARGET_NAME)

SWIPL_LINT_VERSION=v0.8
SWIPL_LINT_PATH=./tmp/pl_lint-$(SWIPL_LINT_VERSION).pl

################################################################################

# Build the 'community' binary (default).
.PHONY: community
community: $(TARGET)

# Build the 'enterprise' binary.
.PHONY: enterprise
enterprise: PROLOG_FILES += $(shell find terminusdb-enterprise/prolog \( -name '*.pl' -o -name '*.ttl' -o -name '*.json' \))
enterprise: RUST_FILES += ./terminusdb-enterprise/rust/Cargo.toml ./terminusdb-enterprise/rust/Cargo.lock $(shell find terminusdb-enterprise/rust/ -type f -name '*.rs')
enterprise: RUST_LIBRARY_FILE := $(ENTERPRISE_RUST_LIBRARY_FILE)
enterprise: RUST_SOURCE_DIR := terminusdb-enterprise/rust
enterprise: ENTERPRISE := true
enterprise: $(TARGET)

# Build the 'community' binary and the documentation.
.PHONY: all
all: community docs

# Build the Docker image for development and testing. To use the TerminusDB
# container, see: https://github.com/terminusdb/terminusdb-bootstrap
.PHONY: docker
docker:
	docker build . \
	  --file Dockerfile \
	  --tag terminusdb/terminusdb-server:local \
	  --build-arg TERMINUSDB_GIT_HASH="$(git rev-parse --verify HEAD)"

# Install all pack dependencies.
.PHONY: install-deps
install-deps:
	$(SWIPL) \
	  --on-error=halt \
	  --on-warning=halt \
	  -g 'Options=[interactive(false), upgrade(true), test(false)], pack_install(tus, Options), halt'

# Download and run the lint tool.
.PHONY: lint
lint: $(SWIPL_LINT_PATH)
	$(SWIPL) -f src/load_paths.pl src/core/query/expansions.pl $(SWIPL_LINT_PATH)

.PHONY: module
module: $(RUST_TARGET)

.PHONY: enterprise-module
enterprise-module: RUST_FILES += terminusdb-enterprise/rust/Cargo.toml terminusdb-enterprise/rust/Cargo.lock $(shell find terminusdb-enterprise/rust/ -type f -name '*.rs')
enterprise-module: RUST_LIBRARY_FILE := $(ENTERPRISE_RUST_LIBRARY_FILE)
enterprise-module: RUST_SOURCE_DIR := terminusdb-enterprise/rust
enterprise-module: $(RUST_TARGET)

# Build a debug version of the binary.
.PHONY: debug
debug: $(RUST_TARGET)
	echo "main, halt." | $(SWIPL) -f src/bootstrap.pl

# Run the unit tests in swipl.
.PHONY: test
test: $(RUST_TARGET)
	$(SWIPL) \
	  --on-error=halt \
	  --on-warning=halt \
	  -t 'run_tests, halt' \
	  -f src/interactive.pl

# Quick command for interactive
.PHONY: i
i: $(RUST_TARGET)
	$(SWIPL) -f src/interactive.pl

# Remove the binary.
.PHONY: clean
clean: shallow-clean
	cd src/rust && cargo clean

.PHONY: enterprise-clean
enterprise-clean: shallow-clean
	cd terminusdb-enterprise/rust && cargo clean

.PHONY: module-clean
module-clean:
	rm -f $(RUST_TARGET)

.PHONY: shallow-clean
shallow-clean: module-clean
	rm -f $(TARGET)

# Build the documentation.
.PHONY: docs
docs: $(ROFF_FILE)

# Remove the documentation.
.PHONY: docs-clean
docs-clean:
	rm -f $(RONN_FILE) $(ROFF_FILE)

################################################################################

$(TARGET): $(RUST_TARGET) $(PROLOG_FILES)
	TERMINUSDB_ENTERPRISE=$(ENTERPRISE) $(SWIPL) \
	  --on-error=halt \
	  --on-warning=halt \
	  --quiet \
	  -O \
	  -t 'main, halt' \
	  -f src/bootstrap.pl

$(RUST_TARGET): $(RUST_FILES)
	cd $(RUST_SOURCE_DIR) && cargo build --release
	cp $(RUST_LIBRARY_FILE) $(RUST_TARGET)

# Create input for `ronn` from a template and the `terminusdb` help text.
$(RONN_FILE): docs/terminusdb.1.ronn.template $(TARGET)
	HELP="$$(./$(TARGET) help -m)" envsubst < $< > $@

# Create a man page from using `ronn`.
$(ROFF_FILE): $(RONN_FILE)
	ronn --roff $<

$(SWIPL_LINT_PATH):
	curl -L --create-dirs -o $@ "https://raw.githubusercontent.com/terminusdb-labs/swipl-lint/$(SWIPL_LINT_VERSION)/pl_lint.pl"
