local config = require('ministry.core.config')
local endpoint = require('ministry.transport.endpoint')

local M = {}

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

    local mapped_ipv4_tail = address:match('^::ffff:(%d+%.%d+%.%d+%.%d+)$')
    if mapped_ipv4_tail ~= nil then
        if not is_valid_ipv4_literal(mapped_ipv4_tail) then
            return nil
        end

        return {
            address = address,
            zone_id = zone_id,
        }
    end

    local mapped_upper, mapped_lower = address:match('^::ffff:(%x+):(%x+)$')
    if mapped_upper ~= nil and mapped_lower ~= nil then
        local upper = tonumber(mapped_upper, 16)
        local lower = tonumber(mapped_lower, 16)
        if upper == nil or lower == nil or upper < 0 or upper > 0xFFFF or lower < 0 or lower > 0xFFFF then
            return nil
        end

        return {
            address = address,
            zone_id = zone_id,
        }
    end

    if not is_valid_ipv6_literal(address) then
        return nil
    end

    return {
        address = address,
        zone_id = zone_id,
    }
end

local function is_localhost_origin_host(host)
    if type(host) ~= 'string' or host == '' then
        return false
    end

    local lowered_host = host:lower()
    if lowered_host:match('^::ffff:127%.') ~= nil then
        return true
    end

    local mapped_upper, mapped_lower = lowered_host:match('^::ffff:(%x+):(%x+)$')
    if mapped_upper ~= nil and mapped_lower ~= nil then
        local upper = tonumber(mapped_upper, 16)
        local lower = tonumber(mapped_lower, 16)
        if upper ~= nil and lower ~= nil then
            return math.floor(upper / 256) == 127 and upper % 256 == 0 and lower >= 0 and lower <= 65535
        end
    end

    if lowered_host == 'localhost' then
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

        local ipv4_tail = normalized_host:match('^::ffff:(.+)$') or normalized_host:match('^0:0:0:0:0:ffff:(.+)$')
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

local function is_localhost_alias_origin_host(host)
    if type(host) ~= 'string' or host == '' then
        return false
    end

    local lowered_host = host:lower()
    if lowered_host == 'localhost' or lowered_host == '127.0.0.1' then
        return true
    end

    local parsed_ipv6 = parse_ipv6_origin_host(host)
    if parsed_ipv6 == nil then
        return false
    end

    local normalized_host = parsed_ipv6.address:lower()
    if normalized_host == '::1' then
        return true
    end

    local ipv4_tail = normalized_host:match('^::ffff:(.+)$') or normalized_host:match('^0:0:0:0:0:ffff:(.+)$')
    if ipv4_tail == '127.0.0.1' then
        return true
    end

    local first_group, second_group = nil, nil
    if ipv4_tail ~= nil then
        first_group, second_group = ipv4_tail:match('^(%x+):(%x+)$')
    end
    if first_group ~= nil and second_group ~= nil then
        local upper = tonumber(first_group, 16)
        local lower = tonumber(second_group, 16)
        return upper == 0x7f00 and lower == 0x0001
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

local function parse_authority_host(authority)
    if type(authority) ~= 'string' then
        return nil
    end

    authority = vim.trim(authority)
    if authority == '' or authority:find('@', 1, true) ~= nil then
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

    return normalize_origin_host(host)
end

local function parse_cors_origin(request)
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

    local normalized_host = parse_authority_host(authority)
    if normalized_host == nil then
        return nil
    end

    return {
        origin = origin,
        scheme = scheme:lower(),
        normalized_host = normalized_host,
        parsed_ipv6 = parse_ipv6_origin_host(normalized_host),
    }
end

