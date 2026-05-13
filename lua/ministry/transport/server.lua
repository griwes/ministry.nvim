local config = require('ministry.core.config')
local endpoint = require('ministry.transport.endpoint')
local jsonrpc = require('ministry.transport.http.jsonrpc')
local http_server = require('ministry.transport.http.server')
local protocol_session = require('ministry.protocol.session')

local M = {}

---@type uv_pipe_t?
local listener = nil
---@type uv_pipe_t[]
local clients = {}
---@type table<uv_pipe_t, string>
local client_sessions = {}
---@type table<uv_pipe_t, uv_timer_t>
local client_timers = {}
---@type string?
local listener_socket_path = nil

local function notify_error(message, level)
    vim.schedule(function()
        vim.notify(message, level or vim.log.levels.ERROR)
    end)
end

local function remove_client(target)
    local retained = {}

    for _, client in ipairs(clients) do
        if client ~= target then
            table.insert(retained, client)
        end
    end

    clients = retained
end

local function close_handle(handle)
    if handle == nil or handle:is_closing() then
        return
    end

    handle:close()
end

local function close_client(client)
    remove_client(client)

    local session_id = client_sessions[client]
    client_sessions[client] = nil
    if session_id ~= nil then
        protocol_session.close(session_id)
    end

    local timer = client_timers[client]
    client_timers[client] = nil
    if timer ~= nil and not timer:is_closing() then
        timer:stop()
        timer:close()
    end

    if not client:is_closing() then
        if client.read_stop ~= nil then
            client:read_stop()
        end
        client:close()
    end
end

local function close_listener()
    close_handle(listener)
    listener = nil

    if listener_socket_path ~= nil then
        vim.uv.fs_unlink(listener_socket_path)
        listener_socket_path = nil
    end
end

local function socket_transport_supported()
    local pipe = vim.uv.new_pipe(false)
    local supports_socket = pipe ~= nil and pipe.bind2 ~= nil

    if pipe ~= nil and pipe.close ~= nil then
        local closing = pipe.is_closing ~= nil and pipe:is_closing() or false
        if not closing then
            pipe:close()
        end
    end

    return supports_socket
end

local function write_message(client, message)
    client:write(vim.json.encode(message) .. '\n')
end

local function handle_line(client, session_id, line)
    if line == '' then
        return
    end

    local ok, message = pcall(vim.json.decode, line)

    if not ok then
        write_message(client, {
            jsonrpc = '2.0',
            id = vim.NIL,
            error = {
                code = -32700,
                message = tostring(message),
            },
        })
        return
    end

    jsonrpc.dispatch_jsonrpc_message_async(message, function(response)
        if response ~= nil and not client:is_closing() then
            write_message(client, response)
        end
    end, session_id)
end

local function start_client_read(client, session_id)
    local buffer = ''
    local max_line_bytes = math.max(1, tonumber(config.get().limits.socket_line_bytes) or 1024 * 1024)
    local deadline_armed = false
    local deadline_timer = vim.uv.new_timer()
    client_timers[client] = deadline_timer

    local function disarm_deadline()
        if deadline_timer ~= nil and not deadline_timer:is_closing() and deadline_armed then
            deadline_timer:stop()
        end
        deadline_armed = false
    end

    local function arm_deadline()
        if deadline_timer == nil or deadline_timer:is_closing() or deadline_armed or buffer == '' then
            return
        end

        deadline_armed = true
        local timeout_ms = math.max(1, tonumber(config.get().limits.request_timeout_ms) or 30000)
        deadline_timer:start(timeout_ms, 0, function()
            deadline_armed = false
            if client:is_closing() then
                return
            end

            write_message(client, {
                jsonrpc = '2.0',
                id = vim.NIL,
                error = {
                    code = -32000,
                    message = 'Ministry socket request deadline exceeded',
                },
            })
            close_client(client)
        end)
    end

    client:read_start(function(err, data)
        if err ~= nil then
            notify_error('mcp socket client read error: ' .. tostring(err), vim.log.levels.WARN)
            close_client(client)
            return
        end

        if data == nil then
            close_client(client)
            return
        end

        buffer = buffer .. data

        while true do
            local newline = buffer:find('\n', 1, true)
            if newline == nil then
                break
            end

            local line = buffer:sub(1, newline - 1)
            buffer = buffer:sub(newline + 1)
            disarm_deadline()
            if #line > max_line_bytes then
                write_message(client, {
                    jsonrpc = '2.0',
                    id = vim.NIL,
                    error = {
                        code = -32000,
                        message = 'Ministry socket request exceeds configured line limit',
                    },
                })
                close_client(client)
                return
            end

            handle_line(client, session_id, line)
        end

        if #buffer > max_line_bytes then
            write_message(client, {
                jsonrpc = '2.0',
                id = vim.NIL,
                error = {
                    code = -32000,
                    message = 'Ministry socket request exceeds configured line limit',
                },
            })
            close_client(client)
            return
        end

        arm_deadline()
    end)
