// OpenCode 2 server plugin (ported from the V1 Hooks-object form).
//
// Strips CRLF from files the agent writes or edits so Windows never leaves ^M in the
// repo. V2 tool names: `write`, `edit`, `patch` (V1 `apply_patch`); the path argument
// is `path` (V1 `filePath`) — `pick` accepts both so the hook survives either shape.
import { Plugin } from "@opencode/plugin"
import path from "node:path"
import fs from "node:fs/promises"

const TOOLS = new Set(["write", "edit", "patch", "multiedit", "apply_patch"])

const SKIP_EXT = new Set([
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp",
  ".pdf", ".zip", ".gz", ".tar", ".7z", ".exe", ".dll",
  ".so", ".dylib", ".wasm", ".bin", ".lock",
])

const SKIP_NAMES = new Set([
  "package-lock.json",
  "bun.lock",
  "bun.lockb",
  "yarn.lock",
  "pnpm-lock.yaml",
])

const pick = (args: unknown): string | undefined => {
  const a = args as Record<string, unknown> | undefined
  const value = a?.path ?? a?.filePath ?? a?.file_path ?? a?.file
  return typeof value === "string" ? value : undefined
}

export default Plugin.define({
  id: "moaid.crlf-stripper",
  async setup(ctx) {
    const directory = ctx.location.directory

    const strip = async (file: string) => {
      if (!file) return
      const abs = path.isAbsolute(file) ? file : path.resolve(directory, file)
      const name = path.basename(abs).toLowerCase()
      if (SKIP_NAMES.has(name)) return
      if (SKIP_EXT.has(path.extname(abs).toLowerCase())) return
      const stat = await fs.stat(abs).catch(() => null)
      if (!stat?.isFile()) return
      const buf = await fs.readFile(abs).catch(() => null)
      if (!buf) return
      if (!buf.includes(0x0d)) return
      const cleaned = Buffer.from(buf.toString("utf8").replace(/\r\n/g, "\n").replace(/\r/g, "\n"), "utf8")
      if (cleaned.equals(buf)) return
      await fs.writeFile(abs, cleaned)
    }

    await ctx.tool.hook("execute.after", async (event) => {
      if (!TOOLS.has(event.tool)) return
      const file = pick(event.input)
      if (file) await strip(file)
    })
  },
})
