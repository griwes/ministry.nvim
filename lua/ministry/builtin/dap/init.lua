local resources = require('ministry.builtin.dap.resources')
local tools = require('ministry.builtin.dap.tools')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'dap',
        title = 'DAP',
        description = 'Built-in Neovim dap.nvim debugger surfaces.',
        tools = tools.specs(),
        resources = resources.specs(),
        resource_templates = resources.templates(),
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
