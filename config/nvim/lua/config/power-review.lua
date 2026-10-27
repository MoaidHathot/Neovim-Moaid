local M = {}

function M.find_dir()
	-- An explicit per-machine path takes precedence over the sibling checkout.
	local dir = vim.env.POWER_REVIEW_DIR
	if not dir or dir == "" then
		-- Resolve symlinked configs too, e.g. ~/.config/nvim -> this repository.
		local config_dir = vim.uv.fs_realpath(vim.fn.stdpath("config")) or vim.fn.stdpath("config")
		dir = vim.fs.joinpath(config_dir, "..", "..", "..", "PowerReview")
	end

	dir = vim.fs.normalize(vim.fn.expand(dir))
	if vim.fn.filereadable(vim.fs.joinpath(dir, "lua", "power-review", "init.lua")) == 1
		and vim.fn.filereadable(vim.fs.joinpath(dir, "plugin", "power-review.lua")) == 1
	then
		return dir
	end
end

M.dir = M.find_dir()

return M
