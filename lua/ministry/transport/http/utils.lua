local M = {}

---@param host string?
---@return boolean
function M.is_loopback_host(host)
    if type(host) ~= 'string' then
        return false
    end

    local normalized = vim.trim(host):lower()
    if normalized:sub(1, 1) == '[' and normalized:sub(-1) == ']' then
        normalized = normalized:sub(2, -2)
    end

    if normalized == 'localhost' or normalized == 'localhost.' or normalized == '::1' then
        return true
    end

    if normalized == '0:0:0:0:0:0:0:1' then
        return true
    end

    local first_octet = normalized:match('^(%d+)%.%d+%.%d+%.%d+$')
    return tonumber(first_octet) == 127
end

---@param left any
---@param right any
---@return boolean
function M.constant_time_equals(left, right)
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

---@param bound string?
---@param configured string?
---@return string?
function M.probe_host_for(bound, configured)
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

local function connection_has_token(connection, target)
    for token in connection:lower():gmatch('[^,]+') do
        if vim.trim(token) == target then
            return true
        end
    end

    return false
end

---@param request table
---@return boolean
function M.should_keep_alive(request)
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

return M
