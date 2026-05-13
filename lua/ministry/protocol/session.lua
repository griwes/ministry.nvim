local config = require('ministry.core.config')

local M = {}

---@class ministry.InflightRequest
---@field cancelled boolean
---@field cancellation_handlers table<integer, fun(reason?: string)>
---@field next_handler_id integer
---@field reason? string
---@field timer? uv_timer_t

---@class ministry.ProtocolSession
---@field id string
---@field transport 'socket'|'http'
---@field requests table<string, ministry.InflightRequest>

---@type table<string, ministry.ProtocolSession>
local sessions = {}
local next_session_ordinal = 0

---@param request_id any
---@return string
local function request_key(request_id)
    return string.format('%s:%s', type(request_id), tostring(request_id))
end

---@param callback fun()
local function invoke(callback)
    if vim.in_fast_event() then
        vim.schedule(callback)
        return
    end

    callback()
end

---@param session_id string
---@param request_id any
---@param reason? string
---@return boolean
function M.cancel(session_id, request_id, reason)
    local session = sessions[session_id]
    local request = session ~= nil and session.requests[request_key(request_id)] or nil
    if request == nil or request.cancelled then
        return false
    end

    request.cancelled = true
    request.reason = reason or 'cancelled'

    for _, handler in pairs(request.cancellation_handlers) do
        invoke(function()
            pcall(handler, request.reason)
        end)
    end

    local ok, approval = pcall(require, 'ministry.approval.policy')
    if ok and type(approval.cancel_session) == 'function' then
        approval.cancel_session(session_id)
    end

    return true
end

---@param transport 'socket'|'http'
---@return string
function M.open(transport)
    next_session_ordinal = next_session_ordinal + 1
    local session_id = string.format('%s-%d-%d-%d', transport, vim.fn.getpid(), vim.uv.hrtime(), next_session_ordinal)
    sessions[session_id] = {
        id = session_id,
        transport = transport,
        requests = {},
    }
    return session_id
end

---@param session_id string
---@param request_id any
---@return table
function M.begin_request(session_id, request_id)
    local session = sessions[session_id]
    if session == nil then
        return {}
    end

    local key = request_key(request_id)
    if session.requests[key] ~= nil then
        return {
            duplicate_request = true,
            request_id = request_id,
            transport = session.transport,
            transport_session_id = session_id,
        }
    end

    local request = {
        cancelled = false,
        cancellation_handlers = {},
        next_handler_id = 0,
    }
    session.requests[key] = request

    local timeout_ms = math.max(1, tonumber(config.get().limits.request_timeout_ms) or 30000)
    local timer = vim.uv.new_timer()
    if timer ~= nil then
        request.timer = timer
        timer:start(timeout_ms, 0, function()
            M.cancel(session_id, request_id, 'request deadline exceeded')
        end)
    end

    return {
        transport = session.transport,
        transport_session_id = session_id,
        request_id = request_id,
        cancel_request = function(target_request_id, reason)
            return M.cancel(session_id, target_request_id, reason)
        end,
        is_cancelled = function()
            return request.cancelled, request.reason
        end,
        register_cancellation = function(handler)
            assert(type(handler) == 'function', 'cancellation handler must be a function')
            request.next_handler_id = request.next_handler_id + 1
            local handler_id = request.next_handler_id
            request.cancellation_handlers[handler_id] = handler

            if request.cancelled then
                invoke(function()
                    pcall(handler, request.reason)
                end)
            end

            return function()
                request.cancellation_handlers[handler_id] = nil
            end
        end,
    }
end

---@param session_id string
---@param request_id any
function M.finish_request(session_id, request_id)
    local session = sessions[session_id]
    local request = session ~= nil and session.requests[request_key(request_id)] or nil
    if request == nil then
        return
    end

    if request.timer ~= nil and not request.timer:is_closing() then
        request.timer:stop()
        request.timer:close()
    end

    session.requests[request_key(request_id)] = nil
end

---@param session_id string
function M.close(session_id)
    local session = sessions[session_id]
    if session == nil then
        return
    end

    local request_ids = {}
    for key in pairs(session.requests) do
        table.insert(request_ids, key)
    end

    for _, key in ipairs(request_ids) do
        local request = session.requests[key]
        if request ~= nil then
            request.cancelled = true
            request.reason = 'transport disconnected'
            for _, handler in pairs(request.cancellation_handlers) do
                invoke(function()
                    pcall(handler, request.reason)
                end)
            end
            if request.timer ~= nil and not request.timer:is_closing() then
                request.timer:stop()
                request.timer:close()
            end
        end
    end

    sessions[session_id] = nil

    local ok, approval = pcall(require, 'ministry.approval.policy')
    if ok and type(approval.cancel_session) == 'function' then
        approval.cancel_session(session_id)
    end
end

---@param context table?
---@return table
function M.bind_approval_context(context)
    local bound = vim.deepcopy(context or {})
    if type(bound.transport_session_id) == 'string' and sessions[bound.transport_session_id] ~= nil then
        return bound
    end

    local only_session_id = nil
    for session_id in pairs(sessions) do
        if only_session_id ~= nil then
            return bound
        end
        only_session_id = session_id
    end

    if only_session_id ~= nil then
        bound.transport_session_id = only_session_id
    end

    return bound
end

function M.reset()
    local session_ids = vim.tbl_keys(sessions)
    for _, session_id in ipairs(session_ids) do
        M.close(session_id)
    end
    sessions = {}
    next_session_ordinal = 0
end

---@return table<string, ministry.ProtocolSession>
function M._debug_sessions()
    return sessions
end

return M
