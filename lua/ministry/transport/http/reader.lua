local cors = require('ministry.transport.http.cors')
local http_jsonrpc = require('ministry.transport.http.jsonrpc')
local http_request = require('ministry.transport.http.request')

local M = {}

---@param client uv_tcp_t
---@param initial_buffer string?
---@param deps table
function M.start_client_read(client, initial_buffer, deps)
    local state = type(client) == 'table' and client or nil
    if state ~= nil then
        state._mcp_http_buffer = (state._mcp_http_buffer or '') .. (initial_buffer or '')
    end
    local buffer = ((state and state._mcp_http_buffer) or '')
    local reading = false

    local function sync_buffer()
        if state ~= nil then
            state._mcp_http_buffer = buffer
        end
    end

    local function dispatch_requests()
        while true do
            local request, consumed_or_err, parse_err = http_request.parse_request(buffer)

            if request == nil then
                local effective_err = consumed_or_err or parse_err

                if effective_err == nil then
                    return
                end

                local request_version = nil
                local first_line = buffer:match('^([^\r\n]+)')
                if first_line ~= nil then
                    request_version = first_line:match('^%S+%s+%S+%s+(%S+)')
                end

                if
                    request_version ~= nil
                    and request_version:match('^HTTP/%d+%.%d+$')
                    and request_version ~= 'HTTP/1.1'
                    and request_version ~= 'HTTP/1.0'
                then
                    buffer = ''
                    sync_buffer()
                    deps.send_response(client, 505, '', nil, false, 'HTTP/1.1')
                    return
                end

                local response = http_jsonrpc.parse_error_response(effective_err, vim.NIL)
                local response_headers = cors.cors_headers_from_buffer(buffer, {
                    server = deps.server,
                    bound_host = deps.bound_host,
                    requested_host = deps.requested_host,
                })
                buffer = ''
                sync_buffer()
                deps.send_json_response(
                    client,
                    200,
                    vim.json.encode(response),
                    false,
                    request_version,
                    nil,
                    response_headers
                )
                return
            end

            buffer = buffer:sub(consumed_or_err + 1)
            sync_buffer()
            deps.handle_http_request(client, request)

            if client:is_closing() then
                return
            end
        end
    end

    local function ensure_reading()
        if client:is_closing() or reading then
            return
        end

        if client.read_start == nil then
            deps.close_client(client)
            return
        end

        reading = true
        client:read_start(function(err, data)
            reading = false
            if err ~= nil then
                deps.notify_error('mcp http read error: ' .. tostring(err), vim.log.levels.WARN)
                deps.close_client(client)
                return
            end

            if data == nil then
                deps.close_client(client)
                return
            end

            buffer = buffer .. data
            sync_buffer()

            if client.read_stop ~= nil then
                client:read_stop()
            end
            dispatch_requests()
            sync_buffer()
            if not client:is_closing() then
                ensure_reading()
            end
        end)
    end

    if buffer ~= '' then
        dispatch_requests()
        sync_buffer()
        if not client:is_closing() then
            ensure_reading()
        end
        return
    end

    ensure_reading()
end

return M
