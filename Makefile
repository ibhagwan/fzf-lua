nvim ?= nvim

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
	for nvim_exec in $(nvim); do \
		printf "\n======\n\n" ; \
		$$nvim_exec --version | head -n 1 && echo '' ; \
		$$nvim_exec --headless --noplugin -u ./scripts/minimal_init.lua \
			-l ./scripts/make_cli.lua ; \
	done

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

# Download the emmylua_check linter from upstream if `gh` is
# available and `emmylua_check` is not already on the system PATH.
# The binary is extracted into deps/emmylua_check/emmylua_check.
EMMY_CHECK_DIR=.emmylua
EMMY_CHECK_BIN=$(EMMY_CHECK_DIR)/emmylua_check
# Pin the emmylua_check release tag to download. Set to an empty
# string (EMMY_CHECK_VERSION=) to fetch the latest release instead.
EMMY_CHECK_VERSION=0.23.1
# OS arch detection. Falls back to linux-x64 on unknown platforms;
# override by passing EMMY_CHECK_ASSET=<asset filename> on the make
# command line.
EMMY_CHECK_ASSET=$(strip \
	$(if $(filter Darwin darwin,$(shell uname -s 2>/dev/null)),emmylua_check-darwin-x64.tar.gz,emmylua_check-linux-x64.tar.gz))
.PHONY: deps/emmylua_check
deps/emmylua_check:
	@if [ -x "$(EMMY_CHECK_BIN)" ] || command -v emmylua_check >/dev/null 2>&1; then \
		: ; \
	elif command -v gh >/dev/null 2>&1; then \
		mkdir -p $(EMMY_CHECK_DIR) ; \
		echo "Downloading emmylua_check $(if $(EMMY_CHECK_VERSION),v$(EMMY_CHECK_VERSION),latest) [$(EMMY_CHECK_ASSET)]..." ; \
		gh release download -R EmmyLuaLs/emmylua-analyzer-rust \
			$(if $(EMMY_CHECK_VERSION),"$(EMMY_CHECK_VERSION)") \
			-p "$(EMMY_CHECK_ASSET)" -D $(EMMY_CHECK_DIR) && \
		tar xzf "$(EMMY_CHECK_DIR)/$(EMMY_CHECK_ASSET)" -C $(EMMY_CHECK_DIR) && \
		rm -f "$(EMMY_CHECK_DIR)/$(EMMY_CHECK_ASSET)" ; \
	else \
		echo "gh is required to download emmylua_check" >&2 ; \
		exit 1 ; \
	fi

.PHONY: lint
lint:
	VIMRUNTIME="$$(nvim --clean --headless +'echo $$VIMRUNTIME' +q 2>&1)" \
		lua-language-server --configpath=../.luarc.jsonc --check=.

.PHONY: emmylua-check
emmylua-check: | deps/emmylua_check
	@if [ -x "$(EMMY_CHECK_BIN)" ]; then \
		EMMY="$(EMMY_CHECK_BIN)" ; \
	else \
		EMMY="emmylua_check" ; \
	fi ; \
	VIMRUNTIME="$$(nvim --clean --headless +'echo $$VIMRUNTIME' +q 2>&1)" \
		$$EMMY . --ignore 'deps/**/*' --warnings-as-errors

gen:
	nvim --clean -l lua/fzf-lua/init.lua

# clean up
.PHONY: clean
clean:
	rm -rf deps
