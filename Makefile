.PHONY: test format lint

test:
	nvim --headless -u tests/minimal_init.lua -c "lua require('plenary.test_harness').test_directory('tests/', { minimal_init = 'tests/minimal_init.lua' })"

format:
	stylua lua/ tests/

lint:
	luacheck lua/ tests/
