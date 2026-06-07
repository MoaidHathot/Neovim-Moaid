# Setting up Zakira.Exchange

Zakira ships as a .NET CLI with two modes:

- `zakira <command>` - CLI for human use.
- `zakira mcp` - MCP server over stdio for agent use.

This file is for **installing and configuring** the server. For *using*
the tools once it's wired up, see the other reference files.

## Prerequisites

- .NET 10 SDK.
- The ONNX model files - download with
  `./scripts/download-model.ps1` (PowerShell) or
  `./scripts/download-model.sh` (Bash). About 90 MB to
  `src/Zakira.Exchange.Core/Models/`.

Without the model, only `list`, `get`, `delete`, and `categories`
commands work. `create`, `edit`, and `search` need it because they
require embedding.

## Building / running locally

```bash
# Build everything
dotnet build Zakira.Exchange.slnx

# Run the CLI
dotnet run --project src/Zakira.Exchange.Cli -- list

# Run the MCP server (foreground, stdio)
dotnet run --project src/Zakira.Exchange.Cli -- mcp
```

If installed as a global tool, the entry point is just `zakira`.

## MCP client configurations

All clients use stdio transport. Pick the snippet that matches your
client.

### Claude Desktop

In `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "zakira": {
      "type": "stdio",
      "command": "zakira",
      "args": ["mcp", "--database-path", "./memories.db"]
    }
  }
}
```

### VS Code

In `.vscode/mcp.json` (workspace) or user MCP settings:

```json
{
  "servers": {
    "zakira": {
      "type": "stdio",
      "command": "zakira",
      "args": ["mcp"]
    }
  }
}
```

### Cursor

Cursor's MCP config uses the same shape as VS Code:

```json
{
  "servers": {
    "zakira": {
      "type": "stdio",
      "command": "zakira",
      "args": ["mcp", "--database-path", "./memories.db"]
    }
  }
}
```

### Using `dotnet run` (no global install)

When iterating on the server itself, point the command at the project:

```json
{
  "servers": {
    "zakira": {
      "type": "stdio",
      "command": "dotnet",
      "args": [
        "run", "--project", "/abs/path/to/src/Zakira.Exchange.Cli",
        "--", "mcp"
      ]
    }
  }
}
```

## Choosing an access mode

| Mode          | Use when...                                                           |
| ------------- | --------------------------------------------------------------------- |
| `full`        | You trust the agent fully (your own machine, your own database).      |
| `no-delete`   | Agent can manage entries but cannot lose data.                        |
| `append-only` | Agent can record but never rewrite history.                           |
| `read-only`   | Agent should *consult* a curated store but never modify it.           |

Specify with `--access-mode <mode>` or the `ZAKIRA_ACCESS_MODE` env
var. Tools the mode disallows are not registered at all - they don't
appear in the agent's tool list. See `tools.md` for the per-tool
availability matrix.

## Const-category mode

`--category <name>` (or `ZAKIRA_CATEGORY`) locks every operation to one
category and **hides the `category` parameter** from the tool schemas.

Use when:

- The agent should only ever read/write one namespace.
- You want a per-project memory bucket without trusting the agent to
  spell the category correctly each time.

```json
{
  "servers": {
    "zakira-project-a": {
      "type": "stdio",
      "command": "zakira",
      "args": ["mcp", "--category", "project-a", "--db", "./project-a.db"]
    }
  }
}
```

You can run multiple MCP server entries side by side, each scoped to a
different category or database.

## Environment variables

Every flag has an environment-variable equivalent. Useful for client
configs that inject environment variables but don't pass CLI args:

| Variable                 | Equivalent flag           |
| ------------------------ | ------------------------- |
| `ZAKIRA_DATABASE_PATH`   | `--database-path`         |
| `ZAKIRA_ACCESS_MODE`     | `--access-mode`           |
| `ZAKIRA_CATEGORY`        | `--category`              |
| `ZAKIRA_MODEL_PATH`      | `--model-path`            |

CLI flags win over environment variables when both are set.

## Concurrent access

SQLite WAL mode is on by default - multiple processes can read and
write the same database without blocking each other. Common patterns:

- One MCP server per database; one CLI window for ad-hoc queries.
- Per-project databases, each behind its own MCP server entry in the
  client config.
- A shared team database, with each team member's MCP client pointed
  at it.

## Verifying the setup

After wiring up the server:

1. Restart the MCP client so it re-reads the config.
2. Ask the agent to list its tools - confirm at least
   `search_memories`, `get_memory`, and `list_memories` are present.
   If the access mode is `full`, all six should appear.
3. Create a test entry from a separate terminal:

   ```bash
   zakira create test setup-check \
     --data "Zakira is wired up." \
     --author setup-verifier
   ```
4. Have the agent search for it -
   `search_memories(query="setup check")` should find it near the top.
5. Delete it when done (if the agent has `delete_memory`):

   ```bash
   zakira delete test setup-check
   ```

## Where to read more

- Published docs: <https://moaidhathot.github.io/Zakira.Exchange/>
- Source: <https://github.com/MoaidHathot/Zakira.Exchange>
- In-repo: `docs/getting-started.md`, `docs/mcp-server.md`,
  `docs/configuration.md`, `docs/architecture.md`.
