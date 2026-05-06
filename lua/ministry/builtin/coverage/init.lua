local resources = require('ministry.builtin.coverage.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'coverage',
        title = 'Coverage',
        description = 'Built-in coverage observation surfaces.',
        resources = resources.specs(),
        namespaces = {
            resources = {
                coverage = 'Coverage plugin state for the current session.',
            },
        },
    }
end

return M
