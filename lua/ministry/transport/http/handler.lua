local cors = require('ministry.transport.http.cors')
local http_jsonrpc = require('ministry.transport.http.jsonrpc')
local negotiation = require('ministry.transport.http.negotiation')
local http_request = require('ministry.transport.http.request')

local M = {}

---@param request table?
---@param has_session_http_token fun(): boolean
---@return boolean
local function is_cors_preflight_request(request, has_session_http_token)
    if request == nil or request.method ~= 'OPTIONS' then
        return false
    end

    local headers = request.headers or {}
    local origin = headers.origin or headers.Origin
    local requested_method = headers['access-control-request-method'] or headers['Access-Control-Request-Method']
    local requested_headers = headers['access-control-request-headers'] or headers['Access-Control-Request-Headers']

    if has_session_http_token() then
        if type(requested_headers) ~= 'string' then
            return false
        end

        local declares_authorization = false
        for header_name in requested_headers:gmatch('[^,]+') do
            if vim.trim(header_name):lower() == 'authorization' then
                declares_authorization = true
                break
            end
        end

        if not declares_authorization then
            return false
        end
    end

    return type(origin) == 'string'
        and origin ~= ''
        and type(requested_method) == 'string'
        and requested_method:upper() == 'POST'
end

---@param client uv_tcp_t
---@param request table
---@param deps table
function M.handle_http_request(client, request, deps)
    if client:is_closing() then
        return
    end

    local keep_alive = deps.should_keep_alive(request)
    local http_version = request.http_version
    local response_headers = cors.cors_headers(request, {
        server = deps.server,
        bound_host = deps.bound_host,
        requested_host = deps.requested_host,
    })

    if request.path ~= '/mcp' then
        deps.send_json_response(
            client,
            404,
            vim.json.encode({
                error = 'not found',
            }),
            keep_alive,
            http_version,
            nil,
            response_headers
        )
        return
    end

    if http_version ~= 'HTTP/1.1' and http_version ~= 'HTTP/1.0' then
        deps.send_response(client, 505, '', nil, false, 'HTTP/1.1')
        return
    end

    if is_cors_preflight_request(request, deps.has_session_http_token) then
        deps.send_response(client, 204, '', response_headers, keep_alive, http_version)
        return
    end

    if
        deps.has_session_http_token()
        and not deps.constant_time_equals(http_request.request_bearer_token(request), deps.session_http_token)
    then
        deps.send_json_response(
            client,
            401,
            vim.json.encode({
                error = 'unauthorized',
            }),
            keep_alive,
            http_version,
            nil,
            vim.list_extend(response_headers, {
                'WWW-Authenticate: Bearer',
            })
        )
        return
    end

    if request.method ~= 'POST' then
        deps.send_json_response(
            client,
            405,
            vim.json.encode({
                error = 'method not allowed',
            }),
            keep_alive,
            http_version,
            nil,
            response_headers
        )
        return
    end

    local accept_header = request.headers.accept
    local response_content_type = negotiation.negotiate_response_content_type(accept_header)

    if response_content_type == nil then
        deps.send_json_response(
            client,
            406,
            vim.json.encode({
                error = 'unsupported accept header',
            }),
            keep_alive,
            http_version,
            nil,
            response_headers
        )
        return
    end

    local content_type = request.headers['content-type']
    if content_type == nil or not negotiation.content_type_is_json(content_type) then
        deps.send_json_response(
            client,
            415,
            vim.json.encode({
                error = 'unsupported content type',
            }),
            keep_alive,
            http_version,
            nil,
            response_headers
        )
        return
    end

    local ok, decoded = pcall(vim.json.decode, request.body)

    if not ok then
        deps.send_json_response(
            client,
            200,
            vim.json.encode({
                jsonrpc = '2.0',
                id = vim.NIL,
                error = {
                    code = -32700,
                    message = tostring(decoded),
                },
            }),
            keep_alive,
            http_version,
            response_content_type,
            response_headers
        )
        return
    end

    local message = decoded

    if message == vim.NIL or type(message) ~= 'table' then
        local response = http_jsonrpc.invalid_request_response(vim.NIL)
        deps.send_json_response(
            client,
            http_jsonrpc.http_status_for_jsonrpc_response(response),
            vim.json.encode(response),
            keep_alive,
            http_version,
            response_content_type,
            response_headers
        )
        return
    end

    http_jsonrpc.dispatch_jsonrpc_message_async(message, function(response)
        if client:is_closing() then
            return
        end

        if response == nil then
            deps.send_response(client, 204, '', response_headers, keep_alive, http_version)
            return
        end

        local encoded = vim.json.encode(response)
        local status = vim.islist(response) and http_jsonrpc.batch_response_status(response)
            or http_jsonrpc.http_status_for_jsonrpc_response(response)

        deps.send_json_response(
            client,
            status,
            encoded,
            keep_alive,
            http_version,
            response_content_type,
            response_headers
        )
    end)
end

return M
