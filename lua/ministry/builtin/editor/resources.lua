local context = require('ministry.builtin.editor.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'buffers://list',
            name = 'Buffer List',
            description = 'Current Neovim buffer inventory with stable buffer ids.',
            mime_type = 'application/json',
            handler = function()
                return {
                    buffers = context.list_buffers(),
                }
            end,
        },
        {
            uri = 'workspace://summary',
            name = 'Workspace Summary',
            description = 'Lightweight editor and workspace summary for the current Neovim session.',
            mime_type = 'application/json',
            handler = function()
                return context.workspace_summary()
            end,
        },
    }
end

return M
