import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readdirSync } from "node:fs"

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

export const PalantirPlugin: Plugin = async ({ $, client, directory }) => {
  const childSessions = new Set<string>()
  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  let wasBusy = false
  let notifyFailed = false

  const notify = async (...args: string[]) => {
    // Highest stable version in the feed wins; version count doesn't affect lookup speed.
    const result = await $`cmd /c dnx Palantir --yes ${SOURCE} -- -q ${args}`.nothrow().quiet()
    if (result.exitCode === 0) return
    // Report once. A dead feed otherwise disables notifications silently,
    // which is how the nuget.org block went unnoticed for four months.
    if (notifyFailed) return
    notifyFailed = true
    await client.tui.showToast({
      body: {
        title: "Palantir",
        message: `Notifications disabled: dnx exited ${result.exitCode}`,
        variant: "error",
      },
    })
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
        "--preset", "opencode-idle",
        "-m", "Ready for input",
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
          "--preset", "opencode-error",
          "-m", "Session encountered an error",
          "-b", directory,
        )
      } else if ((event.type as string) === "permission.asked") {
        const props = event.properties as { sessionID: string }
        if (childSessions.has(props.sessionID)) return
        cancelPending()
        await notify(
          "--preset", "opencode-permission",
          "-m", "Action requires your approval",
          "-b", directory,
        )
      } else if ((event.type as string) === "question.asked") {
        const props = event.properties as { sessionID: string }
        if (childSessions.has(props.sessionID)) return
        cancelPending()
        await notify(
          "--preset", "opencode-permission",
          "-m", "OpenCode is asking a question",
          "-b", directory,
        )
      }
    },
  }
}
