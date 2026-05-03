local resources = require('ministry.builtin.git.resources')
local tools = require('ministry.builtin.git.tools')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'git',
        title = 'Git',
        description = 'Built-in Git repository observation surfaces backed by stratum.nvim.',
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
