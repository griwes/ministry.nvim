---@type mcp.Config
local defaults = {
    socket_prefix = 'nvim_mcp',
    bridge_command = 'socat',
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

