local endpoint = require('mcp.endpoint')
local router = require('mcp.router')

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

local function send_response(client, status, body, headers, keep_alive, http_version)
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

local function is_valid_ipv4_literal(value)
    local octets = vim.split(value, '.', { plain = true })

    if #octets ~= 4 then
        return false
    end

    for _, octet in ipairs(octets) do
        if octet == '' or octet:find('^%d+$') == nil then
            return false
        end

        local number = tonumber(octet)
        if number == nil or number < 0 or number > 255 or tostring(number) ~= octet then
            return false
        end
    end

    return true
end

local function is_valid_ipv6_literal(value)
    if value == '' or value:find(':::', 1, true) ~= nil then
        return false
    end

    local ipv4_tail = false
    if value:find('%.', 1, true) ~= nil then
        local prefix, tail = value:match('^(.*:)([^:]+)$')
        if prefix == nil or tail == nil or not is_valid_ipv4_literal(tail) then
            return false
        end

        value = prefix:sub(1, -2)
        ipv4_tail = true
    end

    if value == '' then
        return false
    end

    local compression_start, compression_end = value:find('::', 1, true)
    local left = value
    local right = nil

    if compression_start ~= nil then
        if value:find('::', compression_end + 1, true) ~= nil then
            return false
        end

        left = value:sub(1, compression_start - 1)
        right = value:sub(compression_end + 1)
    end

    local function count_groups(segment)
        if segment == '' then
            return 0
        end

        local count = 0
        for group in segment:gmatch('[^:]+') do
            if group:find('^%x+$') == nil or #group > 4 then
                return nil
            end
            count = count + 1
        end

        return count
    end

    local left_count = count_groups(left)
    if left_count == nil then
        return false
    end

    local right_count = 0
    if right ~= nil then
        local parsed_right_count = count_groups(right)
        if parsed_right_count == nil then
            return false
        end
        right_count = parsed_right_count
    end

    local total_groups = left_count + right_count + (ipv4_tail and 2 or 0)
    if compression_start ~= nil then
        return total_groups < 8
    end

    return total_groups == 8
end

local function parse_ipv6_origin_host(host)
    if type(host) ~= 'string' or host == '' then
        return nil
    end

    local address = host
    local zone_id = host:match('^(.-)%%25([%w%.%-%_%~]+)$')
    if zone_id ~= nil then
        address = host:match('^(.-)%%25')
        if address == nil or address == '' then
            return nil
        end
    elseif host:find('%%', 1, true) ~= nil then
        return nil
    end

    if not is_valid_ipv6_literal(address) then
        return nil
    end

    return {
        address = address,
        zone_id = zone_id,
    }
end

local function constant_time_equals(left, right)
    if type(left) ~= 'string' or type(right) ~= 'string' then
        return false
    end

    local left_length = #left
    local right_length = #right
    local max_length = math.max(left_length, right_length)
    local diff = left_length == right_length and 0 or 1

    for index = 1, max_length do
        local left_byte = index <= left_length and left:byte(index) or 0
        local right_byte = index <= right_length and right:byte(index) or 0
        if left_byte ~= right_byte then
            diff = 1
        end
    end

    return diff == 0
end

local function is_localhost_origin_host(host)
    if type(host) ~= 'string' or host == '' then
        return false
    end

    if host == 'localhost' then
        return true
    end

    if is_valid_ipv4_literal(host) then
        return host:match('^127%.') ~= nil
    end

    local parsed_ipv6 = parse_ipv6_origin_host(host)
    if parsed_ipv6 ~= nil then
        local normalized_host = parsed_ipv6.address:lower()
        if normalized_host == '::1' then
            return true
        end

        local ipv4_tail = normalized_host:match('^::ffff:(.+)$')
        if ipv4_tail ~= nil then
            if is_valid_ipv4_literal(ipv4_tail) then
                return ipv4_tail:match('^127%.') ~= nil
            end

            local first_group, second_group = ipv4_tail:match('^(%x+):(%x+)$')
            if first_group ~= nil and second_group ~= nil then
                local upper = tonumber(first_group, 16)
                local lower = tonumber(second_group, 16)
                if upper ~= nil and lower ~= nil then
                    return math.floor(upper / 256) == 127 and upper % 256 == 0 and lower >= 0 and lower <= 65535
                end
            end
        end
    end

    return false
