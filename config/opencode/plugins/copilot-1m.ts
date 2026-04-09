import type { Hooks } from "@opencode-ai/plugin";

export default function (): Hooks {
  return {
    provider: {
      id: "github-copilot",
      async models(provider) {
        const base = provider.models["claude-opus-4.6"];
        if (!base) return provider.models;
        provider.models["claude-opus-4.6-1m"] = {
          ...base,
          id: "claude-opus-4.6-1m",
          name: "Claude Opus 4.6 (1M)",
          api: {
            ...base.api,
            id: "claude-opus-4.6-1m",
          },
          limit: {
            ...base.limit,
            context: 1000000,
            input: 900000,
          },
        };
        return provider.models;
      },
    },
    "chat.headers": async (incoming, output) => {
      if (!incoming.model.providerID.includes("github-copilot")) return;
      output.headers["Copilot-Integration-Id"] = "copilot-developer-cli";
    },
  };
}
