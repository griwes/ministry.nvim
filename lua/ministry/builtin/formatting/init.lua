local resources = require('ministry.builtin.formatting.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'formatting',
        title = 'Formatting',
        description = 'Built-in formatter configuration observation surfaces.',
        resources = resources.specs(),
        namespaces = {
            resources = {
                formatting = 'Formatter configuration for the current buffer filetype.',
            },
        },
    }
end

return M
