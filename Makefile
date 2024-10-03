SHELL := /bin/bash
DEPS ?= build

LUA_VERSION ?= luajit 2.1.0-beta3
NVIM_BIN ?= nvim
NVIM_LUA_VERSION := $(shell $(NVIM_BIN) -v 2>/dev/null | grep -E '^Lua(JIT)?' | tr A-Z a-z)
ifdef NVIM_LUA_VERSION
LUA_VERSION ?= $(NVIM_LUA_VERSION)
endif
LUA_NUMBER := $(word 2,$(LUA_VERSION))

TARGET_DIR := $(DEPS)/$(LUA_NUMBER)

ROCKS_PACKAGE_VERSION := $(shell ./.rocks-version ver)
ROCKS_PACKAGE_REVISION := $(shell ./.rocks-version rev)
APPNAME := corevim
TMP_DIR := .tmp

LUAROCKS_INIT ?= $(TMP_DIR)/luarocks-init
LUAROCKS_DEPS ?= $(TMP_DIR)/luarocks-deps
LUAROCKS_TEST_PREPARE ?= $(TMP_DIR)/luarocks-test-prepare
LUAROCKS_MAKE_LOCAL ?= $(TMP_DIR)/luarocks-make-local

HEREROCKS ?= $(DEPS)/hererocks.py
HEREROCKS_URL ?= https://raw.githubusercontent.com/luarocks/hererocks/master/hererocks.py
HEREROCKS_ACTIVE := source $(TARGET_DIR)/bin/activate

LUAROCKS ?= $(TARGET_DIR)/bin/luarocks

BUSTED ?= $(TARGET_DIR)/bin/busted
BUSTED_HELPER ?= $(PWD)/spec/fixtures.lua

LUV ?= $(TARGET_DIR)/lib/lua/$(LUA_NUMBER)/luv.so

LUA_LS ?= $(DEPS)/lua-language-server
LINT_LEVEL ?= Information
LUAROCKS_CONFIG := build/2.1.0-beta3/etc/luarocks/config-5.1.lua
.EXPORT_ALL_VARIABLES:

all: deps

deps: | $(HEREROCKS) $(BUSTED)

test: test_lua test_nvim

test-lua: $(BUSTED) $(LUV)
	@echo Test with $(LUA_VERSION) ......
	@$(HEREROCKS_ACTIVE) && eval $$($(LUAROCKS) path) && \
		$(BUSTED) spec/tests

ifdef NVIM_LUA_VERSION
test-nvim: $(BUSTED)
	@echo Test with Neovim ......
	@$(HEREROCKS_ACTIVE) && eval $$($(LUAROCKS) path) && \
		$(NVIM_BIN) --clean -n --headless -u spec/init.lua -- \
		--helper=$(BUSTED_HELPER) $(BUSTED_ARGS)
endif

$(TMP_DIR):
	@mkdir -p $(TMP_DIR)

$(HEREROCKS): $(TMP_DIR)
	mkdir -p $(DEPS)
	curl $(HEREROCKS_URL) -o $@

$(LUAROCKS): $(HEREROCKS)
	$(HEREROCKS_ENV) python3 $< $(TARGET_DIR) --$(LUA_VERSION) -r latest

$(BUSTED): $(LUAROCKS) | $(LUAROCKS_TEST_PREPARE)
	$(HEREROCKS_ACTIVE) && $(LUAROCKS) install busted

# Ensure luarocks-test-prepare is only run once
$(LUAROCKS_TEST_PREPARE): $(LUAROCKS) ## Installs all dependencies for testing (runs once)
	luarocks test --prepare $(APPNAME)-$(ROCKS_PACKAGE_VERSION)-$(ROCKS_PACKAGE_REVISION).rockspec && \
	touch $(TMP_DIR)/luarocks-test-prepare

$(LUV): $(LUAROCKS)
	@$(HEREROCKS_ACTIVE) && [[ ! $$($(LUAROCKS) which luv) ]] && \
		$(LUAROCKS) install luv || true



lint:
	@rm -rf $(LUA_LS)
	@mkdir -p $(LUA_LS)
	@lua-language-server --check $(PWD) --checklevel=$(LINT_LEVEL) --logpath=$(LUA_LS)
	@grep -q '^\[\]\s*$$' $(LUA_LS)/check.json || (cat $(LUA_LS)/check.json && exit 1)

clean:
	rm -rf $(DEPS)

.PHONY: all deps clean lint test test_nvim test_lua
