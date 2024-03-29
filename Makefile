PLENARY-DIR=../plenary.nvim
PLENARY-REPO=https://github.com/nvim-lua/plenary.nvim.git

.PHONY: test
test:
	nvim --headless --noplugin -u tests/minimal_init.lua -c "lua require('plenary.test_harness').test_directory('tests/', { minimal_init = 'tests/minimal_init.lua', sequential = true, timeout = 120000 })"

# run with `make FILE=tests/path_spec.lua test-file`
.PHONY: test-file
test-file:
	nvim --headless --noplugin -u tests/minimal_init.lua -c "lua require('plenary.busted').run(vim.loop.cwd()..'/'..[[$(FILE)]])"


.PHONY: plenary
plenary:
	@if [ ! -d $(PLENARY-DIR) ] ;\
	then \
	  echo "Cloning plenary.nvim..."; \
	  git clone $(PLENARY-REPO) $(PLENARY-DIR); \
	else \
	  echo "Updating plenary.nvim..."; \
	  git -C $(PLENARY-DIR) pull --rebase; \
	fi
