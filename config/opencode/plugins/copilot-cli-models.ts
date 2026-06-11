import type { Hooks, PluginInput } from "@opencode-ai/plugin"
import type { Model } from "@opencode-ai/sdk/v2"

// GitHub Copilot's `/models` endpoint returns a different (larger) set of models
// depending on the `Copilot-Integration-Id` header. opencode's built-in copilot
// plugin does NOT send this header, so models that are only exposed to the
// official GitHub Copilot CLI (integration id `copilot-developer-cli`) never show
// up in opencode's model picker — e.g. `claude-opus-4.6-1m`, `mai-code-1-flash`.
//
// This plugin re-fetches `/models` with the CLI integration id and returns the
// full picker-enabled set, then injects the same header on chat requests so the
// extra models actually work. It runs after the built-in plugin (config/user
// plugins load last), so its `provider.models` result is authoritative.
//
// It also drops stale catalog entries that the live API no longer surfaces
// (detected via `limit.context === 0` after rebuild) — e.g. `claude-opus-4.7-1m`
// from models.dev whose live successor is `claude-opus-4.7-1m-internal`.
//
// The fetch/build logic below is a plain-TypeScript port of opencode's own
// `packages/opencode/src/plugin/github-copilot/models.ts` so the produced Model
// objects are shaped identically to the built-in ones.

const INTEGRATION_ID = "copilot-developer-cli"
const API_VERSION = "2026-06-01"
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
      default: { cache_price: number; input_price: number; output_price: number }
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

