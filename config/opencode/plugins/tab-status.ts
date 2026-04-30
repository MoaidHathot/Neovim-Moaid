import type { Plugin } from "@opencode-ai/plugin"
import { basename } from "node:path"

// Emits Windows Terminal OSC sequences so each tab visually reflects the
// state of its OpenCode session: working / waiting on user / error / idle.
//
// OSC 0       → tab title
// OSC 9;4;s;p → tab progress bar  (state s, percent p)
//   s=0 clear, s=1 green, s=2 red, s=3 pulsing yellow, s=4 solid yellow
export const TabStatusPlugin: Plugin = async ({ directory }) => {
  const label = basename(directory)
  const children = new Set<string>()
  const pending = new Set<string>() // sessions awaiting permission
  let busy = false

  const esc = "\x1b"
  const emit = (title: string, state: number, pct = 0) => {
    process.stdout.write(`${esc}]0;${title}${esc}\\${esc}]9;4;${state};${pct}${esc}\\`)
  }

  // Tab titles render in Windows Terminal's UI font (Segoe UI Variable),
  // not the terminal font — Nerd Font glyphs tofu there. Use emoji instead.
  const ICON = {
    idle: "\u{1F7E2}", // green circle
    busy: "\u{2699}\u{FE0F}", // gear
    ask:  "\u{2753}", // red question mark
    err:  "\u{274C}", // cross mark
  }

  const render = () => {
    if (pending.size) return emit(`${ICON.ask} ${label}`, 4)
    if (busy) return emit(`${ICON.busy} ${label}`, 3)
    return emit(`${ICON.idle} ${label}`, 0)
  }

  const reset = () => {
    pending.clear()
    busy = false
    emit(`${ICON.idle} ${label}`, 0)
  }

  render()
  process.on("exit", reset)
  process.on("SIGINT", () => { reset(); process.exit(0) })
  process.on("SIGTERM", () => { reset(); process.exit(0) })

  return {
    event: async ({ event }) => {
      const t = event.type as string
      const p = event.properties as any

      if (t === "session.created" && p?.info?.parentID) {
        children.add(p.info.id)
        return
      }
      if (t === "session.deleted") {
        children.delete(p?.sessionID ?? p?.info?.id ?? "")
        return
      }

      const sid = p?.sessionID
      if (sid && children.has(sid)) return

      if (t === "session.status") {
        busy = p.status?.type === "busy"
        return render()
      }
      if (t === "session.error") {
        pending.clear()
        busy = false
        return emit(`${ICON.err} ${label}`, 2)
      }
      if (t === "permission.asked" || t === "permission.updated") {
        if (sid) pending.add(sid)
        return render()
      }
      if (t === "permission.replied") {
        if (sid) pending.delete(sid)
        return render()
      }
    },
  }
}
