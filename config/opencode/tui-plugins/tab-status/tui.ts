// OpenCode 2 CLI plugin (ported from the V1 `TuiPlugin` form).
//
// Emits Windows Terminal OSC sequences so each tab visually reflects the state
// of its OpenCode session, and latches an "unseen" marker for work that
// finished while you were not looking at that tab.
//
// OSC 0       → tab title
// OSC 9;4;s;p → tab progress bar  (state s, percent p)
//   s=0 clear, s=1 green, s=2 red, s=3 pulsing yellow, s=4 solid yellow
//
// Visual encoding (state, percent) — chosen so each is distinguishable at
// a glance even without the title prefix:
//   idle      → (0, 0)     no bar
//   busy      → (3, 0)     pulsing yellow indeterminate
//   question  → (1, 50)    half-filled green bar (literally "half progress")
//   error     → (2, 0)     solid red
//   unseen    → (4, 100)   solid yellow, full bar
//
// This is a CLI plugin rather than a server plugin because terminal focus is
// only observable from the renderer, and because in V2 one shared background
// server serves every terminal: a server plugin would not know which tab it
// belongs to. OpenTUI enables DECSET 1004 and parses ESC[I / ESC[O into
// "focus" and "blur" renderer events, so nothing here speaks raw input codes.
//
// V2 specifics:
// - The event stream carries every session on the shared server, so state is
//   scoped to the session this TUI is currently showing (`ui.router.current()`),
//   which is also what V2's own session tabs switch between.
// - Questions are V2 "forms" (`form.created` / `form.replied` / `form.cancelled`).
// - OpenCode's own title management must be OFF via `"terminal": { "title": false }`
//   in cli.json, otherwise app.tsx rewrites the title to "OC | <session title>" on
//   every route / session-title change and the icon disappears moments after it
//   appears. That setting also makes a missing title a useful signal: a tab showing
//   no title at all means this plugin never loaded.
// - Registered in cli.json's `plugins` array as the *directory* `./tui-plugins/tab-status`.
//   The V2 CLI only loads local plugins laid out like a package (`<dir>/tui.ts`); an
//   entry pointing straight at a .ts file is skipped silently, with no error or log.
//
// Debug goes to a file, never stderr. This runs on the TUI's main thread, so
// anything written to stderr lands in the middle of the rendered screen.
import { Plugin } from "@opencode/plugin/tui"
import { appendFileSync } from "node:fs"
import { basename, join } from "node:path"
import { tmpdir } from "node:os"

const DEBUG_FILE = process.env.OPENCODE_TAB_STATUS_DEBUG === "1" ? join(tmpdir(), "opencode-tab-status.log") : undefined
const debug = (line: string) => {
  if (!DEBUG_FILE) return
  try {
    appendFileSync(DEBUG_FILE, `${new Date().toISOString()} ${line}\n`)
  } catch {
    // Diagnostics must never take the tab indicator down with them.
  }
}

// Emit the OSC 0 tab title, which is what carries the status icon. Flip to
// false here for progress-bar-only; this is a source toggle on purpose, since
// the two OSC channels are hard to tell apart without the icon (busy and unseen
// are both yellow).
//
// The title and the progress bar are emitted as two separate writes because some
// terminals/parsers treat a combined blob as a single sequence and drop the
// trailing OSC (that caused a stuck busy bar).
const EMIT_TITLE = true

// Tab titles render in Windows Terminal's UI font (Segoe UI Variable), not the
// terminal font — Nerd Font glyphs tofu there. Use emoji instead.
//
// There is deliberately no icon for busy or idle. The ring IS the busy signal,
// and an icon on every tab all the time just crowds out the session title.
// Icons are reserved for states that want your attention.
const ICON = {
  ask: "\u{2753}", // red question mark
  err: "\u{274C}", // cross mark
  unseen: "\u{1F514}", // bell
}

// Mirrors opencode's own fallback-title check: an auto-generated placeholder carries
// no information, so fall back to just the repo name rather than showing it.
const DEFAULT_TITLE = /^(New session - |Child session - )\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/

const MAX_TITLE = 40

type FocusEmitter = {
  on?: (event: string, handler: () => void) => unknown
  off?: (event: string, handler: () => void) => unknown
}

