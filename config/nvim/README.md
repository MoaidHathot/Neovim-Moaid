# Neovim configuration

This configuration uses Neovim 0.11+ and lazy.nvim. On a new machine, run
`:Lazy install` to install the plugins in `lazy-lock.json`.

## PowerReview on multiple machines

PowerReview is enabled automatically when its checkout is next to this repository:

```text
<any directory>/
  Neovim-Moaid/config/nvim/
  PowerReview/
```

The drive letter and parent directory can differ between machines. Symlinked
Neovim config directories are resolved before looking for the sibling checkout.

For a checkout elsewhere, set `POWER_REVIEW_DIR` before starting Neovim:

```powershell
# PowerShell: current session
$env:POWER_REVIEW_DIR = 'D:\Projects\PowerReview'
# Persist for future terminals on this Windows machine
[Environment]::SetEnvironmentVariable('POWER_REVIEW_DIR', 'D:\Projects\PowerReview', 'User')
```

```sh
# Linux/macOS: add to your shell profile
export POWER_REVIEW_DIR="$HOME/projects/PowerReview"
```

If the checkout is missing or the override is invalid, PowerReview and its
Neo-tree/Telescope integrations are skipped. Normal editing and file search
continue to work. An explicit override takes precedence over the sibling path.

The CLI still uses `dnx --yes PowerReview --`, so it requires .NET 10 and a NuGet
source containing PowerReview. It uses each machine's NuGet configuration.
CLI settings live in `$XDG_CONFIG_HOME/PowerReview/powerreview.json`.

After restarting Neovim, use `:PowerReview`, `<leader>pr`, or
`:Telescope power_review sessions`. Run `:checkhealth power-review` after loading
the plugin to check the CLI and authentication.

## Search

- `<leader>sf`: file names, with optional filters (e.g. `config  *.lua`).
- `<leader>sg`: file contents, with optional filters (e.g. `setup  *.lua`).
- `<leader>sG`: the same content search, including hidden and ignored files.
- `<leader>sF`: all file names, including hidden and ignored files.

## Regression checks

After installing plugins, run from the repository root:

```sh
nvim -l config/nvim/tests/run.lua
```

The checks launch headless Neovim with temporary config copies and exercise
startup, search, completion, terminals, and PowerReview integrations. When a
PowerReview checkout is available, they also test relocated checkouts, different
plugin load orders, and the missing-checkout fallback. They use local fixtures
and do not open a remote PR.
