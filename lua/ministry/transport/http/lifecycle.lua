local endpoint = require('ministry.transport.endpoint')
local http_utils = require('ministry.transport.http.utils')

local M = {}

---@param state table
---@param deps table
---@param start_clients boolean
local function drain_pending_clients(state, deps, start_clients)
    if state.startup_pending then
        return
    end

    for _, pending_client in ipairs(state.pending_clients) do
        if start_clients then
            table.insert(state.clients, pending_client)
            deps.start_client_read(pending_client)
        elseif not pending_client:is_closing() then
            pending_client:close()
        end
    end

    state.pending_clients = {}
end

---@param state table
---@param deps table
---@param err string?
---@return boolean
local function finalize_startup(state, deps, err)
    if state.startup_finalized then
        return state.startup_result
    end

    state.startup_finalized = true
    state.startup_pending = false

    if err ~= nil then
        state.startup_error = err
        if state.server ~= nil and not state.server:is_closing() then
            state.server:close()
        end
        state.server = nil
        state.requested_host = nil
        state.requested_port = nil
    end

    drain_pending_clients(state, deps, state.startup_error == nil)
    state.startup_result = state.startup_error == nil
    return state.startup_result
end

---@param state table
---@param deps table
---@param err string?
local function finalize_startup_async(state, deps, err)
    if vim.in_fast_event() then
        vim.schedule(function()
            finalize_startup(state, deps, err)
        end)
        return
    end

    finalize_startup(state, deps, err)
end

