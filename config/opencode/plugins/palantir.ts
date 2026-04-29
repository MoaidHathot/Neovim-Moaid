import type { Plugin } from "@opencode-ai/plugin"

export const PalantirPlugin: Plugin = async ({ $, directory }) => {
  const childSessions = new Set<string>()
  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  let wasBusy = false

  const notify = async (...args: string[]) => {
    try {
      await $`cmd /c dnx Palantir --yes --add-source https://api.nuget.org/v3/index.json -- -q ${args}`
    } catch {
      // Silently ignore notification failures
    }
  }

  const cancelPending = () => {
    if (debounceTimer) {
      clearTimeout(debounceTimer)
      debounceTimer = null
    }
  }

  const scheduleIdleNotify = () => {
    cancelPending()
    debounceTimer = setTimeout(() => {
      debounceTimer = null
      notify(
        "--preset", "opencode",
        "-m", "Task completed - ready for input",
        "-b", directory,
      )
    }, 3000)
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        const info = (event.properties as { info: { id: string; parentID?: string } }).info
        if (info.parentID) {
          childSessions.add(info.id)
        }
      } else if (event.type === "session.deleted") {
        const props = event.properties as { sessionID?: string; info?: { id: string } }
        childSessions.delete(props.sessionID ?? props.info?.id ?? "")
      } else if (event.type === "session.status") {
        const props = event.properties as { sessionID: string; status: { type: string } }
        if (childSessions.has(props.sessionID)) return
        if (props.status.type === "busy") {
          wasBusy = true
          cancelPending()
        } else if (props.status.type === "idle" && wasBusy) {
          wasBusy = false
          scheduleIdleNotify()
        }
      } else if (event.type === "session.error") {
        const props = event.properties as { sessionID: string }
        if (childSessions.has(props.sessionID)) return
        cancelPending()
        wasBusy = false
        await notify(
          "--preset", "opencode-action",
          "-m", "Session encountered an error",
          "-b", directory,
        )
      }
    },

    "permission.ask": async (_input, _output) => {
      await notify(
        "--preset", "opencode-action",
        "-m", "Action requires your approval",
        "-b", directory,
      )
    },
  }
}