end

local function normalize_origin_host(host)
    if type(host) ~= 'string' then
        return host
    end

    local normalized = host:match('^%[(.*)%]$')
    if normalized ~= nil then
        return normalized
    end

    return host
end

local function cors_allow_origin(request)
    if not has_session_http_token() then
        return nil
    end

    local origin = request and request.headers and request.headers.origin

    if type(origin) ~= 'string' then
        return nil
    end

    origin = vim.trim(origin)
    if origin == '' or origin == 'null' or origin:find('[\r\n]', 1) ~= nil then
        return nil
    end

    local scheme, authority = origin:match('^(https?)://([^/?#]+)$')
    if scheme == nil or authority == nil or authority == '' then
        return nil
    end

    if authority:find('@', 1, true) ~= nil then
        return nil
    end

    local host, port

    if authority:sub(1, 1) == '[' then
        host, port = authority:match('^(%b[])()')
        if host == nil or host == '[]' then
            return nil
        end

        local rest = authority:sub(port)
        if rest == '' then
            port = nil
        else
            port = rest:match('^:(%d+)$')
            if port == nil then
                return nil
            end
        end

        host = host:sub(2, -2)
        if parse_ipv6_origin_host(host) == nil then
            return nil
        end
    else
        local maybe_host, maybe_port = authority:match('^(.*):(%d+)$')
        if maybe_host ~= nil then
            host = maybe_host
            port = maybe_port
        else
            host = authority
        end

        if host == nil or host == '' or host:find('[%s/:?#%%]') ~= nil then
            return nil
        end
    end

    if port ~= nil and tonumber(port) == nil then
        return nil
    end

    local allowed_host = bound_host or endpoint.describe_http().http_host

    if type(allowed_host) ~= 'string' or allowed_host == '' then
        return nil
    end

    local normalized_host = normalize_origin_host(host)
    local normalized_allowed_host = normalize_origin_host(allowed_host)
    local parsed_origin_ipv6 = parse_ipv6_origin_host(normalized_host)
    local parsed_allowed_ipv6 = parse_ipv6_origin_host(normalized_allowed_host)

    local allow_localhost_origin = normalized_allowed_host == '0.0.0.0'
        or normalized_allowed_host == '::'
        or normalized_allowed_host:lower() == 'localhost'

    if allow_localhost_origin then
        if not is_localhost_origin_host(normalized_host) then
            return nil
        end
    elseif parsed_origin_ipv6 ~= nil and parsed_allowed_ipv6 ~= nil then
        if parsed_origin_ipv6.address:lower() ~= parsed_allowed_ipv6.address:lower() then
            return nil
        end

        local origin_zone_id = parsed_origin_ipv6.zone_id
        local allowed_zone_id = parsed_allowed_ipv6.zone_id
        if origin_zone_id ~= nil or allowed_zone_id ~= nil then
            if origin_zone_id == nil or allowed_zone_id == nil then
                return nil
            end

            if origin_zone_id:lower() ~= allowed_zone_id:lower() then
                return nil
            end
        end
    elseif normalized_host:lower() ~= normalized_allowed_host:lower() then
        return nil
    end

    return origin
end

local function cors_headers(request)
    local headers = {
        'Access-Control-Allow-Methods: POST, OPTIONS',
        'Access-Control-Allow-Headers: Authorization, Content-Type, Accept',
        'Access-Control-Max-Age: 86400',
    }
    local origin = cors_allow_origin(request)

    if origin ~= nil then
        table.insert(headers, 'Access-Control-Allow-Origin: ' .. origin)
        table.insert(headers, 'Vary: Origin')
    end

    return headers
end

local function cors_headers_from_buffer(buffer)
    if type(buffer) ~= 'string' or buffer == '' then
        return cors_headers(nil)
    end

    local request = {
        headers = {},
    }

    for line in buffer:gmatch('([^\r\n]+)') do
        if line == '' then
            break
        end

        local name, value = line:match('^([^:]+):%s*(.*)$')
        if name ~= nil and value ~= nil then
            request.headers[name:lower()] = value
        end
    end

    return cors_headers(request)
end

