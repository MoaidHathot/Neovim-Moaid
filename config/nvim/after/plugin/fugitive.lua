vim.keymap.set("n", "<leader>zs", vim.cmd.Git, { desc = "Git Status" })
vim.keymap.set("n", "<leader>za", "<cmd>:Git add .<CR>", { desc = "Git Add All" })
vim.keymap.set("n", "<leader>zp", "<cmd>:Git push<CR>", { desc = "Git Push" })
-- vim.keymap.set("n", "<leader>zc", "<cmd>:Git commit -m", { desc = "Git Add All" })
