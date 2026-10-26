// OpenCode 2 server plugin (ported from the V1 Hooks-object form).
//
// Desktop notifications through Palantir (dnx) when a session finishes a turn, fails,
// asks for permission, or asks a question (V2 "forms").
//
// V2 differences that shape this file:
// - Plugins are instantiated once per location (project directory) on one shared
//   background server, and the event stream is server-wide. Every event is therefore
//   filtered to sessions that belong to this instance's location, or the same turn
//   would notify once per open project.
// - There is no `$` shell helper and no TUI toast API for server plugins; dnx runs via
//   child_process and a dead notifier is reported once through the server log
//   (~/.local/share/opencode/log/opencode.log, role=server).
import { Plugin } from "@opencode/plugin"
import { existsSync, readdirSync } from "node:fs"
import { execFile } from "node:child_process"

// dnx --source takes a path or URL, not a configured NuGet source name, so the feed
// location can't be committed to dotfiles. Set PRIVATE_LOCAL_NUGET_FEED per machine
// (configuration.dev.dsc.yaml does this) to resolve from it in ~0.4s per notification.
//
// The existence check matters because the DSC sets the variable on every machine,
// including ones where the feed isn't populated yet. Without it, dnx would be handed a
// nonexistent path and every notification would fail. Falling back to all configured
// sources still works, it just costs ~10s from the remote auth round-trip.
const FEED = process.env.PRIVATE_LOCAL_NUGET_FEED
const SOURCE = FEED && existsSync(FEED) && readdirSync(FEED).length > 0 ? ["--source", FEED] : []

const samePath = (a: string | undefined, b: string | undefined) =>
  !!a && !!b && a.replace(/[\\/]+$/, "").toLowerCase() === b.replace(/[\\/]+$/, "").toLowerCase()

export default Plugin.define({
  id: "moaid.palantir",
  async setup(ctx) {
    const directory = ctx.location.directory
    const childSessions = new Set<string>()
    const timers = new Map<string, ReturnType<typeof setTimeout>>()
    const busy = new Set<string>()
    const ownership = new Map<string, boolean>()
    let notifyFailed = false

    const notify = (...args: string[]) =>
      new Promise<void>((resolve) => {
        // Highest stable version in the feed wins; version count doesn't affect lookup speed.
        execFile(
          "cmd",
          ["/c", "dnx", "Palantir", "--yes", ...SOURCE, "--", "-q", ...args],
          { windowsHide: true, timeout: 60_000 },
          (error) => {
            if (!error) return resolve()
            // Report once. A dead feed otherwise disables notifications silently,
            // which is how the nuget.org block went unnoticed for four months.
            if (!notifyFailed) {
              notifyFailed = true
              console.error(`[palantir] notifications disabled: dnx failed (${error.message})`)
            }
            resolve()
          },
        )
      })

    // Sessions created before this instance loaded (resumed tabs) are not seen being
    // born, so ownership falls back to asking the server for the session's location.
    const mine = async (sessionID: string | undefined, location: { directory: string } | undefined) => {
      if (!sessionID) return false
      if (childSessions.has(sessionID)) return false
      if (location) return samePath(location.directory, directory)
      const cached = ownership.get(sessionID)
      if (cached !== undefined) return cached
      const owned = await ctx.session
        .get({ sessionID })
        .then((session) => {
          if (session.parentID) childSessions.add(sessionID)
          return !session.parentID && samePath(session.location?.directory, directory)
        })
        .catch(() => false)
      ownership.set(sessionID, owned)
      return owned
    }

    const cancelPending = (sessionID: string) => {
      const timer = timers.get(sessionID)
      if (!timer) return
      clearTimeout(timer)
      timers.delete(sessionID)
    }

    const scheduleIdleNotify = (sessionID: string, dir: string) => {
      cancelPending(sessionID)
      timers.set(
        sessionID,
        setTimeout(() => {
          timers.delete(sessionID)
          void notify("--preset", "opencode-idle", "-m", "Ready for input", "-b", dir)
        }, 3000),
      )
    }

    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          switch (event.type) {
            case "session.created": {
              if (event.data.parentID) {
                childSessions.add(event.data.sessionID)
                break
              }
              ownership.set(event.data.sessionID, samePath(event.data.location.directory, directory))
              break
            }
            case "session.deleted": {
              childSessions.delete(event.data.sessionID)
              ownership.delete(event.data.sessionID)
              busy.delete(event.data.sessionID)
              cancelPending(event.data.sessionID)
              break
            }
            case "session.status": {
              const id = event.data.sessionID
              if (!(await mine(id, event.location))) break
              if (event.data.status.type === "busy") {
                busy.add(id)
                cancelPending(id)
              } else if (event.data.status.type === "idle" && busy.has(id)) {
                busy.delete(id)
                scheduleIdleNotify(id, event.location?.directory ?? directory)
              }
              break
            }
            case "session.execution.failed": {
              const id = event.data.sessionID
              if (!(await mine(id, event.location))) break
              cancelPending(id)
              busy.delete(id)
              await notify(
                "--preset", "opencode-error",
                "-m", "Session encountered an error",
                "-b", event.location?.directory ?? directory,
              )
              break
            }
            case "permission.asked": {
              const id = event.data.sessionID
              if (!(await mine(id, event.location))) break
              cancelPending(id)
              await notify(
                "--preset", "opencode-permission",
                "-m", "Action requires your approval",
                "-b", event.location?.directory ?? directory,
              )
              break
            }
            case "form.created": {
              const id = event.data.form.sessionID
              if (!(await mine(id, event.location))) break
              cancelPending(id)
              await notify(
                "--preset", "opencode-permission",
                "-m", "OpenCode is asking a question",
                "-b", event.location?.directory ?? directory,
              )
              break
            }
          }
        }
      } catch (error) {
        if (!controller.signal.aborted) console.error("[palantir] event stream ended:", error)
      }
    })()

    return () => {
      controller.abort()
      for (const timer of timers.values()) clearTimeout(timer)
      timers.clear()
    }
  },
})
