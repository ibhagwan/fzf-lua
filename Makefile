NVIM_EXEC ?= nvim

# Run all test files
# assuming `nv` is linked to nightly appimage
# run with `make NVIM_EXEC="nvim nv" test`
# to test on both stable and nightly
.PHONY: test
test:
	for nvim_exec in $(NVIM_EXEC); do \
		printf "\n======\n\n" ; \
		$$nvim_exec --version | head -n 1 && echo '' ; \
		$$nvim_exec --headless --noplugin -u ./scripts/minimal_init.lua \
			-c "lua MiniTest.run()" ; \
	done

# Run test from file at `$FILE` environment variable
# run with `make FILE=tests/init_spec.lua test-file`
.PHONY: test-file
test-file:
	for nvim_exec in $(NVIM_EXEC); do \
		printf "\n======\n\n" ; \
		$$nvim_exec --version | head -n 1 && echo '' ; \
		$$nvim_exec --headless --noplugin -u ./scripts/minimal_init.lua \
			-c "lua MiniTest.run_file('$(FILE)')" ; \
	done
