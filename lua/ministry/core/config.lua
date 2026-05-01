---@type ministry.Config
local defaults = {
    socket_prefix = 'nvim_mcp',
    bridge_command = 'socat',
    transport = 'socket',
    http_host = '127.0.0.1',
    http_port = 0,
    http_token = nil,
    enable_terminal_tools = false,
    auto_start = true,
    external = {
        enabled = false,
        config = nil,
        workspace = {
            enabled = true,
            look_for = {
                '.mcphub/servers.json',
                '.vscode/mcp.json',
                '.cursor/mcp.json',
            },
            reload_on_dir_changed = false,
        },
        request_timeout_ms = 60000,
    },
    approval = {
        enabled = false,
        default = 'ask',
        persistence = true,
        path = nil,
        provider = nil,
    },
    ui = {
        width = 0.8,
        height = 0.8,
        border = 'rounded',
    },
}

local current = vim.deepcopy(defaults)

local M = {}

---@return ministry.Config
function M.get()
    return current
end

---@param opts? Partial<ministry.Config>
---@return ministry.Config
function M.set(opts)
    current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
    return current
end

---@return ministry.Config
function M.reset()
    current = vim.deepcopy(defaults)
    return current
end

return M
