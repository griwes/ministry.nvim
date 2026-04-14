local config = require('ministry.core.config')
local cors = require('ministry.transport.http.cors')
local http_handler = require('ministry.transport.http.handler')
local http_jsonrpc = require('ministry.transport.http.jsonrpc')
local negotiation = require('ministry.transport.http.negotiation')
local http_request = require('ministry.transport.http.request')
local http_reader = require('ministry.transport.http.reader')
local http_response = require('ministry.transport.http.response')
local http_utils = require('ministry.transport.http.utils')
local endpoint = require('ministry.transport.endpoint')

local function notify_error(message, level)
    vim.schedule(function()
        vim.notify(message, level or vim.log.levels.ERROR)
    end)
end

local M = {}

---@type uv_tcp_t?
local server = nil
---@type string?
local bound_host = nil
---@type integer?
local bound_port = nil
---@type string?
local requested_host = nil
---@type integer?
local requested_port = nil
---@type string?
local startup_error = nil
---@type boolean
local startup_pending = false
---@type uv_tcp_t[]
local clients = {}
---@type uv_tcp_t[]
local pending_clients = {}
local session_http_token = nil

local function has_session_http_token()
    return type(session_http_token) == 'string' and vim.trim(session_http_token) ~= ''
end

local function deepcopy(value)
    return vim.deepcopy(value)
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

local function close_client(client)
    remove_client(client)

    if not client:is_closing() then
        if client.read_stop ~= nil then
            client:read_stop()
        end
        client:close()
    end
end

local function send_response(client, status, body, headers, keep_alive, http_version)
    return http_response.send_response(client, status, body, headers, keep_alive, http_version, close_client)
end

local function send_json_response(client, status, body, keep_alive, http_version, content_type, extra_headers)
    return http_response.send_json_response(
        client,
        status,
        body,
        keep_alive,
        http_version,
        content_type,
        extra_headers,
        close_client
    )
end

function M._start_client_read(client, initial_buffer)
    return http_reader.start_client_read(client, initial_buffer, {
        bound_host = bound_host,
        close_client = close_client,
        handle_http_request = function(target_client, request)
            return http_handler.handle_http_request(target_client, request, {
                bound_host = bound_host,
                constant_time_equals = http_utils.constant_time_equals,
                has_session_http_token = has_session_http_token,
                requested_host = requested_host,
                send_json_response = send_json_response,
                send_response = send_response,
                server = server,
                session_http_token = session_http_token,
                should_keep_alive = http_utils.should_keep_alive,
            })
        end,
        notify_error = notify_error,
        requested_host = requested_host,
        send_json_response = send_json_response,
        send_response = send_response,
        server = server,
    })
end

