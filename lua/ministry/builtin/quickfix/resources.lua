local context = require('ministry.builtin.quickfix.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'quickfix://summary',
            name = 'Quickfix Summary',
            description = 'Structured quickfix list state for the current Neovim session.',
            mime_type = 'application/json',
            handler = function()
                return context.quickfix_summary()
            end,
        },
        {
            uri = 'location-list://current',
            name = 'Location List Summary',
            description = 'Structured location-list state for the current Neovim window.',
            mime_type = 'application/json',
            handler = function()
                return context.location_list_summary()
            end,
        },
    }
end

return M
