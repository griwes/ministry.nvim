local dispatch = require('mcp.dispatch')
local registry = require('mcp.registry')

local M = {}

local SUPPORTED_PROTOCOL_VERSIONS = {
    ['2025-06-18'] = true,
}

local DEFAULT_PROTOCOL_VERSION = '2025-06-18'

---@param request table
---@return string?, string?
local function extract_server_and_tool(request)
    local server = request.server or request.serverName
    local tool = request.tool or request.toolName

    return server, tool
end

local function success_response(id, result)
    return {
        jsonrpc = '2.0',
        id = id,
        result = result,
    }
end

local function error_response(id, code, message)
    return {
        jsonrpc = '2.0',
        id = id,
        error = {
            code = code,
            message = message,
        },
    }
end

---@param tool_name string
---@param server_name string
---@return boolean
local function is_already_qualified_tool_name(tool_name, server_name)
    if tool_name == server_name then
        return true
    end

    local first_segment = tool_name:match('^([^/]+)/')
    return first_segment == server_name
end

---@param tool_name string
---@return string
local function normalize_split_tool_name(tool_name)
    if type(tool_name) ~= 'string' then
        return tool_name
    end

    if tool_name:find('/', 1, true) ~= nil then
        return tool_name
    end

    return tool_name:gsub('__', '/')
end

---@param value any
---@return boolean
local function is_content_list(value)
    if type(value) ~= 'table' or vim.islist(value) == false then
        return false
    end

    for _, item in ipairs(value) do
        if type(item) ~= 'table' or type(item.type) ~= 'string' then
            return false
        end
    end

    return true
end

---@param result any
---@return table

local function resource_read_result(result)
    if type(result) == 'table' and result.contents ~= nil then
        return result
    end

    local text
    if type(result) == 'string' then
        text = result
    else
        text = vim.json.encode(result or {})
    end

    return {
        contents = {
            {
                uri = '',
                text = text,
            },
        },
    }
end

---@param result any
---@return table
local function prompt_get_result(result)
    if type(result) == 'table' then
        return result
    end

    return {
        messages = {
            {
                role = 'user',
                content = {
                    type = 'text',
                    text = type(result) == 'string' and result or vim.json.encode(result or {}),
                },
            },
        },
    }
end


local function json_safe_warning_value(value, seen)
    local value_type = type(value)

    if value == vim.NIL or value_type == 'nil' or value_type == 'boolean' or value_type == 'number' or value_type == 'string' then
        return value
    end

    if value_type ~= 'table' then
        return tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        return '<cycle>'
    end

    seen[value] = true

    local sanitized = {}
    local list_length = 0

    while rawget(value, list_length + 1) ~= nil do
        list_length = list_length + 1
        sanitized[list_length] = json_safe_warning_value(value[list_length], seen)
    end

    for key, item in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key > list_length or key % 1 ~= 0 then
            local safe_key = key
            local key_type = type(key)
            if key_type ~= 'string' and key_type ~= 'number' then
                safe_key = tostring(key)
            end
            sanitized[safe_key] = json_safe_warning_value(item, seen)
        end
    end

    seen[value] = nil
    return sanitized
end

local function sanitize_warning(warning)
    if warning == nil then
        return nil
    end

    return json_safe_warning_value(warning)
end

local function tool_call_result(result, warning)
    if type(result) == 'table' then
        if is_content_list(result.content) then
            if warning == nil then
                return result
            end

            local response = vim.tbl_extend('keep', { warning = sanitize_warning(warning) }, result)
            return response
        end

        if is_content_list(result) then
            local response = {
                content = result,
            }

            if warning ~= nil then
                response.warning = sanitize_warning(warning)
            end

            return response
        end
    end

    local text
    if type(result) == 'string' then
        text = result
    else
        text = vim.json.encode(result or {})
    end

    local response = {
        content = {
            {
                type = 'text',
                text = text,
            },
        },
    }

    if warning ~= nil then
        response.warning = sanitize_warning(warning)
    end

    return response
end

