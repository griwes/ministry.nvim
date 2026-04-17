local context = require('ministry.builtin.lsp.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'lsp://summary',
            name = 'LSP Summary',
            description = 'Lightweight summary of active Neovim LSP clients and current-buffer LSP state.',
            mime_type = 'application/json',
            handler = function()
                return context.summary()
            end,
        },
    }
end

return M
