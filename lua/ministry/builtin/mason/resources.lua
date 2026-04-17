local context = require('ministry.builtin.mason.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'mason://inventory',
            name = 'Mason Inventory',
            description = 'Structured summary of installed Mason packages available to this Neovim session.',
            mime_type = 'application/json',
            handler = function()
                return context.inventory()
            end,
        },
    }
end

return M
