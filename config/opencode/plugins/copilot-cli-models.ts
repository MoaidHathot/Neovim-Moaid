// OpenCode 2 server plugin (ported from the V1 `provider.models` + `chat.headers` hooks).
//
// GitHub Copilot's `/models` endpoint returns a different (larger) set of models
// depending on the `Copilot-Integration-Id` header. OpenCode's built-in Copilot plugin
// (`opencode.provider.github.copilot`) does NOT send this header, so models that are
// only exposed to the official GitHub Copilot CLI (integration id
// `copilot-developer-cli`) never show up in the model picker — e.g.
// `claude-opus-4.6-1m`, `mai-code-1-flash`.
//
// This plugin re-fetches `/models` with the CLI integration id and publishes the full
// picker-enabled set for the `github-copilot` provider, then injects the same header
// on every model request to that provider so the extra models actually work. User
// plugins register after the built-in ones, so this provider transform runs last and
// its inventory is authoritative; if the fetch fails the built-in inventory stands.
//
// The model-building logic is a plain-TypeScript port of OpenCode's own
// `packages/core/src/github-copilot/models.ts` so the produced Model.Info objects are
// shaped identically to the built-in ones (V2 shape: `modelID`, `package`, `settings`,
// `capabilities.input[]`, `cost[]` tiers, `variants[]`).
import { Model, Plugin, Provider } from "@opencode/plugin"

type ConnectionInfo = NonNullable<Awaited<ReturnType<Plugin.Context["integration"]["connection"]["active"]>>>

const PROVIDER_ID = "github-copilot"
const INTEGRATION_ID = "copilot-developer-cli"
const API_VERSION = "2026-08-01"
const USER_AGENT = "GitHubCopilotCLI/opencode-plugin"

type RawItem = {
  model_picker_enabled: boolean
  id: string
  name: string
  version: string
  supported_endpoints?: string[]
  policy?: { state?: string }
  billing?: {
    token_prices?: {
      batch_size: number
      default: {
        // API version 2026-08-01 renamed cache_price to cache_read_price.
        cache_price?: number
        cache_read_price?: number
        input_price: number
        output_price: number
      }
    }
  }
  capabilities: {
    family: string
    limits?: {
      max_context_window_tokens?: number
      max_output_tokens?: number
      max_prompt_tokens?: number
      vision?: { supported_media_types: string[] }
    }
    supports: {
      adaptive_thinking?: boolean
      max_thinking_budget?: number
      min_thinking_budget?: number
      reasoning_effort?: string[]
      streaming?: boolean
      structured_outputs?: boolean
      tool_calls?: boolean
      vision?: boolean
    }
  }
}

type SelectableItem = RawItem & {
  capabilities: RawItem["capabilities"] & {
    limits: NonNullable<RawItem["capabilities"]["limits"]> & {
      max_output_tokens: number
      max_prompt_tokens: number
    }
    supports: RawItem["capabilities"]["supports"] & { tool_calls: boolean }
  }
}

type Snapshot = ReadonlyMap<string, SelectableItem>
type Usd = Model.Info["cost"][number]["input"]

const usd = (value: number) => value as Usd

