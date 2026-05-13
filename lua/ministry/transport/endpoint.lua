local config = require('ministry.core.config')

local M = {}

---@type string?
local cached_socket_path = nil

local SOCKET_DIR_MODE = 448

---@return string
local function socket_runtime_dir()
    local runtime_dir = vim.fs.joinpath(vim.fn.stdpath('run'), 'ministry.nvim')
    local stat = vim.uv.fs_lstat(runtime_dir)

    if stat ~= nil and stat.type ~= 'directory' then
        error(string.format('Ministry socket runtime path is not a directory: %s', runtime_dir))
    end

    if stat == nil then
        local created = vim.fn.mkdir(runtime_dir, 'p', SOCKET_DIR_MODE)
        stat = vim.uv.fs_lstat(runtime_dir)
        if created == 0 and (stat == nil or stat.type ~= 'directory') then
            error(string.format('Failed to create Ministry socket runtime directory: %s', runtime_dir))
        end
    end

    local chmod_ok, chmod_err = vim.uv.fs_chmod(runtime_dir, SOCKET_DIR_MODE)
    if not chmod_ok then
        error(string.format('Failed to secure Ministry socket runtime directory: %s', tostring(chmod_err)))
    end

    stat = vim.uv.fs_stat(runtime_dir)
    if stat == nil or stat.type ~= 'directory' or stat.mode % 512 ~= SOCKET_DIR_MODE then
        error(string.format('Ministry socket runtime directory must have mode 0700: %s', runtime_dir))
    end

    local uid = vim.uv.os_getuid and vim.uv.os_getuid() or nil
    if uid ~= nil and stat.uid ~= nil and stat.uid ~= uid then
        error(string.format('Ministry socket runtime directory is not owned by the current user: %s', runtime_dir))
    end

    return runtime_dir
end

local function format_http_host(host)
    if host ~= nil and host:find(':', 1, true) ~= nil and not host:match('^%[.*%]$') then
        return '[' .. host .. ']'
    end

    return host
end

local function session_socket_path()
    if cached_socket_path ~= nil then
        return cached_socket_path
    end

    local prefix = tostring(config.get().socket_prefix or 'nvim_mcp'):gsub('[^%w_.-]', '_'):sub(1, 32)
    if prefix == '' then
        prefix = 'nvim_mcp'
    end
    local pid = vim.fn.getpid()
    local hrtime = vim.loop.hrtime()
    local filename = string.format('%s_%d_%d.sock', prefix, pid, hrtime)
    cached_socket_path = vim.fs.joinpath(socket_runtime_dir(), filename)
    return cached_socket_path
end

---@return ministry.EndpointDescriptor
function M.describe_socket()
    local socket_path = session_socket_path()
    local bridge_command = config.get().bridge_command
    local args = { '-', 'UNIX-CONNECT:' .. socket_path }

    return {
        transport = 'socket',
        socket_kind = 'filesystem',
        socket_name = socket_path,
        command = bridge_command,
        args = args,
        env = {},
        invocation = {
            command = bridge_command,
            args = args,
            env = {},
        },
    }
end

---@param host? string
---@param port? integer
---@return ministry.EndpointDescriptor
function M.describe_http(host, port)
    local applied = config.get()
    local http_host = host or applied.http_host
    local configured_port = applied.http_port
    local http_port = port or configured_port
    local http_token = applied.http_token
    local url = nil
    local invocation = {}

    if http_port ~= 0 then
        url = string.format('http://%s:%d/mcp', format_http_host(http_host), http_port)
        invocation.url = url
        if type(http_token) == 'string' and http_token ~= '' then
            invocation.headers = {
                Authorization = 'Bearer ' .. http_token,
            }
        end
    end

    return {
        transport = 'http',
        http_host = http_host,
        http_port = http_port,
        http_token = http_token,
        url = url,
        command = '',
        args = {},
        env = {},
        invocation = invocation,
    }
end

---@return ministry.EndpointDescriptor
function M.describe()
    if config.get().transport == 'http' then
        local http_server = require('ministry.transport.http.server')
        local host, port = http_server.bound_address()
        if host ~= nil and port ~= nil then
            return M.describe_http(host, port)
        end
        return M.describe_http()
    end

    return M.describe_socket()
end

function M.reset()
    cached_socket_path = nil
end

return M
