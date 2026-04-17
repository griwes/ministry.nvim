local resources = require('ministry.builtin.overseer.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'tasks',
        title = 'Tasks',
        description = 'Built-in generic Overseer task observation surfaces.',
        resources = resources.specs(),
    }
end

return M
