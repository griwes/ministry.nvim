local config = require('ministry.core.config')
local cors = require('ministry.transport.http.cors')
local http_handler = require('ministry.transport.http.handler')
local http_jsonrpc = require('ministry.transport.http.jsonrpc')
local http_lifecycle = require('ministry.transport.http.lifecycle')
local negotiation = require('ministry.transport.http.negotiation')
local http_request = require('ministry.transport.http.request')
local http_reader = require('ministry.transport.http.reader')
local http_response = require('ministry.transport.http.response')
local http_utils = require('ministry.transport.http.utils')
local endpoint = require('ministry.transport.endpoint')
local protocol_session = require('ministry.protocol.session')

local function notify_error(message, level)
    vim.schedule(function()
        vim.notify(message, level or vim.log.levels.ERROR)
    end)
end

local M = {}

local state = {
    ---@type uv_tcp_t?
    server = nil,
    ---@type string?
    bound_host = nil,
    ---@type integer?
    bound_port = nil,
    ---@type string?
    requested_host = nil,
    ---@type integer?
    requested_port = nil,
    ---@type string?
    startup_error = nil,
    ---@type boolean
    startup_pending = false,
    ---@type boolean
    startup_finalized = false,
    ---@type boolean?
    startup_result = nil,
    ---@type uv_tcp_t[]
    clients = {},
    ---@type uv_tcp_t[]
    pending_clients = {},
    session_http_token = nil,
}

---@type table<uv_tcp_t, string>
local client_sessions = {}
---@type table<uv_tcp_t, uv_timer_t>
local client_timers = {}

local function has_session_http_token()
    return type(state.session_http_token) == 'string' and vim.trim(state.session_http_token) ~= ''
end

local function remove_client(target)
    local retained = {}

    for _, client in ipairs(state.clients) do
        if client ~= target then
            table.insert(retained, client)
        end
    end

    state.clients = retained
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
    local session_id = client_sessions[client]
    if session_id == nil then
        session_id = protocol_session.open('http')
        client_sessions[client] = session_id
    end

    return http_reader.start_client_read(client, initial_buffer, {
        bound_host = state.bound_host,
        close_client = close_client,
        handle_http_request = function(target_client, request)
            return http_handler.handle_http_request(target_client, request, {
                bound_host = state.bound_host,
                constant_time_equals = http_utils.constant_time_equals,
                has_session_http_token = has_session_http_token,
                requested_host = state.requested_host,
                send_json_response = send_json_response,
                send_response = send_response,
                server = state.server,
                session_http_token = state.session_http_token,
                session_id = session_id,
                should_keep_alive = http_utils.should_keep_alive,
            })
        end,
        notify_error = notify_error,
        requested_host = state.requested_host,
        set_client_timer = function(target_client, timer)
            client_timers[target_client] = timer
        end,
        send_json_response = send_json_response,
        send_response = send_response,
        server = state.server,
    })
end

---@return boolean, string?
function M.start()
    return http_lifecycle.start(state, {
        notify_error = notify_error,
        start_client_read = function(client)
            return M._start_client_read(client)
        end,
        stop = function()
            return M.stop()
        end,
    })
end

function M.stop()
    local seen = {}
    local active_clients = {}
    for _, client in ipairs(state.clients) do
        table.insert(active_clients, client)
        seen[client] = true
    end
    for client in pairs(client_sessions) do
        if not seen[client] then
            table.insert(active_clients, client)
        end
    end
    for _, client in ipairs(active_clients) do
        close_client(client)
    end

    client_sessions = {}
    client_timers = {}

    return http_lifecycle.stop(state)
end

---@return boolean
function M.running()
    return http_lifecycle.running(state)
end

---@return string|nil, integer|nil
function M.bound_address()
    return http_lifecycle.bound_address(state)
end

M._send_response = send_response
M._send_json_response = send_json_response

return M
