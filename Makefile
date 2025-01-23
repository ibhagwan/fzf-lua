NVIM_EXEC ?= nvim

#
# Run all tests or specic module tests
#
# Test both stable and nightly (assuming `nv` is linked to nightly):
# `make NVIM_EXEC="nvim nv" test`
#
# Test specific module(s) with `make test glob=file`
# NOTE: glob is resolved using `vim.fn.globpath` so we can also run:
# `make test glob=f
#
.PHONY: test
test:
	for nvim_exec in $(NVIM_EXEC); do \
		printf "\n======\n\n" ; \
		$$nvim_exec --version | head -n 1 && echo '' ; \
		$$nvim_exec --headless --noplugin -u ./scripts/minimal_init.lua \
			-l ./scripts/make_cli.lua ; \
	done

#
# Download 'mini.nvim' and `nvim-web-devicons` into "deps" subfolder
# only used with the CI workflow, `minimal_init` will detect the deps
# in our lazy.nvim local config
#
.PHONY: deps
deps:
	make clean
	@mkdir -p deps
	git clone --depth=1 --single-branch https://github.com/echasnovski/mini.nvim deps/mini.nvim
	git clone --depth=1 --single-branch https://github.com/nvim-tree/nvim-web-devicons \
		deps/nvim-web-devicons

# clean up
.PHONY: clean
clean:
	rm -rf deps
