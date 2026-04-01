# Latest Neovim Configuration Changes

## Overview

This update adds new productivity features, fixes minor config issues, and improves keybinding organization across the Neovim configuration.

---

## 1. Diagnostic Navigation

Jump between diagnostics (errors, warnings, hints) without opening Trouble or visually scanning.

| Key | Action |
|-----|--------|
| `[d` | Jump to previous diagnostic |
| `]d` | Jump to next diagnostic |

---

## 2. Which-Key Group Labels

The Which-Key popup now shows organized group headers instead of flat key descriptions. Pressing `<leader>` displays categorized groups:

| Prefix | Group |
|--------|-------|
| `<leader>b` | Buffers |
| `<leader>f` | Files |
| `<leader>s` | Search |
| `<leader>l` | LSP |
| `<leader>lf` | Format |
| `<leader>ls` | Symbols |
| `<leader>g` | Git |
| `<leader>m` | Misc |
| `<leader>n` | .NET |
| `<leader>nr` | .NET References |
| `<leader>np` | .NET Packages |
| `<leader>P` | Preview |
| `<leader>p` | PowerReview |
| `<leader>a` | AI |
| `<leader>d` | Debug/Run |
| `<leader>h` | Highlight |
| `<leader>t` | Tree |

---

## 3. Code Folding (nvim-ufo)

Treesitter and LSP-powered code folding replaces the previous unused manual fold mode. Files open fully unfolded by default.

| Key | Action |
|-----|--------|
| `zR` | Open all folds |
| `zM` | Close all folds |
| `zr` | Open folds (except kinds) |
| `zm` | Close folds (by level) |
| `zK` | Peek inside a fold (falls back to LSP hover if no fold) |

**Fold providers:**
- C#, VB, Lua files: LSP provider with indent fallback
- All other filetypes: Treesitter provider with indent fallback

> Run `:Lazy sync` on first launch to install `nvim-ufo` and `promise-async`.

---

## 4. Buffer-Local LSP Keymaps

LSP keymaps (`K`, `gd`, `<leader>l*`, `<F2>`, `<F12>`) now only activate when an LSP server is attached to the buffer. They no longer exist in plain text files or buffers without an active language server.

**Affected keymaps (unchanged bindings, now buffer-local):**

| Key | Action |
|-----|--------|
| `K` | LSP Hover |
| `gd` | Go to Definition |
| `<F2>` | Rename Symbol |
| `<F12>` | Go to Definition |
| `<leader>ld` | Go to Definition |
| `<leader>li` | Go to Implementation |
| `<leader>lh` | Signature Help |
| `<leader>lr` | Rename Symbol |
| `<leader>lff` | Format Document |
| `<leader>lsR` | Go to References |
| `<leader>lsD` | Toggle Document Diagnostics (Trouble) |
| `<leader>lsI` | Toggle LSP Implementations (Trouble) |
| `<leader>lsd` | Toggle LSP Definitions (Trouble) |

---

## 5. Treesitter Navigation (Previous Direction)

Treesitter textobject motions are now bidirectional. Previously only forward (`]`) motions existed.

| Key | Action |
|-----|--------|
| `]m` / `[m` | Next / previous function start |
| `]c` / `[c` | Next / previous class start |
| `]M` / `[M` | Next / previous function end |
| `]C` / `[C` | Next / previous class end |

---

## 6. Visual Mode Line Movement

`Alt+Down` / `Alt+Up` now works in visual mode to move selected blocks of lines, not just single lines in normal mode.

| Key | Mode | Action |
|-----|------|--------|
| `<M-Down>` | Normal | Move current line down |
| `<M-Up>` | Normal | Move current line up |
| `<M-Down>` | Visual | Move selected lines down |
| `<M-Up>` | Visual | Move selected lines up |

---

## 7. Copilot Suggest Remap

Copilot's "suggest" action was remapped from `<C-c>` to `<C-a>` to resolve a conflict with the `<C-c>` -> `<Esc>` mapping in insert mode.

| Key | Action |
|-----|--------|
| `<C-a>` | Trigger Copilot suggestion |
| `<C-l>` | Next Copilot suggestion |
| `<C-h>` | Previous Copilot suggestion |
| `<C-d>` | Dismiss Copilot suggestion |
| `<C-f>` | Accept word |
| `<C-g>` | Accept line |

---

## Bug Fixes

- **Treesitter indent duplicate**: Removed a misplaced `indent = { enable = true }` from inside the `highlight` block in `treesitter.lua`. The correct top-level `indent` config was already present.
- **LSP desc typo**: Fixed `<leader>lsI` description from "Toggle LSP References" to "Toggle LSP Implementations".
- **Mixed line endings**: Normalized `treesitter.lua` from mixed CRLF/LF to consistent line endings.

---

## Files Changed

| File | Change |
|------|--------|
| `lua/config/keymap.lua` | Diagnostic navigation, visual mode line movement |
| `lua/config/options.lua` | Fold settings for nvim-ufo |
| `lua/plugins/lsp.lua` | LspAttach buffer-local keymaps |
| `lua/plugins/treesitter.lua` | Indent fix, previous-direction motions |
| `lua/plugins/cmp.lua` | Copilot suggest remap |
| `lua/plugins/which-key.lua` | Group labels |
| `lua/plugins/ufo.lua` | **New** - nvim-ufo plugin config |
