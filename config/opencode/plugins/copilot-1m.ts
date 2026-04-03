import type { Hooks } from "@opencode-ai/plugin";

export default function (): Hooks {
  return {
    "chat.headers": async (incoming, output) => {
      if (!incoming.model.providerID.includes("github-copilot")) return;
      output.headers["Copilot-Integration-Id"] = "copilot-developer-cli";
    },
  };
}
