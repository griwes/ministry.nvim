local config = require('mcp.config')

local M = {}

---@type string?
local cached_socket_name = nil

local function format_http_host(host)
    if host ~= nil and host:find(':', 1, true) ~= nil and not host:match('^%[.*%]$') then
        return '[' .. host .. ']'
    end

    return host
end

local function session_socket_name()
    if cached_socket_name ~= nil then
        return cached_socket_name
    end

    local prefix = config.get().socket_prefix
    local pid = vim.fn.getpid()
    local hrtime = vim.loop.hrtime()
    cached_socket_name = string.format('%s_%d_%d', prefix, pid, hrtime)
    return cached_socket_name
end

---@return mcp.EndpointDescriptor
function M.describe_socket()
    local socket_name = session_socket_name()
    local bridge_command = config.get().bridge_command
    local args = { '-', 'ABSTRACT-CONNECT:' .. socket_name }

    return {
        transport = 'socket',
        socket_kind = 'abstract',
        socket_name = socket_name,
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
---@return mcp.EndpointDescriptor
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

---@return mcp.EndpointDescriptor
function M.describe()
    if config.get().transport == 'http' then
        local http_server = require('mcp.http_server')
        local host, port = http_server.bound_address()
        if host ~= nil and port ~= nil then
            return M.describe_http(host, port)
        end
        return M.describe_http()
    end

    return M.describe_socket()
end

function M.reset()
    cached_socket_name = nil
end

return M
