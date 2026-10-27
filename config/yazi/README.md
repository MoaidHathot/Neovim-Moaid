# Yazi

Configuration for Yazi 26.9.1. `YAZI_CONFIG_HOME` points to this directory via
`configurations/configuration.dev.dsc.yaml`.

## Maintenance

Keep only overrides in `yazi.toml` and use `prepend_keymap` for keybindings.
Yazi supplies its own openers, MIME fetchers, previewers, task settings, icons,
and default light/dark themes. This allows upgrades to bring in their matching
defaults automatically. Schema URLs belong in `#:schema` comments; a top-level
`"$schema"` setting prevents this release from loading the configuration.

The dark flavor is selected in `theme.toml`. Both bundled flavors use the
current theme sections; light mode uses Yazi's built-in theme. Code previews
use Yazi's ANSI syntax theme unless a flavor supplies its own `tmtheme.xml`.

## Shortcuts

The current built-in keybindings apply, with these overrides:

| Key | Action |
| --- | --- |
| `z` | Jump via zoxide |
| `Z` | Jump via fzf |
| `t` | Create a tab in the current directory |
| `T` | Rename the current tab |

Single-key `t` takes the place of the built-in `t t` / `t r` tab chords.
Press `F1` or `~` in Yazi to see the effective bindings.

## Windows dependencies

`YAZI_FILE_ONE` must point to Git for Windows' `usr\bin\file.exe`; the DSC setup
configures `C:\Program Files\Git\usr\bin\file.exe`. Adjust it for a custom Git
installation. Restart the terminal after changing environment variables.

An existing Zakira.Replay installation can supply FFmpeg and ffprobe from
`%LOCALAPPDATA%\Zakira.Replay\portable`. Add that directory to the user PATH
when both executables are present.

Optional tools enable additional previews: 7-Zip for archives, FFmpeg for video,
Poppler (`pdftoppm`) for PDF, resvg for SVG, ImageMagick for fonts and additional
image formats, and jq for JSON. File search uses fd/ripgrep; directory jumping
uses fzf/zoxide. See the [installation guide](https://yazi-rs.github.io/docs/installation#windows)
for installation commands.
