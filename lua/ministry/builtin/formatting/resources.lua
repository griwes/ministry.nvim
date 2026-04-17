local context = require('ministry.builtin.formatting.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'formatting://summary',
            name = 'Formatting Summary',
            description = 'Structured summary of formatter configuration for the current buffer filetype.',
            mime_type = 'application/json',
            handler = function()
                return context.summary()
            end,
        },
    }
end

return M
