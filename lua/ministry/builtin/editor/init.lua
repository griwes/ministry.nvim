local prompts = require('ministry.builtin.editor.prompts')
local resources = require('ministry.builtin.editor.resources')
local tools = require('ministry.builtin.editor.tools')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'editor',
        title = 'Editor',
        description = 'Built-in editor-local Neovim context surfaces.',
        tools = tools.specs(),
        resources = resources.specs(),
        prompts = prompts.specs(),
        namespaces = {
            resources = {
                buffers = 'Current Neovim buffer inventory.',
                workspace = 'Editor and workspace summary for the current Neovim session.',
            },
        },
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
