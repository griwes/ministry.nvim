local resources = require('ministry.builtin.quickfix.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'quickfix',
        title = 'Quickfix',
        description = 'Built-in Neovim quickfix and location-list observation surfaces.',
        resources = resources.specs(),
        namespaces = {
            resources = {
                ['location-list'] = 'Current-window location-list state.',
                quickfix = 'Current quickfix list state.',
            },
        },
    }
end

return M
