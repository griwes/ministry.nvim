local config = require('mcp.config')

local M = {}

local function session_socket_name()
    local prefix = config.get().socket_prefix
    local pid = vim.fn.getpid()
    return string.format('%s_%d', prefix, pid)
end

---@return mcp.EndpointDescriptor
function M.describe()
    local socket_name = session_socket_name()
    local bridge_command = config.get().bridge_command

    return {
        transport = 'socket',
        socket_kind = 'abstract',
        socket_name = socket_name,
        command = bridge_command,
        args = { '-', 'ABSTRACT-CONNECT:' .. socket_name },
        env = {},
    }
end

return M