---@param state table
---@param deps table
---@return boolean, string?
function M.start(state, deps)
    local descriptor = endpoint.describe_http()
    local has_token = type(descriptor.http_token) == 'string' and vim.trim(descriptor.http_token) ~= ''

    if not http_utils.is_loopback_host(descriptor.http_host) and not has_token then
        return false, 'non-loopback Ministry HTTP endpoints require http_token authentication'
    end

    if state.server ~= nil and not state.server:is_closing() then
        if state.startup_pending then
            local same_port = state.requested_port == descriptor.http_port
            local same_host = state.requested_host == descriptor.http_host

            if same_host and same_port then
                return true, nil
            end

            deps.stop()
        else
            local same_port = state.bound_port == descriptor.http_port or descriptor.http_port == 0

            if state.bound_host ~= descriptor.http_host or not same_port then
                deps.stop()
            else
                return true, nil
            end
        end
    end

    for _, client in ipairs(state.pending_clients) do
        if not client:is_closing() then
            if client.read_stop ~= nil then
                client:read_stop()
            end
            client:close()
        end
    end
    state.pending_clients = {}

    state.startup_error = nil
    state.startup_pending = true
    state.startup_finalized = false
    state.startup_result = nil
    state.session_http_token = descriptor.http_token
    state.requested_host = descriptor.http_host
    state.requested_port = descriptor.http_port
    state.server = assert(vim.uv.new_tcp())
    local ok, err = state.server:bind(descriptor.http_host, descriptor.http_port)

    if ok ~= 0 then
        if not state.server:is_closing() then
            state.server:close()
        end
        state.server = nil
        state.requested_host = nil
        state.requested_port = nil
        state.startup_pending = false
        state.startup_error = tostring(err or ok)
        return false, state.startup_error
    end

    local sockname = state.server.getsockname and state.server:getsockname() or nil
    state.bound_host = (sockname and sockname.ip) or descriptor.http_host
    state.bound_port = (sockname and sockname.port) or descriptor.http_port

    local listen_failed = nil
    local probe_connected = false
    local probe_consumed = false

    local listen_err = state.server:listen(128, function(callback_err)
        if callback_err then
            deps.notify_error('mcp http listen error: ' .. tostring(callback_err), vim.log.levels.WARN)
            listen_failed = tostring(callback_err)
            state.startup_error = listen_failed
            if state.server ~= nil and not state.server:is_closing() then
                state.server:close()
            end
            state.server = nil
            state.startup_pending = false
            return
        end

        local client = assert(vim.uv.new_tcp())
        local accept_ok, accept_err = state.server:accept(client)

        if accept_ok ~= 0 then
            deps.notify_error('mcp http accept error: ' .. tostring(accept_err or accept_ok), vim.log.levels.WARN)
            if not client:is_closing() then
                client:close()
            end

            return
        end

        if state.startup_pending and probe_connected and not probe_consumed then
            probe_consumed = true
            if not client:is_closing() then
                client:close()
            end
            return
        end

        if state.startup_pending then
            table.insert(state.pending_clients, client)
            return
        end

        table.insert(state.clients, client)
        deps.start_client_read(client)
    end)

    if listen_err ~= nil and listen_err ~= 0 then
        if state.server ~= nil and not state.server:is_closing() then
            state.server:close()
        end
        state.server = nil
        state.requested_host = nil
        state.requested_port = nil
        state.startup_pending = false
        state.startup_error = tostring(listen_err)
        return false, state.startup_error
    end

    local probe_host = http_utils.probe_host_for(state.bound_host, descriptor.http_host)
    local probe = assert(vim.uv.new_tcp())
    local probe_pending = true
    local connect_ok, connect_err = probe:connect(probe_host, state.bound_port, function(callback_err)
        probe_pending = false
        if callback_err then
            state.startup_error = tostring(callback_err)
        elseif listen_failed ~= nil then
            state.startup_error = listen_failed
        else
            probe_connected = true
            state.startup_error = nil
        end
        if callback_err and state.server ~= nil and not state.server:is_closing() then
            state.server:close()
            state.server = nil
        end
        if not probe:is_closing() then
            probe:close()
        end
    end)

    if type(connect_ok) == 'number' and connect_ok < 0 then
        state.startup_pending = false
        state.startup_error = tostring(connect_err or connect_ok or 'connect failed')
        if state.server ~= nil and not state.server:is_closing() then
            state.server:close()
        end
        state.server = nil
        state.requested_host = nil
        state.requested_port = nil
        if not probe:is_closing() then
            probe:close()
        end
        return false, state.startup_error
    end

    local probe_timer = vim.uv.new_timer()
    if probe_timer == nil then
        finalize_startup(state, deps, 'failed to create startup probe timer')
        if state.startup_error ~= nil then
            return false, state.startup_error
        end
        return state.server ~= nil, nil
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
        finalize_startup_async(state, deps, err)
    end

    if listen_failed ~= nil then
        complete_probe(listen_failed)
        return false, state.startup_error
    end

    probe_timer:start(1000, 0, function()
        if probe_pending or listen_failed ~= nil then
            if state.server ~= nil and not state.server:is_closing() then
                state.server:close()
            end
            state.server = nil
            if not probe:is_closing() then
                probe:close()
            end
            complete_probe(listen_failed or 'startup probe timed out')
        end
    end)

    if listen_failed ~= nil or not probe_pending then
        finalize_startup(state, deps, state.startup_error or listen_failed)
        if state.startup_error ~= nil then
            return false, state.startup_error
        end
        return state.server ~= nil, nil
    end

    if vim.in_fast_event() then
        return false, 'http server startup pending'
    end

    local probe_completed = vim.wait(1000, function()
        return state.startup_finalized or not probe_pending or listen_failed ~= nil
    end)

    if listen_failed ~= nil then
        finalize_startup(state, deps, listen_failed)
    elseif not probe_completed and not state.startup_finalized then
        if state.server ~= nil and not state.server:is_closing() then
            state.server:close()
        end
        state.server = nil
        if not probe:is_closing() then
            probe:close()
        end
        finalize_startup(state, deps, 'startup probe timed out')
    elseif not state.startup_finalized then
        finalize_startup(state, deps, state.startup_error)
    end

    if state.startup_error ~= nil then
        return false, state.startup_error
    end

    return state.server ~= nil, nil
end

---@param state table
function M.stop(state)
    for _, client in ipairs(state.clients) do
        if not client:is_closing() then
            if client.read_stop ~= nil then
                client:read_stop()
            end
            client:close()
        end
    end

    for _, client in ipairs(state.pending_clients) do
        if not client:is_closing() then
            if client.read_stop ~= nil then
                client:read_stop()
            end
            client:close()
        end
    end

    state.clients = {}
    state.pending_clients = {}

    if state.server ~= nil and not state.server:is_closing() then
        state.server:close()
    end

    state.server = nil
    state.bound_host = nil
    state.bound_port = nil
    state.requested_host = nil
    state.requested_port = nil
    state.startup_error = nil
    state.startup_pending = false
    state.startup_finalized = false
    state.startup_result = nil
    state.session_http_token = nil
end

---@param state table
---@return boolean
function M.running(state)
    return state.server ~= nil and not state.server:is_closing() and not state.startup_pending
end

---@param state table
---@return string|nil, integer|nil
function M.bound_address(state)
    return state.bound_host, state.bound_port
end

return M
