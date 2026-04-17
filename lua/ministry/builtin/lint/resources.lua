local context = require('ministry.builtin.lint.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'lint://summary',
            name = 'Lint Summary',
            description = 'Structured summary of linter configuration and running linter state for the current buffer filetype.',
            mime_type = 'application/json',
            handler = function()
                return context.summary()
            end,
        },
    }
end

return M
