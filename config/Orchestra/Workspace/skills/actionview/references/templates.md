# Templates

A template is a per-`type` normalization spec. When an incoming entry's `type` matches a registered template, ActionView applies the template's defaults, aliases, and validation rules during ingestion.

**Templates do not contain commands.** They describe the shape of entries of a given type — the producing tool always supplies the actual `command` for each `EntryAction`.

## When to register a template

- You produce many entries of the same type and want consistent defaults (severity, icon, base tags).
- Your producers send slightly different key names (`message` vs `body`, `summary` vs `description`) and you want them aliased to a canonical key.
- You want the dashboard to flag entries missing expected content blocks (e.g., a `pr-review` should always have a `keyValue` block of PR details).

If you only produce one-off notifications, skip templates entirely.

## Template shape

```json
{
  "type": "pr-review",
  "description": "GitHub pull request reviews",
  "defaults": {
    "severity": "medium",
    "icon": "git-pull-request",
    "tags": ["code-review"]
  },
  "contentTemplate": [
    {
      "type": "keyValue",
      "label": "Pull Request Details",
      "required": true,
      "requiredKeys": ["Repository", "Branch", "Author"],
      "keyAliases": { "Repo": "Repository", "By": "Author" }
    },
    {
      "type": "section",
      "title": "Findings",
      "titleAliases": ["Issues", "Concerns"]
    }
  ],
  "expectedActions": [
    { "label": "Approve PR", "style": "success" },
    { "label": "Request Changes", "style": "danger" }
  ]
}
```

| Field | Notes |
|-------|-------|
| `type` | Must match the `type` of incoming entries. |
| `description` | Free-form. |
| `defaults` | Applied to entries that omit these fields. |
| `contentTemplate[]` | Expected content blocks — used to validate and to alias keys. Order matters. |
| `expectedActions[]` | Documentation only — listed in the UI as "expected actions" without commands. |

## Registering a template

### Via file
Drop a JSON file in `data/templates/` named `<type>.json`. ActionView discovers and registers on next scan.

### Via API
`POST /api/templates` with the template JSON body.

### Via MCP
`register_template(templateJson)` — JSON string argument.

### Via CLI
```bash
actionview template register ./my-template.json
```

## Listing & removing

- `GET /api/templates` / `actionview template list` / MCP `list_templates`
- `GET /api/templates/{type}` / `actionview template show <type>` / MCP `get_template`
- `DELETE /api/templates/{type}` / `actionview template remove <type>` / MCP `remove_template`

## Auto-discovery

ActionView records auto-discovered template types in `data/templates/.auto-discovered.json`. Inspect it via `GET /api/templates/auto-discovered`.

## Behavior on mismatch

If an incoming entry references a `type` with no template, it's accepted as-is. If a template exists and the entry violates `requiredKeys`, the entry is still ingested but flagged in `errors/`. Templates are advisory, not blocking — the goal is normalization, not gatekeeping.

## When you (an AI agent) should NOT register a template

- For one-off entry types you'll only use once.
- When the user hasn't asked for it. Templates are a setup-time concern; don't proactively register them.
