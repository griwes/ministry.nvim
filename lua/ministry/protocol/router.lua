local dispatch = require('ministry.protocol.dispatch')
local registry = require('ministry.core.registry')

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

---@param name string
---@return string?, string?
local function split_qualified_tool_name(name)
    if type(name) ~= 'string' then
        return nil, nil
    end

    local server_name, tool_name = name:match('^([^/]+)/(.+)$')
    return server_name, tool_name
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

---@param name string
---@param server string
---@param tool string
---@return boolean
local function split_routing_matches_name(name, server, tool)
    local name_server, name_tool = split_qualified_tool_name(name)
    if name_server == nil or name_tool == nil then
        return false
    end

    return name_server == server and (name_tool == tool or name_tool == normalize_split_tool_name(tool))
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
        local normalized = vim.deepcopy(result)
        local contents = normalized.contents
        if type(contents) == 'table' and vim.islist(contents) == false then
            contents = { contents }
        end

        if type(contents) ~= 'table' or vim.islist(contents) == false then
            error('ministry.nvim resource read must return contents as a list')
        end

        normalized.contents = contents
        return normalized
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
---@param prompt table
---@return table
local function prompt_get_result(result, prompt)
    local normalized
    if type(result) == 'table' then
        normalized = vim.deepcopy(result)
    else
        normalized = {
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

    normalized.name = prompt.name
    normalized.description = prompt.description

    return normalized
end

local function json_safe_warning_value(value, seen)
    local value_type = type(value)

    if
        value == vim.NIL
        or value_type == 'nil'
        or value_type == 'boolean'
        or value_type == 'number'
        or value_type == 'string'
    then
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
            name = 'ministry.nvim',
            title = 'ministry.nvim',
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

    if method == 'notifications/cancelled' then
        local request_id = type(params) == 'table' and params.requestId or nil
        if request_id ~= nil and type(context) == 'table' and type(context.cancel_request) == 'function' then
            context.cancel_request(
                request_id,
                type(params.reason) == 'string' and params.reason or 'cancelled by client'
            )
        end
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

        local handler_request = vim.deepcopy(request)
        handler_request.uri = resource.uri
        handler_request.namespaced_uri = request.uri

        local ok, result, handler_err = pcall(resource.handler, handler_request, context or {})

        if not ok then
            return error_response(id, -32000, result or 'ministry.nvim resource read failed')
        end

        if handler_err ~= nil then
            return error_response(
                id,
                handler_err.code or -32000,
                handler_err.message or 'ministry.nvim resource read failed'
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

    if method == 'resources/templates/read' then
        local request = params or {}
        local resource_template, template_arguments, err = registry.find_resource_template(request.uri or '')

        if err ~= nil then
            return error_response(id, -32602, err)
        end

        local handler_request = vim.deepcopy(request)
        handler_request.arguments = template_arguments
        for key, value in pairs(template_arguments or {}) do
            handler_request[key] = value
        end

        local ok, result, handler_err = pcall(resource_template.handler, handler_request, context or {})

        if not ok then
            return error_response(id, -32000, result or 'ministry.nvim resource template read failed')
        end

        if handler_err ~= nil then
            return error_response(
                id,
                handler_err.code or -32000,
                handler_err.message or 'ministry.nvim resource template read failed'
            )
        end

        local response = resource_read_result(result)
        for _, item in ipairs(response.contents or {}) do
            if item.uri == nil or item.uri == '' then
                item.uri = request.uri
            end

            if item.mimeType == nil and resource_template.mime_type ~= nil then
                item.mimeType = resource_template.mime_type
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

        local handler_request = vim.deepcopy(request)
        handler_request.name = prompt.name
        handler_request.namespaced_name = request.name

        local ok, result, handler_err = pcall(prompt.handler, handler_request, context or {})

        if not ok then
            return error_response(id, -32000, result or 'ministry.nvim prompt get failed')
        end

        if handler_err ~= nil then
            return error_response(
                id,
                handler_err.code or -32000,
                handler_err.message or 'ministry.nvim prompt get failed'
            )
        end

        return success_response(id, prompt_get_result(result, prompt))
    end

    if method == 'tools/call' then
        local request = params or {}
        local tool_name = request.name
        local server_name, split_tool_name = extract_server_and_tool(request)

        local used_split_tool_routing = false

        if tool_name == nil and server_name ~= nil and split_tool_name ~= nil then
            used_split_tool_routing = true
            local exact_tool_name = split_tool_name
            local exact_namespaced_tool_name
            if is_already_qualified_tool_name(exact_tool_name, server_name) then
                exact_namespaced_tool_name = exact_tool_name
            else
                exact_namespaced_tool_name = string.format('%s/%s', server_name, exact_tool_name)
            end

            local exact_tool = registry.find_tool(exact_namespaced_tool_name, { allow_flattened_fallback = false })
            if exact_tool ~= nil then
                tool_name = exact_namespaced_tool_name
            else
                split_tool_name = normalize_split_tool_name(split_tool_name)
                if is_already_qualified_tool_name(split_tool_name, server_name) then
                    tool_name = split_tool_name
                else
                    tool_name = string.format('%s/%s', server_name, split_tool_name)
                end
            end
        elseif tool_name ~= nil and (server_name ~= nil or split_tool_name ~= nil) then
            if server_name == nil or split_tool_name == nil then
                return error_response(id, -32602, 'Missing tool identifier')
            end
            if not split_routing_matches_name(tool_name, server_name, split_tool_name) then
                return error_response(id, -32602, 'Conflicting tool identifiers')
            end
        end

        if tool_name == nil or tool_name == '' then
            return error_response(id, -32602, 'Missing tool identifier')
        end

        if request.name == nil and (server_name == nil or split_tool_name == nil) then
            return error_response(id, -32602, 'Missing tool identifier')
        end

        if used_split_tool_routing then
            local tool, lookup_err = registry.find_tool(tool_name, { allow_flattened_fallback = false })
            if lookup_err ~= nil then
                return error_response(id, -32602, lookup_err)
            end
            if tool ~= nil and tool.name ~= nil and not is_already_qualified_tool_name(tool_name, server_name) then
                tool_name = string.format('%s/%s', server_name, tool.name)
            end
        end

        local result, err, warning = dispatch.call_tool(tool_name, request.arguments, context)

        if err ~= nil then
            return error_response(id, err.code or -32000, err.message or 'ministry.nvim tool call failed')
        end

        return success_response(id, tool_call_result(result, warning))
    end

    return error_response(id, -32601, string.format('Method not found: %s', tostring(method)))
end

return M