local function probe_host_for(bound, configured)
    local host = bound or configured

    if host == nil then
        return host
    end

    if host == '0.0.0.0' then
        return '127.0.0.1'
    end

    local normalized = host
    if normalized:sub(1, 1) == '[' and normalized:sub(-1) == ']' then
        normalized = normalized:sub(2, -2)
    end

    if normalized == '::' or normalized == '0:0:0:0:0:0:0:0' then
        return '::1'
    end

    return host
end

local function send_json_response(client, status, body, keep_alive, http_version, content_type, extra_headers)
    local headers = {
        'Content-Type: ' .. (content_type or 'application/json'),
    }

    for _, header in ipairs(extra_headers or {}) do
        table.insert(headers, header)
    end

    send_response(client, status, body, headers, keep_alive, http_version)
end

local function connection_has_token(connection, target)
    for token in connection:lower():gmatch('[^,]+') do
        if vim.trim(token) == target then
            return true
        end
    end

    return false
end

local function should_keep_alive(request)
    if request.connection_reusable == false then
        return false
    end

    local connection = request.headers.connection
    local version = request.http_version or 'HTTP/1.1'

    if type(connection) == 'string' then
        if connection_has_token(connection, 'close') then
            return false
        end
        if connection_has_token(connection, 'keep-alive') then
            return true
        end
    end

    return version == 'HTTP/1.1'
end

---@param response table|nil
---@return integer
local function http_status_for_jsonrpc_response(_response)
    return 200
end

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

local function parse_request(raw)
    if raw == '' then
        return nil
    end

    local header_start, header_finish = raw:find('\r\n\r\n', 1, true)
    local newline = '\r\n'

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
        return nil
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

local function request_bearer_token(request)
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

local function snapshot_request(request)
    return {
        method = request.method,
        path = request.path,
        http_version = request.http_version,
        body = request.body,
        headers = deepcopy(request.headers),
    }
end

local function normalize_media_type(value)
    if type(value) ~= 'string' then
        return nil
    end

    local media_type = vim.trim(value):match('^[^;]+')
    if media_type == nil or media_type == '' then
        return nil
    end

    return media_type:lower()
end

local function parse_qvalue(value)
    if value == nil then
        return 1
    end

    local number = tonumber(vim.trim(value))
    if number == nil or number < 0 then
        return 0
    end

    if number > 1 then
        return 1
    end

    return number
end

local function parse_media_range(value)
    if type(value) ~= 'string' then
        return nil
    end

    local media_type = nil
    local q = 1

    for part in value:gmatch('[^;]+') do
        local trimmed = vim.trim(part)

        if media_type == nil then
            media_type = trimmed:lower()
        else
            local name, param_value = trimmed:match('^([^=]+)=(.*)$')
            if name ~= nil and name:lower() == 'q' then
                q = parse_qvalue(param_value)
            end
        end
    end

    if media_type == nil or media_type == '' then
        return nil
    end

    local main_type, sub_type = media_type:match('^([^/]+)/([^/]+)$')
    if main_type == nil or sub_type == nil then
        return nil
    end

    return {
        media_type = media_type,
        main_type = main_type,
        sub_type = sub_type,
        q = q,
    }
end

local function content_type_match_specificity(media_range, content_type)
    if media_range == nil then
        return nil
    end

    local normalized_content_type = normalize_media_type(content_type)
    if normalized_content_type == nil then
        return nil
    end

    if media_range.media_type == normalized_content_type then
        return 3
    end

    local content_main, content_sub = normalized_content_type:match('^([^/]+)/([^/]+)$')
    if content_main == nil or content_sub == nil then
        return nil
    end

    if media_range.main_type == content_main and media_range.sub_type == content_sub then
        return 2
    end

    local media_suffix = media_range.sub_type:match('^%*%+(.+)$')
    local content_suffix = content_sub:match('%+(.+)$')
    if media_range.main_type == content_main and media_suffix ~= nil and media_suffix == content_suffix then
        return 1
    end

    if media_range.main_type == content_main and media_range.sub_type == '*' then
        return 0
    end

    if media_range.main_type == '*' and media_range.sub_type == '*' then
        return -1
    end

    return nil
end

local function content_type_is_json(content_type)
    local normalized_content_type = normalize_media_type(content_type)
    if normalized_content_type == nil then
        return false
    end

    local media_type = vim.trim(normalized_content_type:match('^[^;]+') or '')

    return media_type == 'application/json'
        or media_type:match('^application/.+%+json$') ~= nil
