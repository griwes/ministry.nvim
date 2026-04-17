local context = require('ministry.builtin.navigation.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'navigation://marks',
            name = 'Navigation Marks',
            description = 'Structured summary of builtin Neovim mark anchors.',
            mime_type = 'application/json',
            handler = function()
                return context.marks_summary()
            end,
        },
    }
end

return M
