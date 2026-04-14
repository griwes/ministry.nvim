local M = {}

local reason_phrases = {
    [200] = 'OK',
    [204] = 'No Content',
    [400] = 'Bad Request',
    [401] = 'Unauthorized',
    [404] = 'Not Found',
    [405] = 'Method Not Allowed',
    [406] = 'Not Acceptable',
    [415] = 'Unsupported Media Type',
    [422] = 'Unprocessable Entity',
    [500] = 'Internal Server Error',
    [505] = 'HTTP Version Not Supported',
}

---@param client uv_tcp_t
---@param status integer
---@param body string
---@param headers string[]?
---@param keep_alive boolean
---@param http_version string?
---@param close_client fun(client: uv_tcp_t)
function M.send_response(client, status, body, headers, keep_alive, http_version, close_client)
    assert(type(body) == 'string', 'http response body must be a string')

    local response_version = http_version or 'HTTP/1.1'
    local response_headers = vim.deepcopy(headers or {})
    local has_content_type = false
    local allows_body = status < 100 or status >= 200
    allows_body = allows_body and status ~= 204 and status ~= 304
    local response_body = allows_body and body or ''

    for _, header in ipairs(response_headers) do
        if header:lower():match('^content%-type:') ~= nil then
            has_content_type = true
            break
        end
    end

    if allows_body and not has_content_type then
        table.insert(response_headers, 'Content-Type: application/json')
    end

    local payload = {
        string.format('%s %d %s', response_version, status, reason_phrases[status] or 'Unknown'),
    }

    if allows_body or keep_alive then
        table.insert(payload, string.format('Content-Length: %d', #response_body))
    end

    for _, header in ipairs(response_headers) do
        table.insert(payload, header)
    end

    table.insert(payload, 'Connection: ' .. (keep_alive and 'keep-alive' or 'close'))
    table.insert(payload, '')
    table.insert(payload, response_body)

    client:write(table.concat(payload, '\r\n'), function()
        if not keep_alive then
            close_client(client)
        end
    end)
end

---@param client uv_tcp_t
---@param status integer
---@param body string
---@param keep_alive boolean
---@param http_version string?
---@param content_type string?
---@param extra_headers string[]?
---@param close_client fun(client: uv_tcp_t)
function M.send_json_response(client, status, body, keep_alive, http_version, content_type, extra_headers, close_client)
    local headers = {
        'Content-Type: ' .. (content_type or 'application/json'),
    }

    for _, header in ipairs(extra_headers or {}) do
        table.insert(headers, header)
    end

    return M.send_response(client, status, body, headers, keep_alive, http_version, close_client)
end

return M