end

local function content_type_preference(accept_header, content_type)
    if accept_header == nil then
        return {
            acceptable = true,
            q = 1,
            specificity = 0,
            position = math.huge,
        }
    end

    if type(accept_header) ~= 'string' then
        return {
            acceptable = false,
        }
    end

    if vim.trim(accept_header) == '' then
        return {
            acceptable = true,
            q = 1,
            specificity = 0,
            position = math.huge,
        }
    end

    local best_q = nil
    local best_specificity = nil
    local best_position = nil
    local blocked_specificity = nil

    local position = 0
    for value in accept_header:gmatch('[^,]+') do
        position = position + 1
        local media_range = parse_media_range(value)
        local specificity = content_type_match_specificity(media_range, content_type)

        if specificity ~= nil then
            if media_range.q == 0 then
                if blocked_specificity == nil or specificity > blocked_specificity then
                    blocked_specificity = specificity
                end
            elseif
                best_specificity == nil
                or specificity > best_specificity
                or (specificity == best_specificity and media_range.q > best_q)
                or (specificity == best_specificity and media_range.q == best_q and position < best_position)
            then
                best_specificity = specificity
                best_q = media_range.q
                best_position = position
            end
        end
    end

    if blocked_specificity ~= nil and best_specificity ~= nil and blocked_specificity == best_specificity then
        return {
            acceptable = false,
        }
    end

    return {
        acceptable = best_q ~= nil,
        q = best_q,
        specificity = best_specificity,
        position = best_position,
    }
end

local function content_type_excluded(accept_header, content_type)
    if type(accept_header) ~= 'string' or vim.trim(accept_header) == '' then
        return false
    end

    local blocked_specificity = nil

    for value in accept_header:gmatch('[^,]+') do
        local media_range = parse_media_range(value)
        local specificity = content_type_match_specificity(media_range, content_type)

        if specificity ~= nil and media_range.q == 0 then
            if blocked_specificity == nil or specificity > blocked_specificity then
                blocked_specificity = specificity
            end
        end
    end

    return blocked_specificity ~= nil and blocked_specificity >= 2
end

local function accepts_content_type(accept_header, content_type)
    return content_type_preference(accept_header, content_type).acceptable
end

local function negotiate_response_content_type(accept_header)
    local candidates = {
        { response = 'application/json', aliases = { 'application/*+json', '*/*' } },
    }

    local best_content_type = nil
    local best_q = nil
    local best_specificity = nil
    local best_position = nil

    for _, candidate in ipairs(candidates) do
        if content_type_excluded(accept_header, candidate.response) then
            goto continue
        end

        local preference = content_type_preference(accept_header, candidate.response)

        if not preference.acceptable then
            preference = nil
        end

        for _, alias in ipairs(candidate.aliases) do
            local alias_preference = content_type_preference(accept_header, alias)

            if
                alias_preference.acceptable
                and (
                    preference == nil
                    or alias_preference.specificity > preference.specificity
                    or (alias_preference.specificity == preference.specificity and alias_preference.q > preference.q)
                    or (
                        alias_preference.specificity == preference.specificity
                        and alias_preference.q == preference.q
                        and alias_preference.position < preference.position
                    )
                )
            then
                preference = alias_preference
            end
        end

        if
            preference ~= nil
            and preference.acceptable
            and (
                best_content_type == nil
                or preference.specificity > best_specificity
                or (preference.specificity == best_specificity and preference.q > best_q)
                or (
                    preference.specificity == best_specificity
                    and preference.q == best_q
                    and preference.position < best_position
                )
            )
        then
            best_content_type = candidate.response
            best_q = preference.q
            best_specificity = preference.specificity
            best_position = preference.position
        end

        ::continue::
    end

    return best_content_type
end

local function invalid_request_response(id)
    return {
        jsonrpc = '2.0',
        id = id == nil and vim.NIL or id,
        error = {
            code = -32600,
            message = 'Invalid Request',
        },
    }
end

local function parse_error_response(message, id)
    return {
        jsonrpc = '2.0',
        id = id == nil and vim.NIL or id,
        error = {
            code = -32700,
            message = tostring(message),
        },
    }
end