function normalizeDomain(url: string) {
  return url.replace(/^https?:\/\//, "").replace(/\/$/, "")
}

function defaultBaseURL(enterprise?: string) {
  return enterprise ? `https://copilot-api.${normalizeDomain(enterprise)}` : "https://api.githubcopilot.com"
}

// Mirrors `copilotBaseURL` in core's github-copilot plugin: an explicit API endpoint
// discovered at login wins, then an enterprise domain, then the public endpoint.
function baseURL(metadata?: Readonly<Record<string, unknown>>) {
  const endpoint = metadata?.apiEndpoint
  if (typeof endpoint === "string" && endpoint) return endpoint.replace(/\/+$/, "")
  const enterprise = metadata?.enterpriseUrl
  return defaultBaseURL(typeof enterprise === "string" ? enterprise : undefined)
}

function usable(item: RawItem): item is SelectableItem {
  return (
    item.policy?.state !== "disabled" &&
    item.capabilities.limits?.max_output_tokens !== undefined &&
    item.capabilities.limits.max_prompt_tokens !== undefined &&
    item.capabilities.supports.tool_calls !== undefined
  )
}

function variants(remote: SelectableItem, messages: boolean): Model.Info["variants"] {
  const efforts = remote.capabilities.supports.reasoning_effort ?? []
  if (!messages && efforts.length) {
    return efforts.map((effort) => ({
      id: Model.VariantID.make(effort),
      settings: {
        reasoningEffort: effort,
        reasoningSummary: "auto",
        include: ["reasoning.encrypted_content"],
      },
    }))
  }
  if (efforts.length && remote.capabilities.supports.adaptive_thinking) {
    return efforts.map((effort) => ({
      id: Model.VariantID.make(effort),
      settings: {
        thinking: { type: "adaptive", display: "summarized" },
        effort,
      },
    }))
  }
  const max = remote.capabilities.supports.max_thinking_budget
  if (max === undefined) return []
  return [
    { id: Model.VariantID.make("max"), settings: { thinking: { type: "enabled", budgetTokens: max - 1 } } },
    { id: Model.VariantID.make("high"), settings: { thinking: { type: "enabled", budgetTokens: Math.floor(max / 2) } } },
  ]
}

function build(key: string, remote: SelectableItem, url: string, previous?: Model.Info): Model.Info {
  const providerID = Provider.ID.make(PROVIDER_ID)
  const id = Model.ID.make(key)
  const messages = remote.supported_endpoints?.includes("/v1/messages") ?? false
  const endpoint = messages
    ? "messages"
    : remote.supported_endpoints?.includes("/responses")
      ? "responses"
      : remote.supported_endpoints?.includes("/chat/completions")
        ? "chat"
        : undefined
  const image =
    (remote.capabilities.supports.vision ?? false) ||
    (remote.capabilities.limits.vision?.supported_media_types ?? []).some((item) => item.startsWith("image/"))
  const pdf =
    (remote.capabilities.supports.vision ?? false) &&
    (remote.capabilities.limits.vision?.supported_media_types.includes("application/pdf") ?? false)
  const input = ["text"]
  if (image) input.push("image")
  if (pdf) input.push("pdf")
  const prices = remote.billing?.token_prices
  // Copilot reports AIC per billing batch; OpenCode stores USD per million tokens.
  const usdPerMillion = prices && prices.batch_size > 0 ? 10_000 / prices.batch_size : 0
  const version = remote.version.startsWith(`${remote.id}-`)
    ? remote.version.slice(remote.id.length + 1)
    : remote.version
  const released = previous?.time.released || Date.parse(version)

  return {
    ...Model.Info.default(providerID, id),
    id,
    modelID: Model.ID.make(remote.id),
    providerID,
    family: previous?.family ?? Model.Family.make(remote.capabilities.family),
    name: previous?.name ?? remote.name,
    package: messages ? "@opencode/ai/providers/anthropic" : "aisdk:@ai-sdk/github-copilot",
    settings: {
      ...previous?.settings,
      baseURL: messages ? `${url}/v1` : url,
      ...(endpoint ? { endpoint } : {}),
    },
    headers: previous?.headers,
    body: previous?.body,
    capabilities: {
      tools: remote.capabilities.supports.tool_calls,
      input,
      output: ["text"],
    },
    variants: variants(remote, messages),
    time: { released: Number.isFinite(released) ? released : 0 },
    cost: [
      {
        input: usd((prices?.default.input_price ?? 0) * usdPerMillion),
        output: usd((prices?.default.output_price ?? 0) * usdPerMillion),
        cache: {
          read: usd((prices?.default.cache_read_price ?? prices?.default.cache_price ?? 0) * usdPerMillion),
          write: usd(0),
        },
      },
    ],
    status: "active",
    enabled: remote.model_picker_enabled,
    limit: {
      context: remote.capabilities.limits.max_context_window_tokens ?? remote.capabilities.limits.max_prompt_tokens,
      input: remote.capabilities.limits.max_prompt_tokens,
      output: remote.capabilities.limits.max_output_tokens,
    },
  }
}

/** Combine remote facts with the existing source definitions (aliases, local metadata). */
function derive(url: string, remote: Snapshot, existing: readonly Model.Info[]) {
  const result = new Map(existing.map((model) => [model.id as string, model]))
  // Keep aliases and local metadata, but only when their advertised API model still
  // exists. Drops stale catalog entries (e.g. models.dev ids the live API retired).
  for (const [id, model] of result) {
    const current = remote.get(model.modelID)
    if (!current) {
      result.delete(id)
      continue
    }
    result.set(id, build(id, current, url, model))
  }
  // Add endpoint models the built-in plugin never saw (the CLI-only ones).
  for (const [id, item] of remote) {
    if (result.has(id)) continue
    result.set(id, build(id, item, url))
  }
  // Defensive: never publish a model without a real context window.
  for (const [id, model] of result) {
    if (!model.limit.context) result.delete(id)
  }
  return Array.from(result.values())
}

async function fetchSnapshot(url: string, token: string): Promise<Snapshot> {
  const res = await fetch(`${url}/models`, {
    headers: {
      Authorization: `Bearer ${token}`,
      "User-Agent": USER_AGENT,
      "X-GitHub-Api-Version": API_VERSION,
      "Copilot-Integration-Id": INTEGRATION_ID,
    },
    signal: AbortSignal.timeout(5_000),
  })
  if (!res.ok) throw new Error(`Failed to fetch Copilot models: ${res.status}`)
  const body = (await res.json()) as { data?: RawItem[] }
  const remote = new Map<string, SelectableItem>()
  for (const raw of body.data ?? []) {
    if (raw && typeof raw.id === "string" && usable(raw)) remote.set(raw.id, raw)
  }
  return remote
}

export default Plugin.define({
  id: "moaid.copilot-cli-models",
  async setup(ctx) {
    const loaded: { url?: string; snapshot?: Snapshot; connection?: ConnectionInfo } = {}
    let loading: Promise<void> | undefined

    const load = async () => {
      const connection = await ctx.integration.connection.active(PROVIDER_ID)
      const credential = connection
        ? await ctx.integration.connection.resolve(connection).catch(() => undefined)
        : undefined
      if (credential?.type !== "oauth") {
        loaded.url = undefined
        loaded.snapshot = undefined
        loaded.connection = undefined
        return
      }
      const url = baseURL(credential.metadata)
      try {
        // The GitHub OAuth token is the `refresh` field; Copilot exchanges it per request.
        const snapshot = await fetchSnapshot(url, credential.refresh)
        loaded.url = url
        loaded.snapshot = snapshot
        loaded.connection = connection
      } catch (error) {
        // Fall back to whatever the built-in plugin already produced.
        console.error("[copilot-cli-models] failed to fetch CLI models:", error)
        loaded.snapshot = undefined
      }
    }

    const refresh = () => {
      if (!loading) {
        loading = load()
          .then(() => ctx.provider.reload())
          .catch((error) => console.error("[copilot-cli-models] refresh failed:", error))
          .finally(() => {
            loading = undefined
          })
      }
      return loading
    }

    await load()

    await ctx.provider.transform((editor) => {
      const item = editor.get(PROVIDER_ID)
      if (!item) return
      const info = {
        ...item.provider,
        headers: { ...item.provider.headers, "Copilot-Integration-Id": INTEGRATION_ID },
      }
      if (!loaded.snapshot || !loaded.url) {
        // Still advertise the CLI integration so the built-in plugin's next `/models`
        // sync (it merges provider headers) sees the same catalog we would.
        editor.update(PROVIDER_ID, (provider) => {
          provider.headers = info.headers
        })
        return
      }
      editor.add({
        info,
        models: derive(loaded.url, loaded.snapshot, Array.from(item.models.values())),
        sourceConnection: loaded.connection,
      })
    })

    // Make the CLI-only models actually work: every request to the provider carries
    // the same integration id the catalog was fetched with (V1 `chat.headers`).
    await ctx.session.hook(
      "model.request",
      (event) => {
        if (!event.model.providerID.includes(PROVIDER_ID)) return
        event.headers["Copilot-Integration-Id"] = INTEGRATION_ID
      },
      { providerID: PROVIDER_ID },
    )

    // Re-sync when the Copilot login changes (new account, logout, first login).
    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          if (event.type === "credential.switched" && event.data.integrationID !== PROVIDER_ID) continue
          if (event.type !== "credential.switched" && event.type !== "credential.updated") continue
          await refresh()
        }
      } catch (error) {
        if (!controller.signal.aborted) console.error("[copilot-cli-models] event stream ended:", error)
      }
    })()

    return () => controller.abort()
  },
})
