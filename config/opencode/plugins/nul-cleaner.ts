// OpenCode 2 server plugin (ported from the V1 Hooks-object form).
//
// Windows creates a literal file named `nul` when a command redirects to `nul` from a
// non-cmd shell. Remove it after shell/edit tools and whenever the session goes idle.
// V2 renamed the `bash` tool to `shell`; both names are kept so the hook survives a
// V1 session that was migrated mid-flight.
import { Plugin } from "@opencode/plugin"
import path from "node:path"
import fs from "node:fs/promises"
import { execFile } from "node:child_process"

const TOOLS = new Set(["write", "edit", "shell", "bash", "patch", "multiedit", "apply_patch"])

const samePath = (a: string | undefined, b: string | undefined) =>
  !!a && !!b && a.replace(/[\\/]+$/, "").toLowerCase() === b.replace(/[\\/]+$/, "").toLowerCase()

const del = (literal: string) =>
  new Promise<void>((resolve) => {
    execFile("cmd", ["/c", "del", "/f", "/q", literal], { windowsHide: true }, () => resolve())
  })

export default Plugin.define({
  id: "moaid.nul-cleaner",
  async setup(ctx) {
    const remove = async (dir: string | undefined) => {
      if (!dir) return
      const target = path.join(dir, "nul")
      const literal = "\\\\?\\" + path.resolve(target)
      const stat = await fs.stat(literal).catch(() => null)
      if (!stat) return
      await fs.unlink(literal).catch(() => del(literal))
    }

    await ctx.tool.hook("execute.after", async (event) => {
      if (!TOOLS.has(event.tool)) return
      await remove(ctx.location.directory)
    })

    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          if (event.type !== "session.status") continue
          if (event.data.status.type !== "idle") continue
          // Events are server-wide and plugins are instantiated per location; only act
          // on idle events raised at this instance's directory.
          const at = event.location?.directory
          if (at && !samePath(at, ctx.location.directory)) continue
          await remove(ctx.location.directory)
        }
      } catch (error) {
        if (!controller.signal.aborted) console.error("[nul-cleaner] event stream ended:", error)
      }
    })()

    return () => controller.abort()
  },
})
