local context = require('ministry.builtin.overseer.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'tasks://summary',
            name = 'Task Summary',
            description = 'Lightweight summary of generic Overseer task state for the current Neovim session.',
            mime_type = 'application/json',
            handler = function()
                return context.summary()
            end,
        },
    }
end

return M
