// OverShell integration v3 (OpenCode 2 CLI plugin). Ported from the V1 server plugin
// written by `OverShell integrations install opencode`. Safe to delete.
//
// Reports this OpenCode tab's state to the OverShell tab that launched it, over
// loopback, so the tab strip, sidebar and notifications know exactly when the agent is
// working, waiting for input, blocked on a permission or question, or failed — and
// carries OverShell's answers back: a permission approved or denied from the inbox or a
// toast, a question answered, a prompt sent, all through OpenCode's own API rather than
// typed into the dialog. Outside OverShell the environment variables are absent and the
// plugin does nothing.
//
// Why a CLI plugin in V2: OpenCode 2 runs one shared background server per user and
// every terminal connects to it. A server plugin therefore has neither the tab's
// OVERSHELL_* environment nor any notion of "this tab"; the terminal client has both,
// plus the generated client (`context.client`) to reply to permissions and forms and to
// submit prompts. Registered in cli.json's `plugins` array as the *directory*
// `./tui-plugins/overshell`: the V2 CLI only loads local plugins laid out like a package
// (`<dir>/tui.ts`) and silently skips an entry that points straight at a .ts file.
//
// Never write to stderr from here: this runs on the TUI's main thread and anything on
// stderr lands in the middle of the rendered screen. Problems surface as toasts.
import { Plugin } from "@opencode/plugin/tui"

const endpoint = process.env.OVERSHELL_ENDPOINT
const token = process.env.OVERSHELL_TOKEN
const tab = process.env.OVERSHELL_TAB_ID

type Command = { seq: number; kind: string; requestId?: string | null; response: string }

