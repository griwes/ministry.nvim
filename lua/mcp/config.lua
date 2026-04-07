---@type mcp.Config
local defaults = {
    socket_prefix = 'nvim_mcp',
    bridge_command = 'socat',
    transport = 'socket',
    http_host = '127.0.0.1',
    http_port = 0,
    http_token = nil,
    enable_terminal_tools = false,
    auto_start = true,
}

local current = vim.deepcopy(defaults)

local M = {}

---@return mcp.Config
function M.get()
    return current
end

---@param opts? Partial<mcp.Config>
---@return mcp.Config
function M.set(opts)
    current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
    return current
end

---@return mcp.Config
function M.reset()
    current = vim.deepcopy(defaults)
    return current
end

return M
