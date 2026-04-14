# Ministry

Neovim-native unified MCP substrate with namespaced sub-server registration and one endpoint per continuity.

## Status

Early development.

## Installation

Example local `lazy.nvim` spec:

```lua
{
    dir = vim.fn.expand("~/projects/neovim-plugin-orchestration/ministry.nvim"),
    name = 'ministry.nvim',
    opts = {},
}
```

## Development

- tests live in `tests/`
- formatting is enforced with Stylua
- Lua modules should carry LuaLS annotations and doc comments
- CI lives in `.github/workflows/ci.yml`

## Built-in MCP surface

- `ministry.nvim` registers a single built-in logical server named `neovim`
- built-in tools are grouped under nested subtrees; `editor/...` is always enabled and `terminal/...` is opt-in via `enable_terminal_tools = true`
- the advertised MCP tool names therefore look like `neovim/editor/list_buffers` and, when enabled, `neovim/terminal/create`
- editor tools are identifier-first:
  - in-editor buffer operations target explicit `bufnr` values via `neovim/editor/list_buffers`, `neovim/editor/read_buffer`, `neovim/editor/diff_buffer`, `neovim/editor/write_buffer`, and `neovim/editor/apply_diff_buffer`
  - disk-backed operations target explicit file paths via `neovim/editor/diff_file`, `neovim/editor/write_file`, and `neovim/editor/apply_diff_file`
  - current-buffer operations are also exposed via `neovim/editor/diff_current_buffer`, `neovim/editor/write_current_buffer`, and `neovim/editor/apply_diff_current_buffer`
- built-in editor surfaces do not expose current-buffer resources or prompts
- built-in editor resources currently include:
  - `neovim/buffers://list`
  - `neovim/workspace://summary` for lightweight session-global editor/workspace metadata
- built-in terminal resources currently include:
  - `neovim/terminals://list` for lightweight session-global Ministry-owned terminal runtime summaries
  - Ministry also provides generic per-list data-provider hooks for buffer and terminal inventories, so plugins such as `terminalia.nvim` can compute lightweight per-item metadata fresh when the list is read without making the list contract vendor-specific
  - a listed terminal can therefore include a lightweight `terminalia_context_stack` when that specific Ministry terminal has been associated with a Terminalia-owned creation context and Terminalia's provider callback returns stack data for that item
- the HTTP endpoint returns `204 No Content` with an empty body for JSON-RPC notifications, including notification-only batches
- HTTP transport requires `Authorization: Bearer <token>` on application requests; browser CORS preflight `OPTIONS` requests are allowed without auth, while non-preflight `OPTIONS` requests still require the bearer token when `http_token` is set

- terminal tools execute host commands via Neovim and are disabled by default for safety
