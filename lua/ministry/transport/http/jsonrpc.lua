local router = require('ministry.protocol.router')

local M = {}

---@param response table|nil
---@return integer
function M.http_status_for_jsonrpc_response(_response)
    return 200
end

---@param id any
---@return table
function M.invalid_request_response(id)
    return {
        jsonrpc = '2.0',
        id = id == nil and vim.NIL or id,
        error = {
            code = -32600,
            message = 'Invalid Request',
        },
    }
end

---@param message any
---@param id any
---@return table
function M.parse_error_response(message, id)
    return {
        jsonrpc = '2.0',
        id = id == nil and vim.NIL or id,
        error = {
            code = -32700,
            message = tostring(message),
        },
    }
end

---@param responses table|nil
---@return integer
function M.batch_response_status(responses)
    if type(responses) ~= 'table' then
        return 200
    end

    for _, response in ipairs(responses) do
        local status = M.http_status_for_jsonrpc_response(response)
        if status >= 400 then
            return status
        end
    end

    return 200
end

---@param message any
---@return table|nil
function M.dispatch_jsonrpc_message(message)
    if type(message) ~= 'table' then
        return M.invalid_request_response(vim.NIL)
    end

    if vim.islist(message) then
        if vim.tbl_isempty(message) then
            return M.invalid_request_response(vim.NIL)
        end

        local responses = {}

        for _, entry in ipairs(message) do
            local response

            if type(entry) ~= 'table' or vim.islist(entry) then
                response = M.invalid_request_response(vim.NIL)
            else
                response = M.dispatch_jsonrpc_message(entry)
            end

            if response ~= nil then
                table.insert(responses, response)
            end
        end

        return next(responses) ~= nil and responses or nil
    end

    local is_notification = message.id == nil

    if message.jsonrpc ~= '2.0' or type(message.method) ~= 'string' then
        return is_notification and nil or M.invalid_request_response(message.id)
    end

    if message.params ~= nil and type(message.params) ~= 'table' then
        return is_notification and nil or M.invalid_request_response(message.id)
    end

    local response = router.handle_request(message.method, message.params, message.id, {})
    if is_notification then
        return nil
    end

    return response
end

---@param message any
---@param callback fun(response: table|nil)
function M.dispatch_jsonrpc_message_async(message, callback)
    local function dispatch()
        callback(M.dispatch_jsonrpc_message(message))
    end

    if vim.in_fast_event() then
        vim.schedule(dispatch)
        return
    end

    dispatch()
end

return M