export default Plugin.define({
  id: "moaid.tab-status",
  setup(context) {
    const children = new Set<string>()
    const busy = new Map<string, boolean>() // sessionID → busy
    const errored = new Set<string>() // sessions whose last turn failed
    const pending = new Map<string, string>() // permission request ID → sessionID
    const questions = new Map<string, string>() // form ID → sessionID

    // Terminals report focus only on change, never at startup, so the real state
    // is unknown until the first event. Assume focused so a job finishing in a
    // brand new tab doesn't latch a marker the user was actually watching.
    let focused = true
    let unseen = false

    const current = () => {
      const route = context.ui.router.current()
      return route.type === "session" ? route.sessionID : undefined
    }

    const isChild = (sessionID: string) =>
      children.has(sessionID) || context.data.session.get(sessionID)?.parentID !== undefined

    // Ignore anything belonging to a child (sub-agent) session; those are noise.
    // Everything else only matters when it is the session this terminal is showing.
    const mine = (sessionID: string | undefined) => {
      if (!sessionID || isChild(sessionID)) return false
      const active = current()
      return !!active && (active === sessionID || context.data.session.root(active) === sessionID)
    }

    // Workspace label. Prefer the plugin's location, then the TUI's default location,
    // then cwd. Drive roots ("W:\") and "/" have no basename: show the root itself
    // rather than falling through to a literal, which would mislabel every workspace
    // opened at a drive root as whatever the fallback happens to be.
    const repo = () => {
      let fallback: string | undefined
      try {
        fallback = context.data.location.default()?.directory
      } catch {
        fallback = undefined
      }
      for (const candidate of [context.location?.directory, fallback, process.cwd()]) {
        if (!candidate) continue
        const name = basename(candidate)
        if (name) return name
        const root = candidate.replace(/[\\/]+$/, "")
        if (root) return root
      }
      return "opencode"
    }

    const sessionTitle = () => {
      const sessionID = current()
      if (!sessionID) return undefined
      const title = context.data.session.get(sessionID)?.title
      if (!title || DEFAULT_TITLE.test(title)) return undefined
      return title.length > MAX_TITLE ? `${title.slice(0, MAX_TITLE - 3)}...` : title
    }

    // "OC | repo | session title", with the session segment dropped when there
    // isn't a real one yet. Icon prefixes only when a state wants attention.
    const label = (icon?: string) => {
      const parts = ["OC", repo()]
      const session = sessionTitle()
      if (session) parts.push(session)
      const text = parts.join(" | ")
      return icon ? `${icon} ${text}` : text
    }

    const esc = "\x1b"
    // Several events collapse to the same visual state, which produced 25 identical
    // writes out of 55 in a real session. Skip unchanged repaints.
    let lastEmit = ""
    const emit = (title: string, state: number, pct = 0) => {
      const key = `${title}\u0000${state}\u0000${pct}`
      if (key === lastEmit) return
      lastEmit = key
      debug(`emit state=${state} pct=${pct} focused=${focused} unseen=${unseen} title="${title}"`)
      if (EMIT_TITLE) {
        // Emit as two separate writes so terminals see two distinct OSCs.
        process.stdout.write(`${esc}]0;${title}${esc}\\`)
      }
      process.stdout.write(`${esc}]9;4;${state};${pct}${esc}\\`)
    }

    const isBusy = (sessionID: string | undefined) => {
      if (!sessionID) return false
      const known = busy.get(sessionID)
      if (known !== undefined) return known
      // First time we see this session (e.g. resumed): seed from the TUI's cache.
      const seeded = context.data.session.status(sessionID) === "running"
      busy.set(sessionID, seeded)
      return seeded
    }

    const asking = (sessionID: string | undefined) => {
      if (!sessionID) return false
      for (const owner of pending.values()) if (owner === sessionID) return true
      for (const owner of questions.values()) if (owner === sessionID) return true
      return (context.data.session.permission.list(sessionID)?.length ?? 0) > 0
    }

    // Ring means the machine is working; an icon means it wants you. The two are
    // deliberately never shown together, so the bell replaces the ring rather
    // than competing with it — busy and unseen were both yellow rings before,
    // which made the marker impossible to notice.
    //
    // Errors rank above the unseen bell: if a session failed while you were away,
    // "it broke" is more useful than "you missed something".
    const render = () => {
      const sessionID = current()
      if (asking(sessionID)) return emit(label(ICON.ask), 1, 50)
      if (isBusy(sessionID)) return emit(label(), 3)
      if (sessionID && errored.has(sessionID)) return emit(label(ICON.err), 2)
      if (unseen) return emit(label(ICON.unseen), 0)
      return emit(label(), 0)
    }

    // Only latch when the tab isn't being looked at — that is the whole point.
    const markUnseen = () => {
      if (focused) return
      unseen = true
    }

    // "Finished" is the busy → not-busy transition, not merely being idle;
    // otherwise every idle heartbeat while blurred would latch a marker.
    const setBusy = (sessionID: string, next: boolean) => {
      const was = busy.get(sessionID) ?? false
      busy.set(sessionID, next)
      if (!mine(sessionID)) return
      if (was && !next) markUnseen()
      // New work supersedes an older failure.
      if (next) errored.delete(sessionID)
      render()
    }

    const onFocus = () => {
      debug("renderer focus")
      focused = true
      if (!unseen) return
      unseen = false
      render()
    }
    const onBlur = () => {
      debug("renderer blur")
      focused = false
    }

    const renderer = context.renderer as unknown as FocusEmitter
    renderer.on?.("focus", onFocus)
    renderer.on?.("blur", onBlur)

    const unsubscribe = [
      context.data.on("session.created", (e) => {
        if (e.data.parentID) children.add(e.data.sessionID)
        render()
      }),
      context.data.on("session.deleted", (e) => {
        const id = e.data.sessionID
        children.delete(id)
        busy.delete(id)
        errored.delete(id)
        for (const [key, owner] of pending) if (owner === id) pending.delete(key)
        for (const [key, owner] of questions) if (owner === id) questions.delete(key)
        render()
      }),
      context.data.on("session.renamed", () => render()),
      // Navigating between sessions (or V2 session tabs) re-labels the terminal tab.
      context.data.on("session.viewed", () => render()),
      context.data.on("session.status", (e) => {
        if (isChild(e.data.sessionID)) return
        setBusy(e.data.sessionID, e.data.status.type !== "idle")
      }),
      context.data.on("session.execution.started", (e) => {
        if (isChild(e.data.sessionID)) return
        setBusy(e.data.sessionID, true)
      }),
      context.data.on("session.execution.succeeded", (e) => {
        if (isChild(e.data.sessionID)) return
        setBusy(e.data.sessionID, false)
      }),
      context.data.on("session.execution.interrupted", (e) => {
        if (isChild(e.data.sessionID)) return
        setBusy(e.data.sessionID, false)
      }),
      // Defensive: some flows only fire session.idle without a paired
      // session.status idle event. Treat it as an authoritative "done" signal.
      context.data.on("session.idle", (e) => {
        if (isChild(e.data.sessionID)) return
        setBusy(e.data.sessionID, false)
      }),
      context.data.on("session.compaction.ended", (e) => {
        if (isChild(e.data.sessionID)) return
        render()
      }),
      // Errors have to persist. Emitting red directly meant the next idle event
      // repainted over it 27ms later, so the failure was never actually visible.
      // Cleared when new work starts, not on focus — seeing the tab isn't the same
      // as having dealt with what broke.
      context.data.on("session.execution.failed", (e) => {
        const id = e.data.sessionID
        if (isChild(id)) return
        for (const [key, owner] of pending) if (owner === id) pending.delete(key)
        busy.set(id, false)
        errored.add(id)
        if (!mine(id)) return
        markUnseen()
        render()
      }),
      context.data.on("permission.asked", (e) => {
        if (isChild(e.data.sessionID)) return
        pending.set(e.data.id, e.data.sessionID)
        if (!mine(e.data.sessionID)) return
        markUnseen()
        render()
      }),
      context.data.on("permission.replied", (e) => {
        pending.delete(e.data.requestID)
        render()
      }),
      // Multi-choice questions are V2 forms. Tracked by form ID, not session ID,
      // since several can be open within a single session.
      context.data.on("form.created", (e) => {
        const id = e.data.form.sessionID
        if (isChild(id)) return
        questions.set(e.data.form.id, id)
        if (!mine(id)) return
        markUnseen()
        render()
      }),
      context.data.on("form.replied", (e) => {
        questions.delete(e.data.id)
        render()
      }),
      context.data.on("form.cancelled", (e) => {
        questions.delete(e.data.id)
        render()
      }),
    ]

    // `ui.router.current()` is only reactive inside Solid computations, so a slow
    // heartbeat catches route changes that arrive without a session.viewed event.
    const heartbeat = setInterval(render, 2000)

    const clear = () => {
      process.stdout.write(`${esc}]9;4;0;0${esc}\\`)
    }
    process.on("exit", clear)

    debug(
      `activated label="${label()}" location="${context.location?.directory}" ` +
        `cwd="${process.cwd()}" route="${context.ui.router.current().type}" version="${context.app.version}"`,
    )
    render()

    // The renderer is handed to plugins unwrapped and is not scope-tracked, so
    // these listeners would outlive the plugin without explicit cleanup.
    return () => {
      clearInterval(heartbeat)
      renderer.off?.("focus", onFocus)
      renderer.off?.("blur", onBlur)
      for (const off of unsubscribe) off()
      process.off("exit", clear)
      clear()
    }
  },
})
