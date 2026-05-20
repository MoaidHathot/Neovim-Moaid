# mcplense Agent Skill

This folder is an [Agent Skill](https://agentskills.io/) for `mcplense`. Any
skills-aware AI agent (Claude Code, Claude Desktop, Cursor, OpenCode, Goose,
Gemini CLI, OpenHands, Mux, GitHub Copilot, Roo Code, Kiro, and others — see
[the client showcase](https://agentskills.io/clients)) can load this folder to
gain procedural knowledge about how to inspect / scan / audit MCP servers using
the `mcplense` CLI.

## Layout

```
mcplense/
├── SKILL.md           # metadata + main instructions (loaded when the agent activates the skill)
├── references/        # detailed reference docs loaded on demand
│   ├── COMMANDS.md
│   ├── CONFIG.md
│   ├── AUTH.md
│   ├── CHECKS.md
│   └── CLASSIFICATION.md
└── scripts/           # copy-paste-ready helpers the agent (or user) can run
    ├── scan-queries.sh
    └── fleet-drift.sh
```

## Installing into your agent

The skills format is portable; the install path differs per agent. Use the
folder name `mcplense` exactly — the spec requires the parent directory name
to match the `name` field in `SKILL.md`.

### Claude Code

```bash
# Personal (all repos)
mkdir -p ~/.claude/skills
cp -R skills/mcplense ~/.claude/skills/

# Project-local
mkdir -p .claude/skills
cp -R skills/mcplense .claude/skills/
```

Docs: <https://code.claude.com/docs/en/skills>

### Claude (claude.ai / Claude apps)

Upload the `mcplense/` folder as a custom skill in the Skills UI. Docs:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview>

### Cursor

Drop the folder into your repo's `.cursor/skills/` directory. Docs:
<https://cursor.com/docs/context/skills>

### OpenCode

Add the folder under your project's `.opencode/skills/` or your global
`~/.config/opencode/skills/`. Docs: <https://opencode.ai/docs/skills/>

### Goose

```bash
mkdir -p ~/.config/goose/skills
cp -R skills/mcplense ~/.config/goose/skills/
```

Docs: <https://block.github.io/goose/docs/guides/context-engineering/using-skills/>

### Gemini CLI

```bash
mkdir -p ~/.gemini/skills
cp -R skills/mcplense ~/.gemini/skills/
```

Docs: <https://geminicli.com/docs/cli/skills/>

### OpenHands

Add to the `skills/` folder of your OpenHands workspace. Docs:
<https://docs.openhands.dev/overview/skills>

### Other clients

See [agentskills.io/clients](https://agentskills.io/clients) for the complete
list. Most agents accept a folder containing a `SKILL.md` and use the same
discovery mechanism.

## Prerequisites the skill assumes

When the agent activates this skill it expects the `mcplense` CLI to be on
PATH. Install it once with:

```bash
dotnet tool install -g McpLense.Cli
```

The `.NET 10` runtime is required. The skill's reference docs document optional
prerequisites for specific auth flows (Azure CLI for `azure-cli` profiles, a
browser for `interactive-browser` profiles).

## What the skill teaches the agent

Loaded from `SKILL.md` on activation, augmented on demand by the files under
`references/` and `scripts/`:

- Every `mcplense` command + flag, and which command matches which user intent.
- The unified `McpLense.Config.json` schema: `authProfiles[]`, `targets[]`,
  `targetPatterns[]`, `scan.*`. Glob syntax, scope semantics, precedence rules.
- The four auth kinds (`bearer`, `oauth`, `interactive-browser`, `azure-cli`)
  and the auto-pick algorithm (cache-hit-first, then precedence).
- The full per-`IScanCheck` reference: what each check emits, its dependencies,
  its knobs.
- Ready-to-run jq recipes for downstream policy / risk classification.
- Bash helpers (`scan-queries.sh`, `fleet-drift.sh`) for common ops.

## Validating the skill

The reference `skills-ref` validator from [agentskills/agentskills](https://github.com/agentskills/agentskills)
can lint this folder:

```bash
skills-ref validate skills/mcplense
```

## License

This skill ships under the same Unlicense as the McpLense project.
