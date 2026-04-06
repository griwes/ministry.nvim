# mcp.nvim

Neovim-native unified MCP substrate with namespaced sub-server registration and one endpoint per session.

## Status

Early development.

## Installation

Example local `lazy.nvim` spec:

```lua
{
    dir = vim.fn.expand("~/projects/neovim-plugin-orchestration/mcp.nvim"),
    name = 'mcp.nvim',
    opts = {},
}
```

## Development

- tests live in `tests/`
- formatting is enforced with Stylua
- Lua modules should carry LuaLS annotations and doc comments
- CI lives in `.github/workflows/ci.yml`