---@return boolean, string?
function M.start()
    local descriptor = endpoint.describe_http()

    if server ~= nil and not server:is_closing() then
        if startup_pending then
            local same_port = requested_port == descriptor.http_port
            local same_host = requested_host == descriptor.http_host

            if same_host and same_port then
                return true, nil
            end

            M.stop()
        else
            local same_port = bound_port == descriptor.http_port or descriptor.http_port == 0

            if bound_host ~= descriptor.http_host or not same_port then
                M.stop()
            else
                return true, nil
            end
        end
    end

    for _, client in ipairs(pending_clients) do
        if not client:is_closing() then
            if client.read_stop ~= nil then
                client:read_stop()
            end
            client:close()
        end
    end
    pending_clients = {}

    startup_error = nil
    startup_pending = true
    session_http_token = descriptor.http_token
    requested_host = descriptor.http_host
    requested_port = descriptor.http_port
    server = assert(vim.uv.new_tcp())
    local ok, err = server:bind(descriptor.http_host, descriptor.http_port)

    if ok ~= 0 then
        if not server:is_closing() then
            server:close()
        end
        server = nil
        requested_host = nil
        requested_port = nil
        startup_pending = false
        startup_error = tostring(err or ok)
        return false, startup_error
    end

    local sockname = server.getsockname and server:getsockname() or nil
    bound_host = (sockname and sockname.ip) or descriptor.http_host
    bound_port = (sockname and sockname.port) or descriptor.http_port

    local listen_failed = nil
    local probe_connected = false
    local probe_consumed = false

    local function drain_pending_clients(start_clients)
        if startup_pending then
            return
        end

        for _, pending_client in ipairs(pending_clients) do
            if start_clients then
                table.insert(clients, pending_client)
                M._start_client_read(pending_client)
            elseif not pending_client:is_closing() then
                pending_client:close()
            end
        end

        pending_clients = {}
    end

    local listen_err = server:listen(128, function(callback_err)
        if callback_err then
            notify_error('mcp http listen error: ' .. tostring(callback_err), vim.log.levels.WARN)
            listen_failed = tostring(callback_err)
            startup_error = listen_failed
            if server ~= nil and not server:is_closing() then
                server:close()
            end
            server = nil
            startup_pending = false
            return
        end

        local client = assert(vim.uv.new_tcp())
        local accept_ok, accept_err = server:accept(client)

        if accept_ok ~= 0 then
            notify_error('mcp http accept error: ' .. tostring(accept_err or accept_ok), vim.log.levels.WARN)
            if not client:is_closing() then
                client:close()
            end

            return
        end

        if startup_pending and probe_connected and not probe_consumed then
            probe_consumed = true
            if not client:is_closing() then
                client:close()
            end
            return
        end

        if startup_pending then
            table.insert(pending_clients, client)
            return
        end

        table.insert(clients, client)
        M._start_client_read(client)
    end)

    if listen_err ~= nil and listen_err ~= 0 then
        if server ~= nil and not server:is_closing() then
            server:close()
        end
        server = nil
        requested_host = nil
        requested_port = nil
        startup_pending = false
        startup_error = tostring(listen_err)
        return false, startup_error
    end

    local probe_host = http_utils.probe_host_for(bound_host, descriptor.http_host)
    local probe = assert(vim.uv.new_tcp())
    local probe_pending = true
    local connect_ok, connect_err = probe:connect(probe_host, bound_port, function(callback_err)
        probe_pending = false
        if callback_err then
            startup_error = tostring(callback_err)
        elseif listen_failed ~= nil then
            startup_error = listen_failed
        else
            probe_connected = true
            startup_error = nil
        end
        if callback_err and server ~= nil and not server:is_closing() then
            server:close()
            server = nil
        end
        if not probe:is_closing() then
            probe:close()
        end
    end)

    if type(connect_ok) == 'number' and connect_ok < 0 then
        startup_pending = false
        startup_error = tostring(connect_err or connect_ok or 'connect failed')
        if server ~= nil and not server:is_closing() then
            server:close()
        end
        server = nil
        requested_host = nil
        requested_port = nil
        if not probe:is_closing() then
            probe:close()
        end
        return false, startup_error
    end

    local startup_finalized = false
    local startup_result = nil

    local function finalize_startup(err)
        if startup_finalized then
            return startup_result
        end
        startup_finalized = true
        startup_pending = false

        if err ~= nil then
            startup_error = err
            if server ~= nil and not server:is_closing() then
                server:close()
            end
            server = nil
            requested_host = nil
            requested_port = nil
        end

        drain_pending_clients(startup_error == nil)
        startup_result = startup_error == nil
        return startup_result
    end

    local function finalize_startup_async(err)
        if vim.in_fast_event() then
            vim.schedule(function()
                finalize_startup(err)
            end)
            return
        end

        finalize_startup(err)
    end

    local probe_timer = vim.uv.new_timer()
    if probe_timer == nil then
        finalize_startup('failed to create startup probe timer')
        if startup_error ~= nil then
            return false, startup_error
        end
        return server ~= nil, nil
    end

    local function stop_probe_timer()
        if probe_timer ~= nil and not probe_timer:is_closing() then
            probe_timer:stop()
            probe_timer:close()
        end
        probe_timer = nil
    end

    local function complete_probe(err)
        stop_probe_timer()
        finalize_startup_async(err)
    end

    if listen_failed ~= nil then
        complete_probe(listen_failed)
        return false, startup_error
    end

    probe_timer:start(1000, 0, function()
        if probe_pending or listen_failed ~= nil then
            if server ~= nil and not server:is_closing() then
                server:close()
            end
            server = nil
            if not probe:is_closing() then
                probe:close()
            end
            complete_probe(listen_failed or 'startup probe timed out')
        end
    end)

    if listen_failed ~= nil or not probe_pending then
        finalize_startup(startup_error or listen_failed)
        if startup_error ~= nil then
            return false, startup_error
        end
        return server ~= nil, nil
    end

    if vim.in_fast_event() then
        return false, 'http server startup pending'
    end

    local probe_completed = vim.wait(1000, function()
        return startup_finalized or not probe_pending or listen_failed ~= nil
    end)

    if listen_failed ~= nil then
        finalize_startup(listen_failed)
    elseif not probe_completed and not startup_finalized then
        if server ~= nil and not server:is_closing() then
            server:close()
        end
        server = nil
        if not probe:is_closing() then
            probe:close()
        end
        finalize_startup('startup probe timed out')
    elseif not startup_finalized then
        finalize_startup(startup_error)
    end

    if startup_error ~= nil then
        return false, startup_error
    end

    return server ~= nil, nil
end

function M.stop()
    for _, client in ipairs(clients) do
        if not client:is_closing() then
            if client.read_stop ~= nil then
                client:read_stop()
            end
            client:close()
        end
    end

    for _, client in ipairs(pending_clients) do
        if not client:is_closing() then
            if client.read_stop ~= nil then
                client:read_stop()
            end
            client:close()
        end
    end

    clients = {}
    pending_clients = {}

    if server ~= nil and not server:is_closing() then
        server:close()
    end

    server = nil
    bound_host = nil
    bound_port = nil
    requested_host = nil
    requested_port = nil
    startup_error = nil
    startup_pending = false
    session_http_token = nil
end

---@return boolean
function M.running()
    return server ~= nil and not server:is_closing() and not startup_pending
end

---@return string|nil, integer|nil
function M.bound_address()
    return bound_host, bound_port
end

M._send_response = send_response
M._send_json_response = send_json_response

return M
