local resources = require('ministry.builtin.quickfix.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'quickfix',
        title = 'Quickfix',
        description = 'Built-in Neovim quickfix and location-list observation surfaces.',
        resources = resources.specs(),
    }
end

return M
