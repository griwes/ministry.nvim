local resources = require('ministry.builtin.mason.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'mason',
        title = 'Mason',
        description = 'Built-in Mason inventory observation surfaces.',
        resources = resources.specs(),
    }
end

return M