end

---@return boolean, string?
function M.start_socket()
    if listener ~= nil and not listener:is_closing() then
        return true, nil
    end

    listener = nil

    local descriptor = endpoint.describe_socket()
    local new_listener = assert(vim.uv.new_pipe(false))
    vim.uv.fs_unlink(descriptor.socket_name)
    local ok, err = new_listener:bind2(descriptor.socket_name, 0)

    if ok ~= 0 then
        close_handle(new_listener)
        return false, tostring(err or ok)
    end

    local listen_ok, listen_err = new_listener:listen(128, function(listen_err_cb)
        if listen_err_cb ~= nil then
            notify_error('mcp socket listener error: ' .. tostring(listen_err_cb))
            return
        end

        local client = assert(vim.uv.new_pipe(false))
        local accept_ok, accept_err = new_listener:accept(client)

        if accept_ok == nil or accept_ok == false then
            notify_error('mcp socket accept error: ' .. tostring(accept_err))
            close_handle(client)
            return
        end

        table.insert(clients, client)
        local session_id = protocol_session.open('socket')
        client_sessions[client] = session_id
        start_client_read(client, session_id)
    end)

    if listen_ok == nil or listen_ok == false then
        close_handle(new_listener)
        return false, tostring(listen_err or 'listen failed')
    end

    listener = new_listener
    listener_socket_path = descriptor.socket_name
    return true, nil
end

---@return boolean, string?
function M.start_http()
    return http_server.start()
end

---@param transport 'socket'|'http'
---@return boolean, string?
function M.start(transport)
    if transport == 'http' then
        local socket_was_running = listener ~= nil and not listener:is_closing()
        if socket_transport_supported() then
            local socket_ok, socket_err = M.start_socket()
            if not socket_ok then
                return false, socket_err
            end
        end

        local http_ok, http_err = M.start_http()
        if not http_ok and not socket_was_running then
            M.stop_socket()
        end
        return http_ok, http_err
    end

    if transport ~= 'socket' then
        return false, string.format('unsupported transport: %s', transport)
    end

    return M.start_socket()
end

local function should_start_http_in_start_all()
    local descriptor = endpoint.describe_http()
    local applied = config.get()
    return applied.transport == 'http' or descriptor.http_port ~= 0
end

---@return boolean, string?
function M.start_all()
    local socket_was_running = listener ~= nil and not listener:is_closing()
    if socket_transport_supported() then
        local ok, err = M.start_socket()

        if not ok then
            return false, err
        end
    end

    if not should_start_http_in_start_all() then
        return true, nil
    end

    local http_ok, http_err = M.start_http()
    if not http_ok and not socket_was_running then
        M.stop_socket()
    end
    return http_ok, http_err
end

function M.stop_socket()
    local active_clients = {}
    for _, client in ipairs(clients) do
        table.insert(active_clients, client)
    end
    for _, client in ipairs(active_clients) do
        close_client(client)
    end

    clients = {}
    client_sessions = {}
    client_timers = {}
    close_listener()
end

function M.stop_http()
    http_server.stop()
end

---@param transport 'socket'|'http'
function M.stop_transport(transport)
    if transport == 'socket' then
        M.stop_socket()
        return
    end

    if transport == 'http' then
        M.stop_http()
        return
    end

    error(string.format('unsupported transport: %s', transport))
end

function M.stop()
    M.stop_http()
    M.stop_socket()
end

---@param transport 'socket'|'http'
---@return boolean
function M.transport_running(transport)
    if transport == 'socket' then
        return listener ~= nil
    end

    if transport == 'http' then
        return http_server.running()
    end

    return false
end

---@return boolean
function M.running()
    return M.transport_running('socket') or M.transport_running('http')
end

---@return table
function M.debug_state()
    return {
        has_listener = listener ~= nil,
        listener_closing = listener ~= nil and listener:is_closing() or false,
        client_count = #clients,
    }
end

return M
