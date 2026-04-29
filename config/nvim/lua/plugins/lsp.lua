local roslyn_filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props', 'csx', 'targets', 'tproj', 'slngen', 'fproj', 'razor' }
local roslyn_analysis_scope = "openFiles"
local roslyn_analyzers_enabled = true
local diagnostic_severity_index = 1

local diagnostic_severity_modes = {
	{ label = "all", severity = nil },
	{ label = "warnings and errors", severity = vim.diagnostic.severity.WARN },
	{ label = "errors only", severity = vim.diagnostic.severity.ERROR },
}

local function normalize_path(path)
	if not path or path == "" then
		return nil
	end

	return vim.fs.normalize(path)
end

local function common_prefix_len(left, right)
	left = (left or ""):lower()
	right = (right or ""):lower()

	local limit = math.min(#left, #right)
	local index = 1
	while index <= limit and left:sub(index, index) == right:sub(index, index) do
		index = index + 1
	end

	return index - 1
end

local function is_in_dir(path, dir)
	path = normalize_path(path)
	dir = normalize_path(dir)

	if not path or not dir then
		return false
	end

	path = path:lower()
	dir = dir:lower()

	return path == dir or path:sub(1, #dir + 1) == dir .. "/" or path:sub(1, #dir + 1) == dir .. "\\"
end

local function roslyn_target_score(target, current_dir, selected_solution)
	local target_dir = normalize_path(vim.fs.dirname(target)) or ""
	local score = common_prefix_len(current_dir, target_dir)

	if selected_solution and normalize_path(selected_solution) == normalize_path(target) then
		score = score + 1000000
	end

	if is_in_dir(current_dir, target_dir) then
		score = score + 10000 + #target_dir
	end

	if target:match("%.slnx$") then
		score = score + 1000
	elseif target:match("%.sln$") then
		score = score + 500
	elseif target:match("%.slnf$") then
		score = score + 250
	end

	return score
end

local function choose_roslyn_target(targets)
	local candidates = vim.deepcopy(targets)
	local current_file = vim.api.nvim_buf_get_name(0)
	local current_dir = normalize_path(vim.fs.dirname(current_file)) or vim.fn.getcwd()
	local selected_solution = vim.g.roslyn_nvim_selected_solution

	table.sort(candidates, function(left, right)
		local left_score = roslyn_target_score(left, current_dir, selected_solution)
		local right_score = roslyn_target_score(right, current_dir, selected_solution)

		if left_score ~= right_score then
			return left_score > right_score
		end

		return left < right
	end)

	return candidates[1]
end

local function roslyn_root_dir(bufnr, on_dir)
	local config = require("roslyn.config").get()
	if config.lock_target and vim.g.roslyn_nvim_selected_solution then
		on_dir(vim.fs.dirname(vim.g.roslyn_nvim_selected_solution))
		return
	end

	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	if buf_name:match("^roslyn%-source%-generated://") then
		local existing_client = vim.lsp.get_clients({ name = "roslyn" })[1]
		if existing_client and existing_client.config.root_dir then
			on_dir(existing_client.config.root_dir)
			return
		end
	end

	local root_dir = require("roslyn.sln.utils").root_dir(bufnr)
	if root_dir then
		on_dir(root_dir)
		return
	end

	local fallback = vim.fs.root(bufnr, {
		"global.json",
		"Directory.Build.props",
		"Directory.Build.targets",
		"Directory.Packages.props",
		".git",
	}) or normalize_path(vim.fs.dirname(buf_name)) or vim.fn.getcwd()

	on_dir(fallback)
end

local function select_roslyn_target_broad()
	local config = require("roslyn.config").get()
	local broad_search = config.broad_search
	config.broad_search = true
	local ok, err = pcall(vim.cmd, "Roslyn target")
	config.broad_search = broad_search

	if not ok then
		error(err)
	end
end

local function get_roslyn_capabilities()
	local capabilities = vim.lsp.protocol.make_client_capabilities()
	local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
	if ok then
		capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
	end

	capabilities.textDocument = capabilities.textDocument or {}
	capabilities.textDocument.diagnostic = capabilities.textDocument.diagnostic or {}
	capabilities.textDocument.diagnostic.dynamicRegistration = true

	capabilities.workspace = capabilities.workspace or {}
	capabilities.workspace.didChangeWatchedFiles = capabilities.workspace.didChangeWatchedFiles or {}
	capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = false

	return capabilities
end

local function get_roslyn_clients(buf)
	if buf then
		return vim.lsp.get_clients({ name = "roslyn", bufnr = buf })
	end

	return vim.lsp.get_clients({ name = "roslyn" })
end

local function update_roslyn_settings(mutator)
	local clients = get_roslyn_clients()
	if #clients == 0 then
		vim.notify("Roslyn is not running", vim.log.levels.WARN, { title = "Roslyn" })
		return
	end

	for _, client in ipairs(clients) do
		client.config.settings = client.config.settings or {}
		mutator(client.config.settings)
		client:notify("workspace/didChangeConfiguration", { settings = client.config.settings })
	end
end

local function toggle_roslyn_analysis_scope()
	roslyn_analysis_scope = roslyn_analysis_scope == "openFiles" and "fullSolution"
		or roslyn_analysis_scope == "fullSolution" and "none"
		or "openFiles"

	update_roslyn_settings(function(settings)
		settings["csharp|background_analysis"] = settings["csharp|background_analysis"] or {}
		settings["csharp|background_analysis"].dotnet_analyzer_diagnostics_scope = roslyn_analysis_scope
		settings["csharp|background_analysis"].dotnet_compiler_diagnostics_scope = roslyn_analysis_scope
	end)

	vim.notify("Background analysis: " .. roslyn_analysis_scope, vim.log.levels.INFO, { title = "Roslyn" })
end

local function toggle_roslyn_analyzers()
	roslyn_analyzers_enabled = not roslyn_analyzers_enabled

	update_roslyn_settings(function(settings)
		settings.roslyn = settings.roslyn or {}
		settings.roslyn.enable_roslyn_analysers = roslyn_analyzers_enabled
	end)

	local state = roslyn_analyzers_enabled and "enabled" or "disabled"
	vim.notify("Roslyn analyzers " .. state, vim.log.levels.INFO, { title = "Roslyn" })
end

local function cycle_diagnostic_severity()
	diagnostic_severity_index = diagnostic_severity_index % #diagnostic_severity_modes + 1
	local mode = diagnostic_severity_modes[diagnostic_severity_index]
	local severity_filter = mode.severity and { min = mode.severity } or nil

	vim.diagnostic.config({
		severity_sort = true,
		virtual_text = severity_filter and { severity = severity_filter } or true,
		signs = severity_filter and { severity = severity_filter } or true,
		underline = severity_filter and { severity = severity_filter } or true,
	})

	vim.notify("Diagnostics: " .. mode.label, vim.log.levels.INFO, { title = "Diagnostics" })
end

local function toggle_inlay_hints(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.lsp.inlay_hint then
		vim.notify("Inlay hints are not available", vim.log.levels.WARN, { title = "LSP" })
		return
	end

	local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = buf })
	vim.lsp.inlay_hint.enable(not enabled, { bufnr = buf })
end

local function refresh_codelens(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	pcall(vim.lsp.codelens.refresh, { bufnr = buf })
end

local function run_codelens(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(0)[1] - 1
	local line_lenses = vim.tbl_filter(function(lens)
		return lens.range and lens.range.start.line == line and lens.command
	end, vim.lsp.codelens.get(buf))

	if #line_lenses == 0 then
		vim.notify("No executable codelens found at current line", vim.log.levels.INFO, { title = "CodeLens" })
		return
	end

	local function run_lens(lens)
		if lens.command.command == "roslyn.client.peekReferences" then
			vim.lsp.buf.references()
			return
		end

		vim.lsp.codelens.run()
	end

	if #line_lenses == 1 then
		run_lens(line_lenses[1])
		return
	end

	vim.ui.select(line_lenses, {
		prompt = "Code lenses:",
		format_item = function(lens)
			return lens.command.title
		end,
	}, function(lens)
		if lens then
			run_lens(lens)
		end
	end)
end

local function refresh_roslyn_after_project_change(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if #get_roslyn_clients(buf) == 0 then
		return
	end

	refresh_codelens(buf)
	pcall(function()
		vim.lsp.diagnostic._refresh()
	end)

	vim.notify(
		"Project file saved. Roslyn should reload it; run .NET restore if package references changed.",
		vim.log.levels.INFO,
		{ title = "Roslyn" }
	)
end

local function show_roslyn_info()
	local clients = get_roslyn_clients()
	local selected_solution = vim.g.roslyn_nvim_selected_solution
	local lines = {
		"Roslyn clients: " .. tostring(#clients),
		"Target: " .. (selected_solution and vim.fn.fnamemodify(selected_solution, ":.") or "none"),
		"Background analysis: " .. roslyn_analysis_scope,
		"Analyzers: " .. (roslyn_analyzers_enabled and "enabled" or "disabled"),
	}

	for _, client in ipairs(clients) do
		lines[#lines + 1] = string.format(
			"Client %d root: %s",
			client.id,
			client.config.root_dir and vim.fn.fnamemodify(client.config.root_dir, ":.") or "none"
		)
	end

	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Roslyn" })
end

local function toggle_roslyn_semantic_tokens(buf, client)
	buf = buf or vim.api.nvim_get_current_buf()
	client = client or vim.lsp.get_clients({ name = "roslyn", bufnr = buf })[1]

	if not client then
		vim.notify("Roslyn is not attached to this buffer", vim.log.levels.WARN, { title = "Roslyn" })
		return
	end

	local semantic_tokens_provider = vim.b[buf].roslyn_semantic_tokens_provider
	if not semantic_tokens_provider then
		vim.notify("Roslyn semantic tokens are not available", vim.log.levels.WARN, { title = "Roslyn" })
		return
	end

	if vim.b[buf].roslyn_semantic_tokens_enabled then
		vim.lsp.semantic_tokens.stop(buf, client.id)
		client.server_capabilities.semanticTokensProvider = nil
		vim.b[buf].roslyn_semantic_tokens_enabled = false
		vim.notify("Roslyn semantic tokens disabled", vim.log.levels.INFO, { title = "Roslyn" })
		return
	end

	client.server_capabilities.semanticTokensProvider = semantic_tokens_provider
	vim.b[buf].roslyn_semantic_tokens_enabled = true
	vim.lsp.semantic_tokens.start(buf, client.id)
	vim.notify("Roslyn semantic tokens enabled", vim.log.levels.INFO, { title = "Roslyn" })
end

return {
	{
		"williamboman/mason.nvim",
		-- event = "VeryLazy",
		-- lazy = true,
		-- event = { "BufReadPre", "BufNewFile" },
		cmd = { "Mason", "MasonUpdate" },
		-- version = "1.11.0",
		config = function()
			require('mason').setup({
				    registries = {
					"github:mason-org/mason-registry",
					"github:Crashdummyy/mason-registry",
				},
			})
		end
	},
	{
		"williamboman/mason-lspconfig.nvim",
		event = "VeryLazy",
		-- version = "1.32.0",
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		opts = {
			auto_install = false,
		},
	},
	{
		"seblyng/roslyn.nvim",
		ft = roslyn_filetypes,
		cmd = "Roslyn",
		opts = {
			filewatching = "roslyn",
			broad_search = false,
			choose_target = choose_roslyn_target,
			lock_target = false,
		},
		config = function(_, opts)
			require("roslyn").setup(opts)

			vim.lsp.config("roslyn", {
				capabilities = get_roslyn_capabilities(),
				filetypes = roslyn_filetypes,
				root_dir = roslyn_root_dir,
				settings = {
					roslyn = {
						enable_roslyn_analysers = true,
						enable_import_completion = true,
						organize_imports_on_format = true,
						enable_decompilation_support = true,
					},
					["csharp|background_analysis"] = {
						dotnet_analyzer_diagnostics_scope = "openFiles",
						dotnet_compiler_diagnostics_scope = "openFiles",
					},
					["csharp|completion"] = {
						dotnet_show_completion_items_from_unimported_namespaces = true,
					},
					["csharp|inlay_hints"] = {
						csharp_enable_inlay_hints_for_implicit_object_creation = true,
						csharp_enable_inlay_hints_for_implicit_variable_types = true,
						csharp_enable_inlay_hints_for_lambda_parameter_types = true,
						csharp_enable_inlay_hints_for_types = true,
						dotnet_enable_inlay_hints_for_indexer_parameters = true,
						dotnet_enable_inlay_hints_for_literal_parameters = true,
						dotnet_enable_inlay_hints_for_object_creation_parameters = true,
						dotnet_enable_inlay_hints_for_other_parameters = true,
						dotnet_enable_inlay_hints_for_parameters = true,
						dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
						dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
						dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
					},
					["csharp|formatting"] = {
						dotnet_organize_imports_on_format = true,
					},
					["csharp|projects"] = {
						dotnet_enable_file_based_programs = true,
					},
					["csharp|symbol_search"] = {
						dotnet_search_reference_assemblies = true,
					},
					["csharp|code_lens"] = {
						dotnet_enable_references_code_lens = true,
						dotnet_enable_tests_code_lens = true,
					},
				}
			})
		end,
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPost", "BufNewFile" },
		-- event = "VeryLazy",
		-- lazy = true,
		dependencies = {
			"williamboman/mason.nvim",
			-- "williamboman/mason-lspconfig.nvim",
		},
		config = function()
			pcall(vim.api.nvim_create_user_command, "RoslynInfo", show_roslyn_info, {
				desc = "Show Roslyn target and client state",
			})

			vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "BufWritePost" }, {
				group = vim.api.nvim_create_augroup("moaid_roslyn_codelens", { clear = true }),
				pattern = "*.cs",
				callback = function(ev)
					if #get_roslyn_clients(ev.buf) > 0 then
						refresh_codelens(ev.buf)
					end
				end,
			})

			vim.api.nvim_create_autocmd("BufWritePost", {
				group = vim.api.nvim_create_augroup("moaid_roslyn_project_changed", { clear = true }),
				pattern = { "*.csproj", "*.props", "*.targets", "*.sln", "*.slnx", "*.slnf", "global.json", "Directory.Packages.props" },
				callback = function(ev)
					refresh_roslyn_after_project_change(ev.buf)
				end,
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("moaid_lsp_attach", { clear = true }),
				callback = function(ev)
					local buf = ev.buf
					local client = vim.lsp.get_client_by_id(ev.data.client_id)
					local bopts = function(desc)
						return { buffer = buf, desc = desc, silent = true }
					end

					if client and client.name == "roslyn" then
						if client:supports_method("textDocument/inlayHint") then
							pcall(vim.lsp.inlay_hint.enable, true, { bufnr = buf })
						end

						if client:supports_method("textDocument/codeLens") then
							refresh_codelens(buf)
						end

						vim.b[buf].roslyn_semantic_tokens_provider = client.server_capabilities.semanticTokensProvider
						vim.b[buf].roslyn_semantic_tokens_enabled = client.server_capabilities.semanticTokensProvider ~= nil
						vim.keymap.set('n', '<leader>lT', select_roslyn_target_broad, bopts("Select Roslyn Target"))
						vim.keymap.set('n', '<leader>lR', '<cmd>Roslyn restart<CR>', bopts("Restart Roslyn"))
						vim.keymap.set('n', '<leader>lI', show_roslyn_info, bopts("Show Roslyn Info"))
						vim.keymap.set('n', '<leader>lH', function() toggle_inlay_hints(buf) end, bopts("Toggle Inlay Hints"))
						vim.keymap.set('n', '<leader>lc', function() run_codelens(buf) end, bopts("Run CodeLens"))
						vim.keymap.set('n', '<leader>lC', function() refresh_codelens(buf) end, bopts("Refresh CodeLens"))
						vim.keymap.set('n', '<leader>lA', toggle_roslyn_analyzers, bopts("Toggle Roslyn Analyzers"))
						vim.keymap.set('n', '<leader>lB', toggle_roslyn_analysis_scope, bopts("Cycle Background Analysis"))
						vim.keymap.set('n', '<leader>lD', cycle_diagnostic_severity, bopts("Cycle Diagnostic Severity"))
						vim.keymap.set('n', '<leader>lS', function()
							toggle_roslyn_semantic_tokens(buf, client)
						end, bopts("Toggle Roslyn Semantic Tokens"))
						vim.api.nvim_buf_create_user_command(buf, "RoslynSemanticTokensToggle", function()
							toggle_roslyn_semantic_tokens(buf, client)
						end, { desc = "Toggle Roslyn semantic tokens" })
					end

					vim.keymap.set('n', '<leader>lff', function() vim.lsp.buf.format({ async = true }) end, bopts("Format document"))
					vim.keymap.set('n', '<leader>lr', vim.lsp.buf.rename, bopts("Rename Symbol"))
					vim.keymap.set({ 'n', 'i' }, '<f2>', vim.lsp.buf.rename, bopts("Rename Symbol"))
					vim.keymap.set({ 'n', 'i' }, '<f12>', vim.lsp.buf.definition, bopts("Go to Definition"))
					vim.keymap.set('n', '<leader>ld', vim.lsp.buf.definition, bopts("Go to Definition"))
					vim.keymap.set('n', '<leader>li', vim.lsp.buf.implementation, bopts("Go to Implementation"))
					vim.keymap.set('n', '<leader>lh', vim.lsp.buf.signature_help, bopts("Signature Help"))
					vim.keymap.set('n', '<leader>lsR', vim.lsp.buf.references, bopts("Go to References"))
					-- vim.keymap.set({ 'n' }, '<leader>lsD', ":Trouble document_diagnostics<CR>", bopts("Toggle Document Diagnostics"))
					vim.keymap.set('n', '<leader>lsD', ":Trouble diagnostics<CR>", bopts("Toggle Document Diagnostics"))
					vim.keymap.set('n', '<leader>lsI', ':Trouble lsp_implementations<CR>', bopts("Toggle LSP Implementations"))
					vim.keymap.set('n', '<leader>lsd', ":Trouble lsp_definitions<CR>", bopts("Toggle LSP Definitions"))
					vim.keymap.set('n', 'K', vim.lsp.buf.hover, bopts("LSP Hover"))
					vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bopts("Go to Definition"))
				end,
			})
		end
	},
	{
		'nvimtools/none-ls.nvim',
		-- event = { "BufReadPre", "BufNewFile" },
		-- lazy = true,
		enabled = false,
		event = { "BufReadPre", "BufNewFile" },
		-- event = "VeryLazy",
		config = function()
			local null_ls = require('null-ls')
			null_ls.setup({
				sources = {
					-- null_ls.builtins.formatting.stylua,
					-- null_ls.builtins.formatting.csharpier,
					-- null_ls.builtins.formatting.yamlfmt,
					-- null_ls.builtins.formatting.black,
					-- null_ls.builtins.formatting.isort,
				}
			})
		end
	},
	{
		"jay-babu/mason-null-ls.nvim",
		-- event = { "BufReadPre", "BufNewFile" },
		event = { 'VeryLazy' },
		enabled = false,
		dependencies = {
			"williamboman/mason.nvim",
			"nvimtools/none-ls.nvim",
			-- "neovim/nvim-lspconfig"
		},
		config = function()
			require('mason-null-ls').setup({
				automatic_setup = true
			})
		end,
	},
	{
		'https://git.sr.ht/~whynothugo/lsp_lines.nvim',
		-- event = "VeryLazy",
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			require('lsp_lines').setup()

			vim.diagnostic.config({
				virtual_lines = false,
				virtual_text = true,
			})

			local function toggleLines()
				local new_value = not vim.diagnostic.config().virtual_lines
				vim.diagnostic.config({ virtual_lines = new_value, virtual_text = not new_value })
				return new_value
			end

			vim.keymap.set('n', '<leader>lu', toggleLines, { desc = "Toggle Underline Diagnostics", silent = true })
		end
	},
}
