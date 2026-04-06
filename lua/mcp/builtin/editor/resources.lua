local context = require('mcp.builtin.editor.context')

local M = {}

---@return mcp.ResourceSpec[]
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
    }
end

return M