local function cors_allowed_host(request, state)
    if
        state.server ~= nil
        and not state.server:is_closing()
        and type(state.bound_host) == 'string'
        and state.bound_host ~= ''
    then
        return normalize_origin_host(state.bound_host)
    end

    if type(state.requested_host) == 'string' and state.requested_host ~= '' then
        return normalize_origin_host(state.requested_host)
    end

    local configured_host = nil
    local applied_config = config.get()
    if type(applied_config) == 'table' then
        if applied_config.transport == 'http' then
            configured_host = applied_config.http_host
        elseif
            type(applied_config.transport) == 'table'
            and applied_config.transport.type == 'http'
            and type(applied_config.transport.http) == 'table'
        then
            configured_host = applied_config.transport.http.host
        end
    end

    local normalized_descriptor_host = nil
    if type(configured_host) == 'string' and configured_host ~= '' then
        normalized_descriptor_host = normalize_origin_host(configured_host)
    else
        local descriptor_host = endpoint.describe_http().http_host
        if type(descriptor_host) == 'string' and descriptor_host ~= '' then
            normalized_descriptor_host = normalize_origin_host(descriptor_host)
        end
    end

    if
        type(normalized_descriptor_host) == 'string'
        and normalized_descriptor_host ~= ''
        and normalized_descriptor_host ~= '0.0.0.0'
        and normalized_descriptor_host ~= '::'
        and normalized_descriptor_host:lower() ~= 'localhost'
        and not is_localhost_origin_host(normalized_descriptor_host)
    then
        return normalized_descriptor_host
    end

    local request_host = parse_authority_host(request and request.headers and request.headers.host)
    if request_host ~= nil then
        return request_host
    end

    return normalized_descriptor_host
end

local function cors_allow_origin(request, state)
    local parsed_origin = parse_cors_origin(request)
    if parsed_origin == nil then
        return nil, nil
    end

    local allowed_host = cors_allowed_host(request, state)
    if allowed_host == nil then
        return nil, parsed_origin.origin
    end

    local normalized_host = parsed_origin.normalized_host
    local normalized_allowed_host = allowed_host
    local parsed_origin_ipv6 = parsed_origin.parsed_ipv6
    local parsed_allowed_ipv6 = parse_ipv6_origin_host(normalized_allowed_host)

    local allow_any_loopback_origin = normalized_allowed_host == '0.0.0.0'
        or normalized_allowed_host == '::'
        or normalized_allowed_host:lower() == 'localhost'
    local allow_localhost_alias_origin = normalized_allowed_host == '127.0.0.1' or normalized_allowed_host == '::1'

    if allow_any_loopback_origin then
        if not is_localhost_origin_host(normalized_host) then
            if parsed_origin.scheme == 'http' then
                return nil, nil
            end
            return nil, parsed_origin.origin
        end
    elseif allow_localhost_alias_origin then
        if not is_localhost_alias_origin_host(normalized_host) then
            if parsed_origin.scheme == 'http' then
                return nil, nil
            end
            return nil, parsed_origin.origin
        end
    elseif parsed_origin_ipv6 ~= nil and parsed_allowed_ipv6 ~= nil then
        if parsed_origin_ipv6.address:lower() ~= parsed_allowed_ipv6.address:lower() then
            return nil, parsed_origin.origin
        end

        local origin_zone_id = parsed_origin_ipv6.zone_id
        local allowed_zone_id = parsed_allowed_ipv6.zone_id
        if origin_zone_id ~= nil or allowed_zone_id ~= nil then
            if origin_zone_id == nil or allowed_zone_id == nil then
                return nil, parsed_origin.origin
            end

            if origin_zone_id:lower() ~= allowed_zone_id:lower() then
                return nil, parsed_origin.origin
            end
        end
    elseif normalized_host:lower() ~= normalized_allowed_host:lower() then
        return nil, parsed_origin.origin
    end

    return parsed_origin.origin, parsed_origin.origin
end

---@param request table?
---@param state { server: uv_tcp_t?, bound_host: string?, requested_host: string? }
---@return string[]
function M.cors_headers(request, state)
    local headers = {
        'Access-Control-Allow-Methods: POST, OPTIONS',
        'Access-Control-Allow-Headers: Authorization, Content-Type, Accept',
        'Access-Control-Max-Age: 86400',
    }
    local origin, vary_origin = cors_allow_origin(request, state)

    if origin ~= nil then
        table.insert(headers, 'Access-Control-Allow-Origin: ' .. origin)
    end
    if vary_origin ~= nil then
        table.insert(headers, 'Vary: Origin')
    end

    return headers
end

---@param buffer string?
---@param state { server: uv_tcp_t?, bound_host: string?, requested_host: string? }
---@return string[]
function M.cors_headers_from_buffer(buffer, state)
    if type(buffer) ~= 'string' or buffer == '' then
        return M.cors_headers(nil, state)
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

    return M.cors_headers(request, state)
end

return M
