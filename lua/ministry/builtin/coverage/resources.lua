local context = require('ministry.builtin.coverage.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'coverage://summary',
            name = 'Coverage Summary',
            description = 'Structured summary of in-process coverage plugin state for this Neovim session.',
            mime_type = 'application/json',
            handler = function()
                return context.summary()
            end,
        },
    }
end

return M
