# Run all test files
.PHONY: test
test:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run test from file at `$FILE` environment variable
# run with `make FILE=tests/init_spec.lua test-file`
.PHONY: test-file
test-file:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"
