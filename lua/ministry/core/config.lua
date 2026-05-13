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
    limits = {
        http_body_bytes = 4 * 1024 * 1024,
        http_header_bytes = 64 * 1024,
        request_timeout_ms = 30000,
        socket_line_bytes = 1024 * 1024,
    },
    terminal = {
        max_output_bytes = 1024 * 1024,
        max_wait_timeout_ms = 1000,
        wait_timeout_ms = 100,
    },
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
        enabled = true,
        default = 'ask',
        persistence = true,
        path = nil,
        provider = nil,
        providers = { 'legate' },
        reservation_ttl_ms = 30000,
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