export default Plugin.define({
  id: "moaid.overshell",
  setup(context) {
    if (!endpoint || !token || !tab) return

    const children = new Set<string>()
    let seq = 0
    let failures = 0
    let lastReported: string | undefined

    const directory = () => {
      if (context.location?.directory) return context.location.directory
      try {
        return context.data.location.default()?.directory ?? process.cwd()
      } catch {
        return process.cwd()
      }
    }

    // The tab's session is whatever this terminal is showing. V2 session tabs switch
    // this too, which is the right semantic for a per-terminal-tab integration.
    const current = () => {
      const route = context.ui.router.current()
      return route.type === "session" ? route.sessionID : undefined
    }

    const title = () => {
      const id = current()
      const value = id ? context.data.session.get(id)?.title : undefined
      if (!value || /^(New session|Child session) - /.test(value)) return undefined
      return value
    }

    const isChild = (sessionID: string) =>
      children.has(sessionID) || context.data.session.get(sessionID)?.parentID !== undefined

    // Sub-agent sessions are noise for the tab's state; so is every other session on
    // the shared server that this terminal is not showing.
    const mine = (sessionID: string | undefined) => {
      if (!sessionID || isChild(sessionID)) return false
      const active = current()
      return !!active && (active === sessionID || context.data.session.root(active) === sessionID)
    }

    const report = (state: string, extra: Record<string, unknown> = {}) => {
      if (failures >= 5) return
      const sessionId = current()
      const body = {
        tab,
        source: "opencode",
        harness: "opencode",
        seq: ++seq,
        state,
        summary: title(),
        session: sessionId ? { id: sessionId, resumeCommand: `opencode --session ${sessionId}` } : undefined,
        cwd: directory(),
        ...extra,
      }
      lastReported = sessionId
      fetch(`${endpoint}/v1/report`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(2000),
      })
        .then(() => {
          failures = 0
        })
        .catch(() => {
          failures++
        })
    }

    const warn = (message: string) => {
      context.ui.toast.show({ title: "OverShell", message, variant: "warning" })
    }

    // ---- the way back: OverShell's commands for this tab ----
    // The ids of the permission / form currently open, so a reply from OverShell can
    // name one even when the command queue only says "approve".
    let openPermission: { id: string; sessionID: string } | undefined
    let openForm: { id: string; sessionID: string } | undefined

    const replyPermission = async (requestID: string, sessionID: string, decision: "once" | "always" | "reject") => {
      try {
        await context.client.permission.reply({ sessionID, requestID, decision })
        return true
      } catch (error) {
        warn(`permission reply did not land: ${error instanceof Error ? error.message : String(error)}`)
        return false
      }
    }

    // OverShell answers a "question" with one string. V2 questions are forms with typed
    // fields: answer the first visible field, coercing to its type and mapping an option
    // label back to its value when the string matches a label.
    const formAnswer = (sessionID: string, formID: string, response: string) => {
      const form = context.data.session.form.list(sessionID)?.find((item) => item.id === formID)
      const field = form?.fields.find((item) => !("hidden" in item && item.hidden))
      if (!field) return { answer: response }
      const options = "options" in field ? field.options : undefined
      const match = options?.find((option) => option.label === response || option.value === response)
      const value = match?.value ?? response
      switch (field.type) {
        case "multiselect":
          return { [field.key]: value.split(",").map((item) => item.trim()).filter(Boolean) }
        case "boolean":
          return { [field.key]: /^(true|yes|y|1)$/i.test(value) }
        case "number":
        case "integer":
          return { [field.key]: Number(value) }
        default:
          return { [field.key]: value }
      }
    }

    const replyForm = async (formID: string, sessionID: string, response: string) => {
      try {
        await context.client.session.form.reply({ sessionID, formID, answer: formAnswer(sessionID, formID, response) })
        return true
      } catch (error) {
        warn(`question reply did not land: ${error instanceof Error ? error.message : String(error)}`)
        return false
      }
    }

    // Prompts go straight to the session, which is also what a headless run needs. When
    // the tab is still on the home screen (OverShell sends a first prompt after the screen
    // settles), create the session and navigate to it so the user sees the turn.
    const sendPrompt = async (text: string) => {
      try {
        let sessionID = current()
        if (!sessionID) {
          const session = await context.client.session.create({ location: { directory: directory() } })
          sessionID = session.id
          context.ui.router.navigate({ type: "session", sessionID })
        }
        await context.client.session.prompt({ sessionID, text })
        return true
      } catch (error) {
        warn(`prompt could not be delivered: ${error instanceof Error ? error.message : String(error)}`)
        return false
      }
    }

    const execute = async (command: Command) => {
      switch (command.kind) {
        case "permission": {
          const target = command.requestId
            ? { id: command.requestId, sessionID: openPermission?.sessionID ?? current() ?? "" }
            : openPermission
          if (!target) return
          const decision =
            command.response === "approve"
              ? "once"
              : command.response === "deny"
                ? "reject"
                : command.response === "always" || command.response === "once" || command.response === "reject"
                  ? command.response
                  : "once"
          if (await replyPermission(target.id, target.sessionID, decision)) {
            if (openPermission?.id === target.id) openPermission = undefined
          }
          return
        }
        case "question": {
          const target = command.requestId
            ? { id: command.requestId, sessionID: openForm?.sessionID ?? current() ?? "" }
            : openForm
          if (!target) return
          if (await replyForm(target.id, target.sessionID, command.response)) {
            if (openForm?.id === target.id) openForm = undefined
          }
          return
        }
        case "prompt":
          await sendPrompt(command.response)
          return
      }
    }

    // A long poll per tab: held up to 25 s by OverShell, answered at once when something is
    // queued. Failures back off; the loop ends when the tab is gone or the plugin unloads.
    let after = 0
    let polling = true
    const poll = async () => {
      let backoff = 1000
      while (polling) {
        try {
          const res = await fetch(`${endpoint}/v1/tabs/${encodeURIComponent(tab)}/commands?after=${after}`, {
            headers: { authorization: `Bearer ${token}` },
            signal: AbortSignal.timeout(35000),
          })
          if (res.status === 401 || res.status === 404) return
          if (!res.ok) throw new Error(String(res.status))
          const data = (await res.json()) as { commands?: Command[] }
          for (const command of data.commands ?? []) {
            after = Math.max(after, command.seq)
            await execute(command)
          }
          backoff = 1000
        } catch {
          await new Promise((r) => setTimeout(r, backoff))
          backoff = Math.min(backoff * 2, 30000)
        }
      }
    }
    void poll()

    const unsubscribe = [
      context.data.on("session.created", (e) => {
        if (e.data.parentID) {
          children.add(e.data.sessionID)
          return
        }
        // Created from this tab's home screen: the router moves to it right after.
        setTimeout(() => {
          if (mine(e.data.sessionID)) report("idle", { message: "session started" })
        }, 100)
      }),
      context.data.on("session.deleted", (e) => children.delete(e.data.sessionID)),
      context.data.on("session.renamed", (e) => {
        if (mine(e.data.sessionID)) report(context.data.session.status(e.data.sessionID) === "running" ? "working" : "idle")
      }),
      // A resumed session (`opencode --session <id>` - what OverShell types after a restart)
      // never fires session.created, so the first view of a session announces it.
      context.data.on("session.viewed", (e) => {
        if (!mine(e.data.sessionID) || lastReported === e.data.sessionID) return
        report(context.data.session.status(e.data.sessionID) === "running" ? "working" : "idle", {
          message: "session resumed",
        })
      }),
      context.data.on("session.status", (e) => {
        if (!mine(e.data.sessionID)) return
        if (e.data.status.type === "busy") report("working")
        else if (e.data.status.type === "idle") report("idle", { message: "turn finished" })
      }),
      context.data.on("session.execution.started", (e) => {
        if (mine(e.data.sessionID)) report("working")
      }),
      context.data.on("session.execution.succeeded", (e) => {
        if (mine(e.data.sessionID)) report("idle", { message: "turn finished" })
      }),
      context.data.on("session.execution.interrupted", (e) => {
        if (mine(e.data.sessionID)) report("idle", { message: "turn interrupted" })
      }),
      context.data.on("session.idle", (e) => {
        if (mine(e.data.sessionID)) report("idle", { message: "turn finished" })
      }),
      context.data.on("session.execution.failed", (e) => {
        if (mine(e.data.sessionID)) report("error", { message: e.data.error.message || "Session encountered an error" })
      }),
      context.data.on("permission.asked", (e) => {
        if (!mine(e.data.sessionID)) return
        openPermission = { id: e.data.id, sessionID: e.data.sessionID }
        report("blocked", {
          message: e.data.message ?? `Action requires your approval: ${e.data.action}`,
          requestId: e.data.id,
          requestKind: "permission",
        })
      }),
      context.data.on("permission.replied", (e) => {
        if (!mine(e.data.sessionID)) return
        openPermission = undefined
        report("working", { message: "permission answered" })
      }),
      context.data.on("form.created", (e) => {
        const id = e.data.form.sessionID
        if (!mine(id)) return
        openForm = { id: e.data.form.id, sessionID: id }
        report("blocked", {
          message: e.data.form.title || "OpenCode is asking a question",
          requestId: e.data.form.id,
          requestKind: "question",
        })
      }),
      context.data.on("form.replied", (e) => {
        if (!mine(e.data.sessionID)) return
        openForm = undefined
        report("working", { message: "question answered" })
      }),
      context.data.on("form.cancelled", (e) => {
        if (!mine(e.data.sessionID)) return
        openForm = undefined
        report("working", { message: "question dismissed" })
      }),
    ]

    const id = current()
    if (id) report(context.data.session.status(id) === "running" ? "working" : "idle", { message: "session resumed" })

    return () => {
      polling = false
      for (const off of unsubscribe) off()
    }
  },
})
