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
        namespaces = {
            resources = {
                dap = 'Debugger session state backed by dap.nvim.',
            },
            resource_templates = {
                dap = 'Parameterized debugger resources backed by dap.nvim.',
                ['dap/scopes'] = 'Debugger scopes for a concrete stack frame.',
                ['dap/stack'] = 'Debugger stack frames for a concrete thread.',
                ['dap/variables'] = 'Debugger variables for a concrete variablesReference.',
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
