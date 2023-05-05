local navic = require('nvim-navic')

local on_attach = function(client, bufnr)
    if client.server_capabilities.documentSymbolProvider then
        navic.attach(client, bufnr)
    end
end

require("lspconfig").clangd.setup {
    on_attach = on_attach,
	lsp = {
		auto_attach = true,
	}
}
