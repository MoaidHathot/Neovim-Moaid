import type { Plugin } from "@opencode-ai/plugin"

export const PalantirPlugin: Plugin = async ({ $, directory }) => {
  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  let wasBusy = false

  const notify = async (...args: string[]) => {
    try {
      await $`cmd /c dnx Palantir --yes -- ${args}`
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
        "-t", "OpenCode",
        "-m", "Task completed - ready for input",
        "-b", directory,
        "--audio", "im", "-q"
      )
    }, 3000)
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.status") {
        const status = (event.properties as { status: { type: string } }).status
        if (status.type === "busy") {
          wasBusy = true
          cancelPending()
        } else if (status.type === "idle" && wasBusy) {
          wasBusy = false
          scheduleIdleNotify()
        }
      } else if (event.type === "session.error") {
        cancelPending()
        wasBusy = false
        await notify(
          "-t", "OpenCode",
          "-m", "Session encountered an error",
          "-b", directory,
          "--audio", "reminder",
          "--duration", "long", "-q"
        )
      }
    },

    "permission.ask": async (_input, _output) => {
      await notify(
        "-t", "OpenCode",
        "-m", "Action requires your approval",
        "-b", directory,
        "--audio", "reminder",
        "--duration", "long", "-q"
      )
    },
  }
}
