local M = {}

---@class ministry.HttpRequestMeta
---@field session_id? string
---@field status? integer

---@class ministry.HttpRequestOpts
---@field allow_empty_response? boolean
---@field expected_id? integer
---@field session_id? string

---@type fun(spec: ministry.ExternalServerSpec, payload: table, timeout_ms: integer, opts?: ministry.HttpRequestOpts): table?, table?, ministry.HttpRequestMeta?
local request_impl

---@param headers table<string, string>|nil
---@param session_id? string
---@return string[]
local function curl_headers(headers, session_id)
    local args = {
        '-sS',
        '-i',
        '-X',
        'POST',
        '-H',
        'Content-Type: application/json',
        '-H',
        'Accept: application/json, text/event-stream',
        '-H',
        'MCP-Protocol-Version: 2025-06-18',
    }

    for name, value in pairs(headers or {}) do
        table.insert(args, '-H')
        table.insert(args, string.format('%s: %s', name, value))
    end

    if session_id ~= nil and session_id ~= '' then
        table.insert(args, '-H')
        table.insert(args, string.format('Mcp-Session-Id: %s', session_id))
    end

    return args
end

---@param output string
---@return table<string, string>, string, integer?
local function split_headers(output)
    local headers = {}
    local header_text = ''
    local body = output or ''
    local status = nil

    while true do
        local start_index, end_index = body:find('\r\n\r\n', 1, true)
        if start_index == nil then
            start_index, end_index = body:find('\n\n', 1, true)
        end
        if start_index == nil then
            break
        end

        local candidate = body:sub(1, start_index - 1)
        if not candidate:match('^HTTP/%d[%.%d]*%s+') then
            break
        end

        header_text = candidate
        status = tonumber(candidate:match('^HTTP/%d[%.%d]*%s+(%d+)'))
        body = body:sub(end_index + 1)
    end

    for line in header_text:gmatch('[^\r\n]+') do
        local name, value = line:match('^([^:]+):%s*(.*)$')
        if name ~= nil then
            headers[name:lower()] = value
        end
    end

    return headers, body, status
end

---@param output string
---@return table[]
local function decode_sse(output)
    local messages = {}
    local event_lines = {}

    local function flush()
        if #event_lines == 0 then
            return
        end

        local data = {}
        for _, line in ipairs(event_lines) do
            local payload = line:match('^data:%s?(.*)$')
            if payload ~= nil then
                table.insert(data, payload)
            end
        end

        if #data > 0 then
            local ok, decoded = pcall(vim.json.decode, table.concat(data, '\n'))
            if ok and type(decoded) == 'table' then
                table.insert(messages, decoded)
            end
        end

        event_lines = {}
    end

    for line in (output .. '\n'):gmatch('(.-)\n') do
        line = line:gsub('\r$', '')
        if line == '' then
            flush()
        else
            table.insert(event_lines, line)
        end
    end

    return messages
end

---@param output string
---@param expected_id? integer
---@return table?, string?
local function decode_output(output, expected_id)
    if output == nil or output == '' then
        return nil, 'empty HTTP response'
    end

    if
        vim.startswith(output, 'event:')
        or vim.startswith(output, 'data:')
        or output:find('\ndata:', 1, true) ~= nil
    then
        for _, message in ipairs(decode_sse(output)) do
            if expected_id == nil or message.id == expected_id then
                return message, nil
            end
        end
        return nil, 'SSE response did not include the expected JSON-RPC id'
    end

    local ok, decoded = pcall(vim.json.decode, output)
    if not ok then
        return nil, tostring(decoded)
    end

    if vim.islist(decoded) and expected_id ~= nil then
        for _, item in ipairs(decoded) do
            if type(item) == 'table' and item.id == expected_id then
                return item, nil
            end
        end
        return nil, 'JSON-RPC batch response did not include the expected id'
    end

    return decoded, nil
end

---@param spec ministry.ExternalServerSpec
---@param payload table
---@param timeout_ms integer
---@param opts? ministry.HttpRequestOpts
---@return table?, table?, ministry.HttpRequestMeta?
local function curl_request(spec, payload, timeout_ms, opts)
    if spec.url == nil then
        return nil, {
            code = -32602,
            message = 'HTTP MCP server is missing url',
        }
    end

    opts = opts or {}
    local args = curl_headers(spec.headers, opts.session_id)
    table.insert(args, '--data-binary')
    table.insert(args, '@-')
    table.insert(args, spec.url)

    local result = vim.system(vim.list_extend({ 'curl' }, args), {
        text = true,
        stdin = vim.json.encode(payload),
        timeout = timeout_ms,
    }):wait()

    if result.code ~= 0 then
        return nil,
            {
                code = -32000,
                message = string.format('HTTP MCP request failed: %s', result.stderr or result.stdout or result.code),
            }
    end

    local headers, body, status = split_headers(result.stdout)
    local meta = {
        session_id = headers['mcp-session-id'],
        status = status,
    }

    if status ~= nil and (status < 200 or status >= 300) then
        return nil,
            {
                code = -32000,
                message = string.format('HTTP MCP request failed with status %d', status),
                http_status = status,
            },
            meta
    end

    if (body == nil or body == '') and opts.allow_empty_response then
        return {}, nil, meta
    end

    local decoded, decode_err = decode_output(body, opts.expected_id)
    if decoded == nil then
        return nil,
            {
                code = -32700,
                message = string.format('Invalid HTTP MCP response: %s', decode_err),
            },
            meta
    end

    return decoded, nil, meta
end

---@param spec ministry.ExternalServerSpec
---@param payload table
---@param timeout_ms integer
---@param opts? ministry.HttpRequestOpts
---@return table?, table?, ministry.HttpRequestMeta?
function M.request(spec, payload, timeout_ms, opts)
    return request_impl(spec, payload, timeout_ms, opts)
end

---@param impl fun(spec: ministry.ExternalServerSpec, payload: table, timeout_ms: integer, opts?: ministry.HttpRequestOpts): table?, table?, ministry.HttpRequestMeta?
function M._set_request_impl(impl)
    request_impl = impl
end

function M._reset_request_impl()
    request_impl = curl_request
end

function M._decode_output(output, expected_id)
    return decode_output(output, expected_id)
end

function M._split_headers(output)
    return split_headers(output)
end

request_impl = curl_request

return M