---@param params table|nil
---@return table|nil, table|nil
local function initialize_result(params)
    local request = params or {}
    local requested_version = request.protocolVersion

    if requested_version ~= nil and SUPPORTED_PROTOCOL_VERSIONS[requested_version] ~= true then
        return nil,
            {
                code = -32602,
                message = string.format('Unsupported protocol version: %s', tostring(requested_version)),
            }
    end

    return {
        protocolVersion = DEFAULT_PROTOCOL_VERSION,
        capabilities = {
            tools = {
                listChanged = false,
            },
            resources = {
                listChanged = false,
            },
            prompts = {
                listChanged = false,
            },
        },
        serverInfo = {
            name = 'mcp.nvim',
            title = 'mcp.nvim',
            version = '0.1.0-dev',
        },
    },
        nil
end

---@param method string|nil
---@param params table|nil
---@param id integer|string|nil
---@param context table|nil
---@return table|nil
function M.handle_request(method, params, id, context)
    if method == 'initialize' then
        local result, err = initialize_result(params)

        if err ~= nil then
            return error_response(id, err.code, err.message)
        end

        return success_response(id, result)
    end

    if method == 'notifications/initialized' then
        return nil
    end

    if method == 'tools/list' then
        return success_response(id, {
            tools = registry.list_tool_descriptors(),
        })
    end

    if method == 'resources/list' then
        return success_response(id, {
            resources = registry.list_resource_descriptors(),
        })
    end

    if method == 'prompts/list' then
        return success_response(id, {
            prompts = registry.list_prompt_descriptors(),
        })
    end

    if method == 'resources/templates/list' then
        return success_response(id, {
            resourceTemplates = registry.list_resource_template_descriptors(),
        })
    end

    if method == 'resources/read' then
        local request = params or {}
        local resource, err = registry.find_resource(request.uri or '')

        if err ~= nil then
            return error_response(id, -32602, err)
        end

        local handler_request = vim.tbl_extend('force', {}, request, {
            uri = resource.uri,
            namespaced_uri = request.uri,
        })

        local result, handler_err = resource.handler(handler_request, context or {})

        if handler_err ~= nil then
            return error_response(
                id,
                handler_err.code or -32000,
                handler_err.message or 'mcp.nvim resource read failed'
            )
        end

        local response = resource_read_result(result)
        for _, item in ipairs(response.contents or {}) do
            if item.uri == nil or item.uri == '' then
                item.uri = handler_request.namespaced_uri
            end

            if item.mimeType == nil and resource.mime_type ~= nil then
                item.mimeType = resource.mime_type
            end
        end

        return success_response(id, response)
    end

    if method == 'prompts/get' then
        local request = params or {}
        local prompt, err = registry.find_prompt(request.name or '')

        if err ~= nil then
            return error_response(id, -32602, err)
        end

        local handler_request = vim.tbl_extend('force', {}, request, {
            name = prompt.name,
            namespaced_name = request.name,
        })

        local result, handler_err = prompt.handler(handler_request, context or {})

        if handler_err ~= nil then
            return error_response(id, handler_err.code or -32000, handler_err.message or 'mcp.nvim prompt get failed')
        end

        return success_response(id, prompt_get_result(result))
    end

    if method == 'tools/call' then
        local request = params or {}
        local tool_name = request.name
        local server_name, split_tool_name = extract_server_and_tool(request)

        local used_split_tool_routing = false

        if tool_name == nil and server_name ~= nil and split_tool_name ~= nil then
            used_split_tool_routing = true
            split_tool_name = normalize_split_tool_name(split_tool_name)
            if is_already_qualified_tool_name(split_tool_name, server_name) then
                tool_name = split_tool_name
            else
                tool_name = string.format('%s/%s', server_name, split_tool_name)
            end
        end

        if tool_name == nil or tool_name == '' then
            return error_response(id, -32602, 'Missing tool identifier')
        end

        if request.name == nil and (server_name == nil or split_tool_name == nil) then
            return error_response(id, -32602, 'Missing tool identifier')
        end

        if used_split_tool_routing then
            local _, lookup_err = registry.find_tool(tool_name)
            if lookup_err ~= nil then
                return error_response(id, -32602, lookup_err)
            end
        end

        local result, err, warning = dispatch.call_tool(tool_name, request.arguments, context)

        if err ~= nil then
            return error_response(id, err.code or -32000, err.message or 'mcp.nvim tool call failed')
        end

        return success_response(id, tool_call_result(result, warning))
    end

    return error_response(id, -32601, string.format('Method not found: %s', tostring(method)))
end

return M
