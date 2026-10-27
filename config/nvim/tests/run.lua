-- Run with: nvim -l config/nvim/tests/run.lua
local config_dir = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local temp = vim.fn.tempname()

local function copy_dir(source, destination)
	vim.fn.mkdir(destination, "p")
	for name, kind in vim.fs.dir(source) do
		if kind == "directory" and name ~= "tests" then
			copy_dir(vim.fs.joinpath(source, name), vim.fs.joinpath(destination, name))
		elseif kind == "file" then
			assert(vim.uv.fs_copyfile(vim.fs.joinpath(source, name), vim.fs.joinpath(destination, name)))
		end
	end
end

local function machine(name)
	local root = vim.fs.joinpath(temp, name)
	local config = vim.fs.joinpath(root, "Neovim-Moaid", "config")
	copy_dir(config_dir, vim.fs.joinpath(config, "nvim"))
	return root, config
end

local work = vim.fs.joinpath(temp, "workspace with spaces")
local function run_case(label, config, override, expected, first, full)
	if arg[1] and not label:find(arg[1], 1, true) then return end
	local result = vim.system({
		vim.v.progpath, "--headless", "-i", "NONE", "-n",
		"--cmd", "lua dofile(vim.env.NVIM_TEST_SCRIPT)",
	}, {
		cwd = work,
		text = true,
		timeout = 60000,
		env = {
			XDG_CONFIG_HOME = config,
			NVIM_APPNAME = "nvim",
			POWER_REVIEW_DIR = override or "",
			NVIM_TEST_SCRIPT = vim.fs.joinpath(config_dir, "tests", "smoke.lua"),
			NVIM_TEST_EXPECTED_PR = expected or "",
			NVIM_TEST_FIRST = first or "telescope",
			NVIM_TEST_FULL = full and "1" or "0",
		},
	}):wait()
	assert(result.code == 0, label .. "\n" .. (result.stdout or "") .. (result.stderr or ""))
	if full and vim.fn.has("win32") == 1 then
		-- Windows headless terminals write to the process output, not a screen grid.
		assert(((result.stdout or "") .. (result.stderr or "")):find("CONFIG_TERMINAL_OK", 1, true), "Missing shell output")
	end
	io.stdout:write("PASS: " .. label .. "\n")
end

local link
local ok, err = xpcall(function()
	vim.fn.mkdir(work, "p")
	vim.fn.writefile({ "CONFIG_SMOKE_TOKEN" }, vim.fs.joinpath(work, "visible file.txt"))
	vim.fn.writefile({ "CONFIG_SMOKE_TOKEN" }, vim.fs.joinpath(work, ".hidden.txt"))
	vim.fn.writefile({ "CONFIG_SMOKE_TOKEN" }, vim.fs.joinpath(work, "ignored.txt"))
	vim.fn.writefile({ "ignored.txt" }, vim.fs.joinpath(work, ".ignore"))

	local _, missing_config = machine("without checkout")
	run_case("missing checkout: startup, search, completion, terminal", missing_config, nil, nil, "telescope", true)

	local stdpath = vim.fn.stdpath
	vim.fn.stdpath = function(what) return what == "config" and config_dir or stdpath(what) end
	local checkout = dofile(vim.fs.joinpath(config_dir, "lua", "config", "power-review.lua")).dir
	vim.fn.stdpath = stdpath
	if not checkout then
		io.stdout:write("SKIP: present-checkout tests (set POWER_REVIEW_DIR to enable)\n")
		return
	end

	local root, config = machine("with sibling")
	local sibling = vim.fs.joinpath(root, "PowerReview")
	for _, directory in ipairs({ "lua", "plugin" }) do
		copy_dir(vim.fs.joinpath(checkout, directory), vim.fs.joinpath(sibling, directory))
	end
	for _, first in ipairs({ "neo-tree", "telescope", "PowerReview" }) do
		run_case("sibling checkout, " .. first .. " loaded first", config, nil, sibling, first)
	end

	local relocated = vim.fs.joinpath(temp, "another location", "PR checkout")
	copy_dir(sibling, relocated)
	run_case("explicit override with spaces", missing_config, relocated, relocated)
	run_case("invalid override disables even an available sibling", config, work)

	local linked_config = vim.fs.joinpath(temp, "linked config")
	vim.fn.mkdir(linked_config, "p")
	link = vim.fs.joinpath(linked_config, "nvim")
	local linked = vim.uv.fs_symlink(vim.fs.joinpath(config, "nvim"), link, {
		dir = true,
		junction = vim.fn.has("win32") == 1,
	})
	if linked then
		run_case("symlinked config resolves the real sibling", linked_config, nil, sibling)
	else
		link = nil
		io.stdout:write("SKIP: symlink test (directory symlinks unavailable)\n")
	end
end, debug.traceback)

if link then
	if vim.fn.has("win32") == 1 then
		assert(vim.uv.fs_rmdir(link))
	else
		assert(vim.uv.fs_unlink(link))
	end
end
vim.fn.delete(temp, "rf")
assert(ok, err)
