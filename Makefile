nvim ?= nvim
#
# Parallel test runner configuration:
#   PARALLEL=1 (default) -> dispatch one nvim per spec file via
#                           scripts/parallel_test.lua up to JOBS workers.
#   PARALLEL=0           -> legacy serial runner (one nvim for all files).
#   JOBS=N               -> parallelism factor (defaults to nproc).
#
PARALLEL ?= 1
JOBS    ?= $(shell nproc 2>/dev/null || echo 4)

#
# Run all tests or specic module tests
#
# Test both stable and nightly (assuming `nv` is linked to nightly):
# `make test nvim=nv` or `make test nvim="nvim nv"` (for both)
#
# Test specific module(s) with `make test glob=file`
# NOTE: glob is resolved using `vim.fn.globpath` so we can also run:
# `make test glob=f`
#
.PHONY: test
test:
	@if [ "$(PARALLEL)" = "1" ]; then \
		echo "PARALLEL test run ($(JOBS) workers)"; \
		runner_args="--jobs $(JOBS)"; \
		[ -n "$(glob)" ]   && runner_args="$$runner_args --glob $(glob)"; \
		[ -n "$(filter)" ] && runner_args="$$runner_args --filter $(filter)"; \
		failed=0; \
		for nvim_exec in $(nvim); do \
			$$nvim_exec --headless -l ./scripts/parallel_test.lua \
				$$runner_args "$$nvim_exec" || failed=$$((failed + 1)); \
		done; \
		if [ $$failed -ne 0 ]; then \
			echo "FAIL: $$failed nvim binary/ies reported failing specs"; \
			exit 1; \
		fi; \
	else \
		for nvim_exec in $(nvim); do \
			printf "\n======\n\n" ; \
			$$nvim_exec --version | head -n 1 && echo '' ; \
			$$nvim_exec --headless --noplugin -u ./scripts/minimal_init.lua \
				-l ./scripts/make_cli.lua ; \
		done; \
	fi

# clean / update all screenshots
.PHONY: screenshots
screenshots:
	make test update_screenshots=true

