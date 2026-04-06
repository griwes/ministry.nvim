local prompts = require('mcp.builtin.editor.prompts')
local resources = require('mcp.builtin.editor.resources')
local tools = require('mcp.builtin.editor.tools')

local M = {}

---@return mcp.ServerSpec
function M.server_spec()
    return {
        name = 'editor',
        title = 'Editor',
        description = 'Built-in editor-local Neovim context surfaces.',
        tools = tools.specs(),
        resources = resources.specs(),
        prompts = prompts.specs(),
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