function normalizeDomain(url: string) {
  return url.replace(/^https?:\/\//, "").replace(/\/$/, "")
}

function base(enterpriseUrl?: string) {
  return enterpriseUrl ? `https://copilot-api.${normalizeDomain(enterpriseUrl)}` : "https://api.githubcopilot.com"
}

function usable(item: RawItem): item is SelectableItem {
  return (
    item.policy?.state !== "disabled" &&
    item.capabilities.limits?.max_output_tokens !== undefined &&
    item.capabilities.limits.max_prompt_tokens !== undefined &&
    item.capabilities.supports.tool_calls !== undefined
  )
}

// Matches Anthropic Opus 4.7 and any later version (4.8, 5.x, ...). Mirrors
// `anthropicOpus47OrLater` in opencode's provider/transform.ts so we don't have
// to revisit this when new Opus versions ship. Used to force the
// `display: "summarized"` thinking flag — Opus 4.7+ flipped the API default to
// "omitted", which returns empty thinking blocks unless we override it.
function isAnthropicOpus47OrLater(apiId: string) {
  const m = /opus-(\d+)[.-](\d+)(?:[.@-]|$)|claude-(\d+)[.-](\d+)-opus(?:[.@-]|$)/i.exec(apiId)
  if (!m) return false
  const major = Number(m[1] ?? m[3])
  const minor = Number(m[2] ?? m[4])
  return major > 4 || (major === 4 && minor >= 7)
}

function build(key: string, remote: SelectableItem, url: string, prev?: Model): Model {
  const reasoning =
    !!remote.capabilities.supports.adaptive_thinking ||
    !!remote.capabilities.supports.reasoning_effort?.length ||
    remote.capabilities.supports.max_thinking_budget !== undefined ||
    remote.capabilities.supports.min_thinking_budget !== undefined
  const image =
    (remote.capabilities.supports.vision ?? false) ||
    (remote.capabilities.limits.vision?.supported_media_types ?? []).some((item) => item.startsWith("image/"))

  const isMsgApi = remote.supported_endpoints?.includes("/v1/messages")
  const prices = remote.billing?.token_prices
  // Copilot prices are AIC per billing batch; opencode stores USD per million tokens.
  const usdPerMillion = prices ? 10_000 / prices.batch_size : 0

  const model: Model = {
    id: key,
    providerID: "github-copilot",
    api: {
      id: remote.id,
      url: isMsgApi ? `${url}/v1` : url,
      npm: isMsgApi ? "@ai-sdk/anthropic" : "@ai-sdk/github-copilot",
    },
    status: "active",
    limit: {
      context: remote.capabilities.limits.max_context_window_tokens ?? remote.capabilities.limits.max_prompt_tokens,
      input: remote.capabilities.limits.max_prompt_tokens,
      output: remote.capabilities.limits.max_output_tokens,
    },
    capabilities: {
      temperature: prev?.capabilities.temperature ?? true,
      reasoning: prev?.capabilities.reasoning ?? reasoning,
      attachment: prev?.capabilities.attachment ?? true,
      toolcall: remote.capabilities.supports.tool_calls,
      input: { text: true, audio: false, image, video: false, pdf: false },
      output: { text: true, audio: false, image: false, video: false, pdf: false },
      interleaved: false,
    },
    family: prev?.family ?? remote.capabilities.family,
    name: prev?.name ?? remote.name,
    cost: {
      input: (prices?.default.input_price ?? 0) * usdPerMillion,
      output: (prices?.default.output_price ?? 0) * usdPerMillion,
      cache: {
        read: (prices?.default.cache_price ?? 0) * usdPerMillion,
        write: 0,
      },
    },
    options: prev?.options ?? {},
    headers: prev?.headers ?? {},
    release_date:
      prev?.release_date ??
      (remote.version.startsWith(`${remote.id}-`) ? remote.version.slice(remote.id.length + 1) : remote.version),
  }

  const efforts = remote.capabilities.supports.reasoning_effort
  const variants: NonNullable<Model["variants"]> = {}
  if (!isMsgApi && efforts?.length) {
    efforts.forEach((effort) => {
      variants[effort] = {
        reasoningEffort: effort,
        reasoningSummary: "auto",
        include: ["reasoning.encrypted_content"],
      }
    })
  } else if (efforts?.length && remote.capabilities.supports.adaptive_thinking) {
    efforts.forEach((effort) => {
      variants[effort] = {
        thinking: {
          type: "adaptive",
          ...(isAnthropicOpus47OrLater(model.api.id) ? { display: "summarized" } : {}),
        },
        effort,
      }
    })
  } else if (remote.capabilities.supports.max_thinking_budget) {
    const max = remote.capabilities.supports.max_thinking_budget
    variants["max"] = { thinking: { type: "enabled", budgetTokens: max - 1 } }
    variants["high"] = { thinking: { type: "enabled", budgetTokens: Math.floor(max / 2) } }
  }
  if (Object.keys(variants).length > 0) model.variants = variants

  return model
}

async function fetchModels(baseURL: string, token: string, existing: Record<string, Model>) {
  const res = await fetch(`${baseURL}/models`, {
    headers: {
      Authorization: `Bearer ${token}`,
      "User-Agent": USER_AGENT,
      "X-GitHub-Api-Version": API_VERSION,
      "Copilot-Integration-Id": INTEGRATION_ID,
    },
    signal: AbortSignal.timeout(5_000),
  })
  if (!res.ok) throw new Error(`Failed to fetch copilot models: ${res.status}`)
  const body = (await res.json()) as { data: RawItem[] }

  const remote = new Map<string, SelectableItem>()
  for (const raw of body.data ?? []) {
    if (raw && typeof raw.id === "string" && usable(raw)) remote.set(raw.id, raw)
  }

  const result: Record<string, Model> = { ...existing }
  // prune existing entries no longer advertised by the endpoint
  for (const [key, model] of Object.entries(result)) {
    const m = remote.get(model.api.id)
    if (!m) {
      delete result[key]
      continue
    }
    result[key] = build(key, m, baseURL, model)
  }
  // add new endpoint models (the CLI-only ones the built-in plugin misses)
  for (const [id, m] of remote) {
    if (id in result) continue
    result[id] = build(id, m, baseURL)
  }

  // Drop any entry without a real context window. Catches stale models.dev
  // catalog entries (e.g. `claude-opus-4.7-1m`, ctx=0) that the live API no
  // longer surfaces — the prune loop above already removed them, but
  // downstream config-defined models can re-add them, so this is defensive.
  for (const [key, model] of Object.entries(result)) {
    if (!model.limit?.context) delete result[key]
  }

  const pickerEnabled = new Set([...remote].filter(([, item]) => item.model_picker_enabled).map(([id]) => id))
  return Object.fromEntries(Object.entries(result).filter(([, model]) => pickerEnabled.has(model.api.id)))
}

export default async function CopilotCliModelsPlugin(_input: PluginInput): Promise<Hooks> {
  return {
    provider: {
      id: "github-copilot",
      async models(provider, ctx) {
        if (ctx.auth?.type !== "oauth") return provider.models
        const auth = ctx.auth
        try {
          return await fetchModels(base(auth.enterpriseUrl), auth.refresh, provider.models)
        } catch (error) {
          // Fall back to whatever the built-in plugin already produced.
          console.error("[copilot-cli-models] failed to fetch CLI models:", error)
          return provider.models
        }
      },
    },
    "chat.headers": async (incoming, output) => {
      if (!incoming.model.providerID.includes("github-copilot")) return
      output.headers["Copilot-Integration-Id"] = INTEGRATION_ID
    },
  }
}
