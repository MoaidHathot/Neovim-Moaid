import type { TuiPlugin } from "@opencode-ai/plugin/tui"
import { appendFileSync } from "node:fs"
import { basename, join } from "node:path"
import { tmpdir } from "node:os"

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
// This is a TUI plugin rather than a server plugin because terminal focus is
// only observable from the renderer. Server plugins run in a worker thread with
// no renderer and no stdin, and no focus event exists in the server event union.
// OpenTUI already enables DECSET 1004 and parses ESC[I / ESC[O into "focus" and
// "blur" renderer events, so nothing here has to speak raw escape sequences.
//
// TUI plugins are not auto-discovered from plugin directories the way server
// plugins are; this file is registered in tui.json's `plugin` array. It must
// also live outside plugins/, or the server loader would try to load it and
// throw "must default export an object with server()".
// Debug goes to a file, never stderr. This runs on the TUI's main thread, so
// anything written to stderr lands in the middle of the rendered screen and
// corrupts it — unlike the server plugin this replaced, whose stderr was
// captured into the opencode log.
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
// Requires opencode's own title management to be OFF via OPENCODE_n=1, otherwise
// the reactive effect in app.tsx rewrites the title to "OC | <session title>" on
// every route / session-title change and the icon disappears moments after it
// appears. That flag also makes a missing title a useful signal: with opencode's
// titles disabled, a tab showing no title at all means this plugin never loaded.
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

// Mirrors opencode's own isDefaultTitle: an auto-generated placeholder carries
// no information, so fall back to just the repo name rather than showing it.
const DEFAULT_TITLE = /^(New session - |Child session - )\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/

const MAX_TITLE = 40

const tui: TuiPlugin = async (api) => {
  const children = new Set<string>()
  const pending = new Set<string>() // sessions awaiting permission
  const questions = new Set<string>() // open question request IDs
  let busy = false

  // Terminals report focus only on change, never at startup, so the real state
  // is unknown until the first event. Assume focused so a job finishing in a
  // brand new tab doesn't latch a marker the user was actually watching.
  let focused = true
  let unseen = false

  // state.path is populated asynchronously and has been observed empty even
  // after activation, so try every source and resolve per render rather than
  // capturing once.
  const repo = () => {
    for (const candidate of [api.state.path?.directory, api.state.path?.worktree, process.cwd()]) {
      if (!candidate) continue
      const name = basename(candidate)
      if (name) return name
    }
    return "opencode"
  }

  const sessionTitle = () => {
    const route = api.route?.current
    if (route?.name !== "session") return undefined
    const sessionID = (route.params as { sessionID?: string } | undefined)?.sessionID
    if (!sessionID) return undefined
    const title = api.state.session?.get(sessionID)?.title
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
  const emit = (title: string, state: number, pct = 0) => {
    debug(`emit state=${state} pct=${pct} focused=${focused} unseen=${unseen} title="${title}"`)
    if (EMIT_TITLE) {
      // Emit as two separate writes so terminals see two distinct OSCs.
      process.stdout.write(`${esc}]0;${title}${esc}\\`)
    }
    process.stdout.write(`${esc}]9;4;${state};${pct}${esc}\\`)
  }

  // Ring means the machine is working; an icon means it wants you. The two are
  // deliberately never shown together, so the bell replaces the ring rather
  // than competing with it — busy and unseen were both yellow rings before,
  // which made the marker impossible to notice.
  const render = () => {
    if (pending.size || questions.size) return emit(label(ICON.ask), 1, 50)
    if (busy) return emit(label(), 3)
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
  const setBusy = (next: boolean) => {
    if (busy && !next) markUnseen()
    busy = next
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

  api.renderer.on("focus", onFocus)
  api.renderer.on("blur", onBlur)

  // Ignore anything belonging to a child (sub-agent) session; those are noise.
  const foreign = (props: { sessionID?: string }) => Boolean(props.sessionID && children.has(props.sessionID))

  const unsubscribe = [
    api.event.on("session.created", (e) => {
      const info = (e.properties as { info?: { id: string; parentID?: string } }).info
      if (info?.parentID) children.add(info.id)
    }),
    api.event.on("session.deleted", (e) => {
      const props = e.properties as { sessionID?: string; info?: { id: string } }
      children.delete(props.sessionID ?? props.info?.id ?? "")
    }),
    api.event.on("session.status", (e) => {
      const props = e.properties as { sessionID?: string; status?: { type: string } }
      if (foreign(props)) return
      setBusy(props.status?.type === "busy")
    }),
    // Defensive: some flows only fire session.idle without a paired
    // session.status idle event. Treat it as an authoritative "done" signal.
    api.event.on("session.idle", (e) => {
      if (foreign(e.properties as { sessionID?: string })) return
      setBusy(false)
    }),
    api.event.on("session.compacted", (e) => {
      if (foreign(e.properties as { sessionID?: string })) return
      setBusy(false)
    }),
    api.event.on("session.error", (e) => {
      if (foreign(e.properties as { sessionID?: string })) return
      pending.clear()
      busy = false
      markUnseen()
      emit(label(ICON.err), 2)
    }),
    api.event.on("permission.asked", (e) => {
      const props = e.properties as { sessionID?: string }
      if (foreign(props)) return
      if (props.sessionID) pending.add(props.sessionID)
      markUnseen()
      render()
    }),
    api.event.on("permission.replied", (e) => {
      const props = e.properties as { sessionID?: string }
      if (foreign(props)) return
      if (props.sessionID) pending.delete(props.sessionID)
      render()
    }),
    // Multi-choice questions ("Open questions for you" style prompts). These are
    // tracked by request ID, not session ID, since multiple questions can be
    // open within a single session.
    api.event.on("question.asked", (e) => {
      const props = e.properties as { sessionID?: string; id?: string }
      if (foreign(props)) return
      if (props.id) questions.add(props.id)
      markUnseen()
      render()
    }),
    api.event.on("question.replied", (e) => {
      const props = e.properties as { requestID?: string }
      if (props.requestID) questions.delete(props.requestID)
      render()
    }),
    api.event.on("question.rejected", (e) => {
      const props = e.properties as { requestID?: string }
      if (props.requestID) questions.delete(props.requestID)
      render()
    }),
  ]

  const clear = () => {
    process.stdout.write(`${esc}]9;4;0;0${esc}\\`)
  }

  // api.renderer is handed to plugins unwrapped and is not scope-tracked, so
  // these listeners would outlive the plugin without explicit cleanup.
  api.lifecycle.onDispose(() => {
    api.renderer.off("focus", onFocus)
    api.renderer.off("blur", onBlur)
    for (const off of unsubscribe) off()
    process.off("exit", clear)
    clear()
  })
  process.on("exit", clear)

  // Log the raw path sources, not just the derived label: a previous run showed
  // an empty label and the derived value alone gave no way to tell which source
  // was missing.
  debug(
    `activated label="${label()}" directory="${api.state.path?.directory}" ` +
      `worktree="${api.state.path?.worktree}" cwd="${process.cwd()}" route="${api.route?.current?.name}"`,
  )
  render()
}

export default {
  id: "tab-status",
  tui,
}
