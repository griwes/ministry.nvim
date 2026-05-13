local config = require('ministry.core.config')

local M = {}

local function append_header_value(headers, name, value)
    local current = headers[name]

    if current == nil then
        headers[name] = value
        return
    end

    if type(current) == 'table' then
        table.insert(current, value)
        return
    end

    headers[name] = { current, value }
end

local function get_single_header_value(headers, name)
    local value = headers[name]

    if type(value) == 'table' then
        return nil
    end

    return value
end

local function combine_header_values(value)
    if type(value) == 'table' then
        return table.concat(value, ', ')
    end

    return value
end

---@param raw string
---@return table?, integer?, string?
function M.parse_request(raw)
    if raw == '' then
        return nil
    end

    local header_start, header_finish = raw:find('\r\n\r\n', 1, true)
    local newline = '\r\n'
    local limits = config.get().limits
    local max_header_bytes = math.max(1, tonumber(limits.http_header_bytes) or 64 * 1024)
    local max_body_bytes = math.max(1, tonumber(limits.http_body_bytes) or 4 * 1024 * 1024)

    if header_start == nil or header_finish == nil then
        header_start, header_finish = raw:find('\n\n', 1, true)
        if header_start ~= nil then
            local lf_head = raw:sub(1, header_start - 1)
            if lf_head:find('\r', 1, true) ~= nil then
                return nil, nil, 'invalid http framing'
            end
        end
        newline = '\n'
    end

    if header_start == nil or header_finish == nil then
        if #raw > max_header_bytes then
            return nil, nil, 'http headers exceed configured limit'
        end
        return nil
    end

    if header_start - 1 > max_header_bytes then
        return nil, nil, 'http headers exceed configured limit'
    end

    local head = raw:sub(1, header_start - 1)
    local body_start = header_finish + 1

    if newline == '\r\n' then
        if head:find('[^\r]\n', 1) ~= nil then
            return nil, nil, 'invalid http framing'
        end
    elseif head:find('\r', 1, true) ~= nil then
        return nil, nil, 'invalid http framing'
    end

    local normalized_head = head:gsub('\r\n', '\n')
    local first_line = normalized_head:match('([^\n]+)')

    if first_line == nil then
        return nil
    end

    local method, path, http_version = first_line:match('^(%S+)%s+(%S+)%s+(%S+)$')

    if method == nil or path == nil or http_version == nil then
        return nil
    end

    if http_version:match('^HTTP/%d+%.%d+$') == nil then
        return nil, nil, 'invalid http version'
    end

    local content_length = nil
    local headers = {}
    local first_header = true

    for line in normalized_head:gmatch('[^\n]+') do
        if first_header then
            first_header = false
        else
            if line:match('^[ \t]') ~= nil then
                return nil, nil, 'invalid folded header'
            end

            local name, value = line:match('^([^:]+):%s*(.*)$')

            if name ~= nil then
                local lower_name = name:lower()
                append_header_value(headers, lower_name, value)

                if lower_name == 'content-length' then
                    if value:match('^%d+$') == nil then
                        return nil, nil, 'invalid content-length'
                    end

                    local parsed_value = tonumber(value)

                    if parsed_value == nil then
                        return nil, nil, 'invalid content-length'
                    end

                    if content_length ~= nil and parsed_value ~= content_length then
                        return nil, nil, 'ambiguous content-length'
                    end

                    content_length = parsed_value
                    if content_length > max_body_bytes then
                        return nil, nil, 'http body exceeds configured limit'
                    end
                elseif lower_name == 'content-type' and type(headers[lower_name]) == 'table' then
                    return nil, nil, 'duplicate content-type'
                end
            end
        end
    end

    local transfer_encoding = headers['transfer-encoding']
    if transfer_encoding ~= nil then
        return nil, nil, 'unsupported transfer-encoding'
    end

    if content_length == nil then
        if body_start <= #raw then
            return nil, nil, 'missing content-length'
        end

        content_length = 0
    end

    if type(headers.accept) == 'table' then
        headers.accept = combine_header_values(headers.accept)
    end

    if type(headers.connection) == 'table' then
        headers.connection = combine_header_values(headers.connection)
    end

    headers['content-type'] = get_single_header_value(headers, 'content-type')
    if type(headers['content-length']) == 'table' then
        headers['content-length'] = tostring(content_length)
    else
        headers['content-length'] = get_single_header_value(headers, 'content-length')
    end

    if (#raw - body_start + 1) < content_length then
        return nil
    end

    local body = ''
    if content_length > 0 then
        body = raw:sub(body_start, body_start + content_length - 1)
    end

    return {
        method = method,
        path = path,
        http_version = http_version,
        body = body,
        headers = headers,
        connection_reusable = true,
    },
        body_start + content_length - 1
end

---@param request table
---@return string?
function M.request_bearer_token(request)
    local authorization = request.headers.authorization

    if type(authorization) ~= 'string' then
        return nil
    end

    local token = authorization:match('^[Bb][Ee][Aa][Rr][Ee][Rr]%s+(.+)$')
    if token == nil then
        return nil
    end

    token = vim.trim(token)
    if token == '' then
        return nil
    end

    return token
end

---@param request table
---@return table
function M.snapshot_request(request)
    return {
        method = request.method,
        path = request.path,
        http_version = request.http_version,
        body = request.body,
        headers = vim.deepcopy(request.headers),
    }
end

return M
