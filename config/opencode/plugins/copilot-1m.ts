import type { Hooks } from "@opencode-ai/plugin";

export default function (): Hooks {
  return {
    provider: {
      id: "github-copilot",
      async models(provider) {
        for (const id of ["claude-opus-4.6", "claude-opus-4.7"] as const) {
          const base = provider.models[id];
          if (!base) continue;
          const oneMillionID = `${id}-1m`;
          provider.models[oneMillionID] = {
            ...base,
            id: oneMillionID,
            name: `${base.name} (1M)`,
            api: {
              ...base.api,
              id: oneMillionID,
            },
            limit: {
              ...base.limit,
              context: 1000000,
              input: 900000,
              output: 128000,
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
