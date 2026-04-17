local resources = require('ministry.builtin.lsp.resources')
local tools = require('ministry.builtin.lsp.tools')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'lsp',
        title = 'LSP',
        description = 'Built-in Neovim LSP information surfaces.',
        tools = tools.specs(),
        resources = resources.specs(),
    }
end

---@return table
function M.tools_tree()
    local flattened = {}

    for _, tool in ipairs(tools.specs()) do
        flattened[tool.name] = vim.tbl_extend('force', {}, tool, { name = nil })
    end

    return flattened
end

return M
