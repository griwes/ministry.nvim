local resources = require('ministry.builtin.lint.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'lint',
        title = 'Lint',
        description = 'Built-in linter configuration observation surfaces.',
        resources = resources.specs(),
        namespaces = {
            resources = {
                lint = 'Linter configuration and running linter state.',
            },
        },
    }
end

return M
