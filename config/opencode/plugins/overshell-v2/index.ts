// OverShell OpenCode V2 integration — installed by OverShell; safe to remove this directory.
import { Plugin } from "@opencode/plugin"

// Per-terminal environment and the visible session belong to the CLI, not to the shared
// service. The TUI entrypoint reports them; the server entrypoint enables auto-discovery.
export default Plugin.define({ id: "overshell.v2", setup() {} })
