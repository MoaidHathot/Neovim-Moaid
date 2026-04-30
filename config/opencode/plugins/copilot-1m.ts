import type { Hooks } from "@opencode-ai/plugin";

export default function (): Hooks {
  return {
    provider: {
      id: "github-copilot",
      async models(provider) {
        const opus46 = provider.models["claude-opus-4.6"];
        if (opus46) {
          provider.models["claude-opus-4.6-1m"] = {
            ...opus46,
            id: "claude-opus-4.6-1m",
            name: "Claude Opus 4.6 (1M)",
            api: {
              ...opus46.api,
              id: "claude-opus-4.6-1m",
              url: "https://api.githubcopilot.com",
              npm: "@ai-sdk/github-copilot",
            },
            limit: {
              ...opus46.limit,
              context: 1000000,
              input: 900000,
            },
          };
        }

        const opus47 = provider.models["claude-opus-4.7"];
        if (opus47) {
          provider.models["claude-opus-4.7-1m"] = {
            ...opus47,
            id: "claude-opus-4.7-1m",
            name: "Claude Opus 4.7 (1M)",
            api: {
              ...opus47.api,
              id: "claude-opus-4.7-1m-internal",
              url: "https://api.githubcopilot.com",
              npm: "@ai-sdk/github-copilot",
            },
            headers: {
              ...opus47.headers,
              "anthropic-beta": "context-1m-2025-08-07",
            },
            limit: {
              ...opus47.limit,
              context: 1000000,
              input: 900000,
            },
          };
        }

        return provider.models;
      },
    },
    "chat.headers": async (incoming, output) => {
      if (!incoming.model.providerID.includes("github-copilot")) return;
      output.headers["Copilot-Integration-Id"] = "copilot-developer-cli";
    },
  };
}