local function batch_response_status(responses)
    if type(responses) ~= 'table' then
        return 200
    end

    for _, response in ipairs(responses) do
        local status = http_status_for_jsonrpc_response(response)
        if status >= 400 then
            return status
        end
    end

    return 200
end

local function dispatch_jsonrpc_message(message)
    if type(message) ~= 'table' then
        return invalid_request_response(vim.NIL)
    end

    if vim.tbl_islist(message) then
        if vim.tbl_isempty(message) then
            return invalid_request_response(vim.NIL)
        end

        local responses = {}

        for _, entry in ipairs(message) do
            local response

            if type(entry) ~= 'table' or vim.tbl_islist(entry) then
                response = invalid_request_response(vim.NIL)
            else
                response = dispatch_jsonrpc_message(entry)
            end

            if response ~= nil then
                table.insert(responses, response)
            end
        end

        return next(responses) ~= nil and responses or nil
    end

    if message.jsonrpc ~= '2.0' or type(message.method) ~= 'string' then
        return invalid_request_response(message.id)
    end

    if message.params ~= nil and type(message.params) ~= 'table' then
        return invalid_request_response(message.id)
    end

    return router.handle_request(message.method, message.params, message.id, {})
end

local function is_cors_preflight_request(request)
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

local function handle_http_request(client, request)
    if client:is_closing() then
        return
    end

    local keep_alive = should_keep_alive(request)
    local http_version = request.http_version
    local response_headers = cors_headers(request)

    if request.path ~= '/mcp' then
        send_json_response(
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
        send_response(client, 505, '', nil, false, 'HTTP/1.1')
        return
    end

    if is_cors_preflight_request(request) then
        send_response(client, 204, '', response_headers, keep_alive, http_version)
        return
    end

    if has_session_http_token() and not constant_time_equals(request_bearer_token(request), session_http_token) then
        send_json_response(
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
        send_json_response(
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
    local response_content_type = negotiate_response_content_type(accept_header)

    if response_content_type == nil then
        send_json_response(
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
    if content_type == nil or not content_type_is_json(content_type) then
        send_json_response(
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
        send_json_response(
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
        local response = invalid_request_response(vim.NIL)
        send_json_response(
            client,
            http_status_for_jsonrpc_response(response),
            vim.json.encode(response),
            keep_alive,
            http_version,
            response_content_type,
            response_headers
        )
        return
    end

    local response = dispatch_jsonrpc_message(message)
    if response == nil then
        send_response(client, 204, '', response_headers, keep_alive, http_version)
        return
    end

    local encoded = vim.json.encode(response)
    local status = vim.tbl_islist(response) and batch_response_status(response)
        or http_status_for_jsonrpc_response(response)

    send_json_response(client, status, encoded, keep_alive, http_version, response_content_type, response_headers)
end

function M._start_client_read(client, initial_buffer)
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
            local request, consumed_or_err, parse_err = parse_request(buffer)

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
                    send_response(client, 505, '', nil, false, 'HTTP/1.1')
                    return
                end

                local response = parse_error_response(effective_err, vim.NIL)
                local response_headers = cors_headers_from_buffer(buffer)
                buffer = ''
                sync_buffer()
                send_json_response(
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
            handle_http_request(client, request)

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
            close_client(client)
            return
        end

        reading = true
        client:read_start(function(err, data)
            reading = false
            if err ~= nil then
                notify_error('mcp http read error: ' .. tostring(err), vim.log.levels.WARN)
                close_client(client)
                return
            end

            if data == nil then
                close_client(client)
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

---@return boolean, string?
function M.start()
    local descriptor = endpoint.describe_http()

    if server ~= nil and not server:is_closing() then
        if startup_pending then
            local same_port = bound_port == descriptor.http_port or (descriptor.http_port == 0 and bound_port == 0)
            local same_host = bound_host == descriptor.http_host or bound_host == nil or descriptor.http_host == nil

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
    server = assert(vim.uv.new_tcp())
    local ok, err = server:bind(descriptor.http_host, descriptor.http_port)

    if ok ~= 0 then
        if not server:is_closing() then
            server:close()
        end
        server = nil
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
        startup_pending = false
        startup_error = tostring(listen_err)
        return false, startup_error
    end

    local probe_host = probe_host_for(bound_host, descriptor.http_host)
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