.PHONY: clean-screenshots
clean-screenshots:
	rm -rf tests/screenshots/*
	make test

#
# Download 'mini.nvim' and `nvim-web-devicons` into "deps" subfolder
# only used with the CI workflow, `minimal_init` will detect the deps
# in our lazy.nvim local config
#
.PHONY: deps
deps:
	make clean
	@mkdir -p deps
	make deps/fzf-lua
	git clone --depth=1 --single-branch https://github.com/nvim-mini/mini.nvim deps/mini.nvim
	git clone --depth=1 --single-branch https://github.com/nvim-tree/nvim-web-devicons deps/nvim-web-devicons
	git clone --depth=1 --single-branch https://github.com/hrsh7th/nvim-cmp deps/nvim-cmp
	git clone --depth=1 --single-branch https://github.com/mfussenegger/nvim-dap.git deps/nvim-dap


# Target to clone the repository and checkout the specific SHA.
# Pinning a fixed SHA ensures that fzf test screenshots remain
# deterministic — the screenshots include total file counts and
# file ordering, both of which would change if the working tree's
# current state (or different commits) were used instead.
SHA=abe5ecafebb4e24feb162384d5f492431036e791
.PHONY: deps/fzf-lua
deps/fzf-lua:
	@mkdir -p deps
	git clone .git $@
	(cd $@ && git checkout $(SHA))

# Download the emmylua binaries (emmylua_check + luafmt) from upstream
# if `gh` is available and they are not already on the system PATH.
# Binaries are extracted into .emmylua/.
EMMYLUA_DIR=.emmylua
EMMY_CHECK_BIN=$(EMMYLUA_DIR)/emmylua_check
LUA_FMT_BIN=$(EMMYLUA_DIR)/luafmt
# Pin the emmylua release tag to download. Set to an empty
# string (EMMYLUA_VERSION=) to fetch the latest release instead.
EMMYLUA_VERSION=0.23.1
# OS arch detection for emmylua_check. Falls back to linux-x64 on
# unknown platforms; override by passing EMMY_CHECK_ASSET=<asset
# filename> on the make command line.
EMMY_CHECK_ASSET=$(strip \
	$(if $(filter Darwin darwin,$(shell uname -s 2>/dev/null)),emmylua_check-darwin-x64.tar.gz,emmylua_check-linux-x64.tar.gz))
# OS arch detection for luafmt. Falls back to linux-x64 on unknown
# platforms; override by passing LUA_FMT_ASSET=<asset filename> on
# the make command line.
LUA_FMT_ASSET=$(strip \
	$(if $(filter Darwin darwin,$(shell uname -s 2>/dev/null)),luafmt-darwin-x64.tar.gz,luafmt-linux-x64.tar.gz))

.PHONY: deps/emmylua
deps/emmylua:
	@mkdir -p $(EMMYLUA_DIR) ; \
	if [ ! -x "$(EMMY_CHECK_BIN)" ] && ! command -v emmylua_check >/dev/null 2>&1; then \
		if ! command -v gh >/dev/null 2>&1; then \
			echo "gh is required to download emmylua_check" >&2 ; \
			exit 1 ; \
		fi ; \
		echo "Downloading emmylua_check $(if $(EMMYLUA_VERSION),v$(EMMYLUA_VERSION),latest) [$(EMMY_CHECK_ASSET)]..." ; \
		gh release download -R EmmyLuaLs/emmylua-analyzer-rust \
			$(if $(EMMYLUA_VERSION),"$(EMMYLUA_VERSION)") \
			-p "$(EMMY_CHECK_ASSET)" -D $(EMMYLUA_DIR) && \
		tar xzf "$(EMMYLUA_DIR)/$(EMMY_CHECK_ASSET)" -C $(EMMYLUA_DIR) && \
		rm -f "$(EMMYLUA_DIR)/$(EMMY_CHECK_ASSET)" ; \
	fi ; \
	if [ ! -x "$(LUA_FMT_BIN)" ] && ! command -v luafmt >/dev/null 2>&1; then \
		if ! command -v gh >/dev/null 2>&1; then \
			echo "gh is required to download luafmt" >&2 ; \
			exit 1 ; \
		fi ; \
		echo "Downloading luafmt $(if $(EMMYLUA_VERSION),v$(EMMYLUA_VERSION),latest) [$(LUA_FMT_ASSET)]..." ; \
		gh release download -R EmmyLuaLs/emmylua-analyzer-rust \
			$(if $(EMMYLUA_VERSION),"$(EMMYLUA_VERSION)") \
			-p "$(LUA_FMT_ASSET)" -D $(EMMYLUA_DIR) && \
		tar xzf "$(EMMYLUA_DIR)/$(LUA_FMT_ASSET)" -C $(EMMYLUA_DIR) && \
		rm -f "$(EMMYLUA_DIR)/$(LUA_FMT_ASSET)" ; \
	fi

.PHONY: lint
lint:
	VIMRUNTIME="$$(nvim --clean --headless +'echo $$VIMRUNTIME' +q 2>&1)" \
		lua-language-server --configpath=../.luarc.jsonc --check=.

.PHONY: emmylua-check
emmylua-check: | deps/emmylua
	@if [ -x "$(EMMY_CHECK_BIN)" ]; then \
		EMMY="$(EMMY_CHECK_BIN)" ; \
	else \
		EMMY="emmylua_check" ; \
	fi ; \
	VIMRUNTIME="$$(nvim --clean --headless +'echo $$VIMRUNTIME' +q 2>&1)" \
		$$EMMY . --ignore 'deps/**/*' --warnings-as-errors

.PHONY: fmt fmtcheck
fmt: | deps/emmylua
	@if [ -x "$(LUA_FMT_BIN)" ]; then \
		FMT="$(LUA_FMT_BIN)" ; \
	else \
		FMT="luafmt" ; \
	fi ; \
	$$FMT --config .luafmt.toml --write --recursive ./lua ./tests

fmtcheck: | deps/emmylua
	@if [ -x "$(LUA_FMT_BIN)" ]; then \
		FMT="$(LUA_FMT_BIN)" ; \
	else \
		FMT="luafmt" ; \
	fi ; \
	$$FMT --config .luafmt.toml --check --recursive ./lua ./tests

gen:
	nvim --clean -l lua/fzf-lua/init.lua

# clean up
.PHONY: clean
clean:
	rm -rf deps
