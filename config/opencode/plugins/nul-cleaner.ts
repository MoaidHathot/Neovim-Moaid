import type { Plugin } from "@opencode-ai/plugin"
import path from "node:path"
import fs from "node:fs/promises"

const TOOLS = new Set(["write", "edit", "bash", "patch", "multiedit"])

export const NulCleanerPlugin: Plugin = async ({ directory, $ }) => {
  const remove = async (dir: string) => {
    const target = path.join(dir, "nul")
    const literal = "\\\\?\\" + path.resolve(target)
    const stat = await fs.stat(literal).catch(() => null)
    if (!stat) return
    await fs.unlink(literal).catch(async () => {
      await $`cmd /c del /f /q ${literal} >nul 2>nul`.quiet().nothrow()
    })
  }

  return {
    "tool.execute.after": async (input) => {
      if (!TOOLS.has(input.tool)) return
      await remove(directory)
    },
    event: async ({ event }) => {
      if (event.type !== "session.status") return
      const props = event.properties as { status: { type: string } }
      if (props.status.type === "idle") await remove(directory)
    },
  }
}
