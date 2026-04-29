import type { Plugin } from "@opencode-ai/plugin"
import path from "node:path"
import fs from "node:fs/promises"

const TOOLS = new Set(["write", "edit", "patch", "multiedit"])

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

const pick = (args: any): string | undefined =>
  args?.filePath ?? args?.file_path ?? args?.path ?? args?.file

export const CrlfStripperPlugin: Plugin = async ({ directory }) => {
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

  return {
    "tool.execute.after": async (input) => {
      if (!TOOLS.has(input.tool)) return
      const file = pick(input.args)
      if (file) await strip(file)
    },
  }
}
