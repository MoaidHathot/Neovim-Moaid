// OverShell OpenCode V2 integration — installed by OverShell; safe to remove this directory.
import { Plugin } from "@opencode/plugin/tui"

export default Plugin.define({
  id: "overshell.v2",
  setup(context) {
    const endpoint = process.env.OVERSHELL_ENDPOINT
    const token = process.env.OVERSHELL_TOKEN
    const tab = process.env.OVERSHELL_TAB_ID
    if (!endpoint || !token || !tab) return

    const stop = new AbortController()
    // Reloading a CLI plugin starts a new counter above this instance's earlier reports.
    let sequence = Date.now() * 1000
    let sent = ""
    let stateKey = ""
    let sending = false
    let retryAt = 0
    let backoff = 1000

    const current = () => {
      const route = context.ui.router.current()
      const id = route.type === "session" ? route.sessionID : undefined
      const info = id ? context.data.session.get(id) : undefined
      const family = id ? [...new Set([id, ...context.data.session.family(id)])] : []
      const permissions = family.flatMap((sessionID) => context.data.session.permission.list(sessionID) ?? [])
      const forms = family.flatMap((sessionID) => context.data.session.form.list(sessionID) ?? [])
      const permission = permissions[0]
      const form = forms[0]
      const status = !id ? "idle" : !info ? "unknown" : permission || form ? "blocked"
        : context.data.session.status(id) === "running" ? "working" : info.outcome === "failed" ? "error" : "idle"
      const location = info?.location ?? context.location ?? context.data.location.default()
      return { id, info, permissions, forms, permission, form, status, location }
    }

    const report = async () => {
      if (stop.signal.aborted || sending || Date.now() < retryAt) return
      sending = true
      try {
        const view = current()
        const payload = {
          tab, source: "opencode-ui", harness: "opencode", state: view.status,
          session: { id: view.id ?? null, title: view.info?.title ?? null },
          cwd: view.location.directory,
          requestId: view.permission?.id ?? view.form?.id ?? null,
          requestKind: view.permission ? "permission" : view.form ? "question" : null,
          message: view.permission?.message ?? (view.permission ? `Permission: ${view.permission.action}` : view.form?.title) ?? null,
        }
        const key = JSON.stringify(payload)
        if (key === sent) return
        const nextState = JSON.stringify([view.id, view.status, payload.requestId, payload.requestKind, payload.message])
        const response = await fetch(`${endpoint}/v1/report`, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
          body: JSON.stringify({ ...payload, seq: ++sequence, metadataOnly: nextState === stateKey }),
          signal: AbortSignal.any([stop.signal, AbortSignal.timeout(2000)]),
        })
        if (!response.ok) throw new Error(`OverShell report: HTTP ${response.status}`)
        sent = key
        stateKey = nextState
        backoff = 1000
      } catch {
        retryAt = Date.now() + backoff
        backoff = Math.min(backoff * 2, 30000)
      } finally { sending = false }
    }

    const check = (result: unknown) => {
      if (result && typeof result === "object" && "error" in result && result.error) throw new Error(JSON.stringify(result.error))
    }

    const execute = async (command: { kind: string; requestId?: string | null; response: string }) => {
      const view = current()
      if (command.kind === "permission") {
        const request = command.requestId ? view.permissions.find((p) => p.id === command.requestId) : view.permission
        if (!request) throw new Error("That permission is no longer open in this session")
        const decision = command.response === "approve" ? "once" : command.response === "deny" ? "reject" : command.response
        if (decision !== "once" && decision !== "always" && decision !== "reject") throw new Error("Unknown permission response")
        // V2.0 exposes permission.reply at the root; later generated clients nest it
        // under session. Both use the same session-scoped request and decision.
        const client = context.client as unknown as Record<string, any>
        const permissions = client.permission ?? client.session.permission
        check(await permissions.reply({ sessionID: request.sessionID, requestID: request.id, decision }))
      } else if (command.kind === "question") {
        const form = command.requestId ? view.forms.find((f) => f.id === command.requestId) : view.form
        if (!form) throw new Error("That question is no longer open in this session")
        const fields = form.fields.filter((field) => !("hidden" in field && field.hidden))
        if (fields.length === 0) throw new Error("This form has no visible fields to answer")
        let answer: Record<string, string | number | boolean | string[]>
        if (fields.length === 1) {
          const field = fields[0]
          const options = "options" in field ? field.options : undefined
          const optionValue = (text: string) => options?.find((option) => option.label === text || option.value === text)?.value ?? text
          let value: string | number | boolean | string[] = command.response
          if (field.type === "boolean") {
            const text = command.response.trim()
            if (!/^(yes|no|true|false|y|n|1|0)$/i.test(text)) throw new Error("Answer this field with yes or no")
            value = /^(yes|true|y|1)$/i.test(text)
          } else if (field.type === "number" || field.type === "integer") {
            if (command.response.trim().length === 0) throw new Error("Answer this field with a valid number")
            value = Number(command.response)
            if (!Number.isFinite(value) || (field.type === "integer" && !Number.isInteger(value))) throw new Error("Answer this field with a valid number")
          } else if (field.type === "multiselect") {
            const text = command.response.trim()
            const whole = options?.find((option) => option.label === text || option.value === text)
            value = text.startsWith("[") ? JSON.parse(text)
              : whole ? [whole.value] : text.split(",").map((item) => item.trim()).filter(Boolean)
            if (!Array.isArray(value) || !value.every((item) => typeof item === "string")) throw new Error("Expected a list of choices")
            value = value.map(optionValue)
          } else if (field.type === "string") value = optionValue(command.response)
          else throw new Error("Complete this external field in OpenCode")
          answer = { [field.key]: value }
        } else {
          answer = JSON.parse(command.response)
          if (!answer || Array.isArray(answer) || typeof answer !== "object") throw new Error("Answer multiple fields with a JSON object keyed by field name")
        }
        await context.data.session.form.reply({ sessionID: form.sessionID, formID: form.id, answer }, form.location ?? view.location)
      } else if (command.kind === "prompt") {
        let sessionID = view.id
        if (!sessionID) {
          const created = await context.client.session.create({ location: view.location })
          check(created)
          sessionID = created.id
          context.ui.router.navigate({ type: "session", sessionID })
        }
        check(await context.client.session.prompt({ sessionID, text: command.response }))
      }
    }

    let after = 0
    const poll = async () => {
      while (!stop.signal.aborted) {
        try {
          const response = await fetch(`${endpoint}/v1/tabs/${encodeURIComponent(tab)}/commands?after=${after}`, {
            headers: { authorization: `Bearer ${token}` },
            signal: AbortSignal.any([stop.signal, AbortSignal.timeout(35000)]),
          })
          if (response.status === 401 || response.status === 404) return
          if (!response.ok) throw new Error(`HTTP ${response.status}`)
          const data = await response.json() as { commands?: Array<{ seq: number; kind: string; requestId?: string | null; response: string }> }
          for (const command of data.commands ?? []) {
            if (command.seq <= after || stop.signal.aborted) continue
            after = command.seq
            try { await execute(command) }
            catch (error) { context.ui.toast.show({ title: "OverShell", message: String(error), variant: "error" }) }
          }
        } catch {
          if (stop.signal.aborted) return
          await new Promise<void>((resolve) => {
            const done = () => { clearTimeout(timer); stop.signal.removeEventListener("abort", done); resolve() }
            const timer = setTimeout(done, 1000)
            stop.signal.addEventListener("abort", done, { once: true })
          })
        }
      }
    }

    // Cached accessors keep this per client. No shared-server event can select another
    // tab's session; renames and navigation are observed even without a new agent turn.
    const timer = setInterval(() => { void report() }, 250)
    void report()
    void poll()
    return async () => {
      clearInterval(timer)
      stop.abort()
      try {
        await fetch(`${endpoint}/v1/report`, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
          body: JSON.stringify({ tab, source: "opencode-ui", harness: "opencode", state: "exited", seq: ++sequence }),
          signal: AbortSignal.timeout(2000),
        })
      } catch { /* The owning terminal may already have closed. */ }
    }
  },
})
