local M = {}

---@type table<string, mcp.ServerSpec>
local servers = {}

local function deepcopy(value)
    return vim.deepcopy(value)
end

---@param server mcp.ServerSpec
local function validate_server(server)
    assert(type(server) == 'table', 'mcp server spec must be a table')
    assert(type(server.name) == 'string' and server.name ~= '', 'mcp server name must be a non-empty string')
end

---@param server_name string
---@return mcp.ServerSpec
local function ensure_server(server_name)
    local server = servers[server_name]
    assert(server ~= nil, string.format('Unknown mcp server: %s', server_name))
    return server
end

---@param items table[]|nil
---@return table[]
local function normalized_items(items)
    return deepcopy(items or {})
end

---@param tool mcp.ToolSpec
---@return mcp.ToolSpec
local function normalize_tool_schema_fields(tool)
    if type(tool) ~= 'table' then
        return tool
    end

    if tool.input_schema == nil and tool.inputSchema ~= nil then
        tool.input_schema = tool.inputSchema
    end

    return tool
end

---@param value table
---@return boolean
local function looks_like_tool_spec(value)
    if type(value) ~= 'table' or vim.islist(value) then
        return false
    end

    if value.handler ~= nil then
        return true
    end

    if type(value.handler) == 'function' then
        return true
    end

    return value.name ~= nil or value.description ~= nil or value.input_schema ~= nil
end

---@param prefix string[]
---@param tree table
---@param output mcp.ToolSpec[]
local function flatten_tool_tree(prefix, tree, output)
    for key, value in pairs(tree) do
        assert(type(key) == 'string' and key ~= '', 'nested tool keys must be non-empty strings')

        local next_prefix = deepcopy(prefix)
        table.insert(next_prefix, key)

        if looks_like_tool_spec(value) then
            local tool = deepcopy(value)
            normalize_tool_schema_fields(tool)
            tool.name = table.concat(next_prefix, '/')
            table.insert(output, tool)
        else
            assert(type(value) == 'table', 'nested tool namespace entries must be tables')
            flatten_tool_tree(next_prefix, value, output)
        end
    end
end

---@param tool mcp.ToolSpec
local function validate_tool(tool)
    assert(type(tool) == 'table', 'mcp tool spec must be a table')
    assert(type(tool.name) == 'string' and tool.name ~= '', 'mcp tool name must be a non-empty string')
    if tool.handler ~= nil then
        assert(type(tool.handler) == 'function', 'mcp tool handler must be a function')
    end
end

---@param resource mcp.ResourceSpec
local function validate_resource(resource)
    assert(type(resource) == 'table', 'mcp resource spec must be a table')
    assert(type(resource.uri) == 'string' and resource.uri ~= '', 'mcp resource uri must be a non-empty string')
    assert(type(resource.handler) == 'function', 'mcp resource handler must be a function')
end

---@param resource_template mcp.ResourceTemplateSpec
local function validate_resource_template(resource_template)
    assert(type(resource_template) == 'table', 'mcp resource template spec must be a table')
    assert(
        type(resource_template.name) == 'string' and resource_template.name ~= '',
        'mcp resource template name must be a non-empty string'
    )
    assert(
        type(resource_template.uri_template) == 'string' and resource_template.uri_template ~= '',
        'mcp resource template uri_template must be a non-empty string'
    )
    assert(type(resource_template.handler) == 'function', 'mcp resource template handler must be a function')
end

---@param prompt mcp.PromptSpec
local function validate_prompt(prompt)
    assert(type(prompt) == 'table', 'mcp prompt spec must be a table')
    assert(type(prompt.name) == 'string' and prompt.name ~= '', 'mcp prompt name must be a non-empty string')
    assert(type(prompt.handler) == 'function', 'mcp prompt handler must be a function')
end

---@param tools table[]|table|nil
---@return table[]
local function normalize_tools(tools)
    if tools == nil then
        return {}
    end

    if vim.islist(tools) then
        local normalized = normalized_items(tools)
        for _, tool in ipairs(normalized) do
            normalize_tool_schema_fields(tool)
            validate_tool(tool)
        end
        return normalized
    end

    local flattened = {}
    flatten_tool_tree({}, tools, flattened)
    table.sort(flattened, function(left, right)
        return left.name < right.name
    end)

    for _, tool in ipairs(flattened) do
        validate_tool(tool)
    end

    return flattened
end

---@param server mcp.ServerSpec
---@return mcp.ServerSpec
function M.register_server(server)
    validate_server(server)

    local resources = normalized_items(server.resources)
    for _, resource in ipairs(resources) do
        validate_resource(resource)
    end

    local resource_templates = normalized_items(server.resource_templates)
    for _, resource_template in ipairs(resource_templates) do
        validate_resource_template(resource_template)
    end

    local prompts = normalized_items(server.prompts)
    for _, prompt in ipairs(prompts) do
        validate_prompt(prompt)
    end

    local normalized = {
        name = server.name,
        title = server.title,
        description = server.description,
        tools = normalize_tools(server.tools),
        resources = resources,
        resource_templates = resource_templates,
        prompts = prompts,
    }

    servers[server.name] = normalized
    return deepcopy(normalized)
end

---@param server_name string
function M.unregister_server(server_name)
    servers[server_name] = nil
end

---@return mcp.ServerSpec[]
function M.list_servers()
    local items = {}

    for _, server in pairs(servers) do
        table.insert(items, deepcopy(server))
    end

    table.sort(items, function(left, right)
        return left.name < right.name
    end)

    return items
end

---@param server_name string
---@return mcp.ServerSpec?
function M.get_server(server_name)
    local server = servers[server_name]
    if server == nil then
        return nil
    end

    return deepcopy(server)
end

---@param items table[]
---@param item table
---@param matches fun(existing: table, candidate: table): boolean
local function replace_or_append(items, item, matches)
    local normalized = deepcopy(item)
    local retained = {}
    local replaced = false

    for _, existing in ipairs(items) do
        if matches(existing, normalized) then
            if not replaced then
                table.insert(retained, normalized)
                replaced = true
            end
        else
            table.insert(retained, existing)
        end
    end

    if not replaced then
        table.insert(retained, normalized)
    end

    for index = #items, 1, -1 do
        items[index] = nil
    end
    for _, existing in ipairs(retained) do
        table.insert(items, existing)
    end
end

---@param server_name string
---@param tool mcp.ToolSpec
function M.register_tool(server_name, tool)
    local server = ensure_server(server_name)
    assert(type(tool) == 'table', 'mcp tool spec must be a table')
    assert(type(tool.name) == 'string' and tool.name ~= '', 'mcp tool name must be a non-empty string')
    assert(type(tool.handler) == 'function', 'mcp tool handler must be a function')
    replace_or_append(server.tools, tool, function(existing, candidate)
        return existing.name == candidate.name
    end)
end

---@param server_name string
---@param tool_name string
function M.unregister_tool(server_name, tool_name)
    local server = ensure_server(server_name)
    local retained = {}
    for _, tool in ipairs(server.tools or {}) do
        if tool.name ~= tool_name then
            table.insert(retained, tool)
        end
    end
    server.tools = retained
end

---@param server_name string
---@param resource mcp.ResourceSpec
function M.register_resource(server_name, resource)
    local server = ensure_server(server_name)
    validate_resource(resource)
    replace_or_append(server.resources, resource, function(existing, candidate)
        return existing.uri == candidate.uri
    end)
end

---@param server_name string
---@param uri string
function M.unregister_resource(server_name, uri)
    local server = ensure_server(server_name)
    local retained = {}
    for _, resource in ipairs(server.resources or {}) do
        if resource.uri ~= uri then
            table.insert(retained, resource)
        end
    end
    server.resources = retained
end

---@param server_name string
---@param resource_template mcp.ResourceTemplateSpec
function M.register_resource_template(server_name, resource_template)
    local server = ensure_server(server_name)
    validate_resource_template(resource_template)
    replace_or_append(server.resource_templates, resource_template, function(existing, candidate)
        return existing.name == candidate.name or existing.uri_template == candidate.uri_template
    end)
end

---@param server_name string
---@param template_name string
function M.unregister_resource_template(server_name, template_name)
    local server = ensure_server(server_name)
    local retained = {}
    for _, resource_template in ipairs(server.resource_templates or {}) do
        if resource_template.name ~= template_name then
            table.insert(retained, resource_template)
        end
    end
    server.resource_templates = retained
end

---@param server_name string
---@param prompt mcp.PromptSpec
function M.register_prompt(server_name, prompt)
    local server = ensure_server(server_name)
    validate_prompt(prompt)
    replace_or_append(server.prompts, prompt, function(existing, candidate)
        return existing.name == candidate.name
    end)
end

---@param server_name string
---@param prompt_name string
function M.unregister_prompt(server_name, prompt_name)
    local server = ensure_server(server_name)
    local retained = {}
    for _, prompt in ipairs(server.prompts or {}) do
        if prompt.name ~= prompt_name then
            table.insert(retained, prompt)
        end
    end
    server.prompts = retained
end

---@return table[]
function M.list_tool_descriptors()
    local descriptors = {}

    for _, server in ipairs(M.list_servers()) do
        for _, tool in ipairs(server.tools or {}) do
            local namespaced_name = string.format('%s/%s', server.name, tool.name)
            table.insert(descriptors, {
                server = server.name,
                namespaced_name = namespaced_name,
                name = namespaced_name,
                title = namespaced_name,
                description = tool.description,
                inputSchema = tool.input_schema or {
                    type = 'object',
                    properties = {},
                },
            })
        end
    end

    table.sort(descriptors, function(left, right)
        return left.namespaced_name < right.namespaced_name
    end)

    return descriptors
end

---@return table[]
function M.list_resource_descriptors()
    local descriptors = {}

    for _, server in ipairs(M.list_servers()) do
        for _, resource in ipairs(server.resources or {}) do
            local namespaced_uri = string.format('%s/%s', server.name, resource.uri)
            table.insert(descriptors, {
                server = server.name,
                namespaced_uri = namespaced_uri,
                uri = namespaced_uri,
                name = resource.name,
                description = resource.description,
                mimeType = resource.mime_type,
            })
        end
    end

    table.sort(descriptors, function(left, right)
        return left.namespaced_uri < right.namespaced_uri
    end)

    return descriptors
end

---@return table[]

---@param namespaced_uri string
---@return mcp.ResourceSpec?, string?
function M.find_resource(namespaced_uri)
    assert(
        type(namespaced_uri) == 'string' and namespaced_uri ~= '',
        'namespaced resource uri must be a non-empty string'
    )

    local best_server_name

    for server_name, server in pairs(servers) do
        local prefix = server_name .. '/'

        if vim.startswith(namespaced_uri, prefix) then
            local resource_uri = namespaced_uri:sub(#prefix + 1)

            if resource_uri ~= '' and (best_server_name == nil or #server_name > #best_server_name) then
                for _, resource in ipairs(server.resources or {}) do
                    if resource.uri == resource_uri then
                        best_server_name = server_name
                        break
                    end
                end
            end
        end
    end

    if best_server_name ~= nil then
        local resource_uri = namespaced_uri:sub(#best_server_name + 2)

        for _, resource in ipairs(servers[best_server_name].resources or {}) do
            if resource.uri == resource_uri then
                return deepcopy(resource), nil
            end
        end
    end

    local server_name, resource_uri = namespaced_uri:match('^(.-)/(.-)$')

    if server_name == nil or resource_uri == nil then
        return nil, string.format('Invalid namespaced resource uri: %s', namespaced_uri)
    end

    if servers[server_name] == nil then
        return nil, string.format('Unknown mcp server: %s', server_name)
    end

    return nil, string.format('Unknown resource %s on server %s', resource_uri, server_name)
end

---@return table[]
function M.list_resource_template_descriptors()
    local descriptors = {}

    for _, server in ipairs(M.list_servers()) do
        for _, resource_template in ipairs(server.resource_templates or {}) do
            table.insert(descriptors, {
                server = server.name,
                name = resource_template.name,
                uriTemplate = resource_template.uri_template,
                description = resource_template.description,
                mimeType = resource_template.mime_type,
            })
        end
    end

    table.sort(descriptors, function(left, right)
        if left.server == right.server then
            return left.uriTemplate < right.uriTemplate
        end

        return left.server < right.server
    end)

    return descriptors
end

---@param namespaced_name string
---@return mcp.PromptSpec?, string?
function M.find_prompt(namespaced_name)
    assert(
        type(namespaced_name) == 'string' and namespaced_name ~= '',
        'namespaced prompt name must be a non-empty string'
    )

    local best_server_name

    for server_name, server in pairs(servers) do
        local prefix = server_name .. '/'

        if vim.startswith(namespaced_name, prefix) then
            local prompt_name = namespaced_name:sub(#prefix + 1)

            if prompt_name ~= '' and (best_server_name == nil or #server_name > #best_server_name) then
                for _, prompt in ipairs(server.prompts or {}) do
                    if prompt.name == prompt_name then
                        best_server_name = server_name
                        break
                    end
                end
            end
        end
    end

    if best_server_name ~= nil then
        local prompt_name = namespaced_name:sub(#best_server_name + 2)

        for _, prompt in ipairs(servers[best_server_name].prompts or {}) do
            if prompt.name == prompt_name then
                return deepcopy(prompt), nil
            end
        end
    end

    local server_name, prompt_name = namespaced_name:match('^(.-)/(.-)$')

    if server_name == nil or prompt_name == nil then
        return nil, string.format('Invalid namespaced prompt name: %s', namespaced_name)
    end

    if servers[server_name] == nil then
        return nil, string.format('Unknown mcp server: %s', server_name)
    end

    return nil, string.format('Unknown prompt %s on server %s', prompt_name, server_name)
end

function M.list_prompt_descriptors()
    local descriptors = {}

    for _, server in ipairs(M.list_servers()) do
        for _, prompt in ipairs(server.prompts or {}) do
            local namespaced_name = string.format('%s/%s', server.name, prompt.name)
            table.insert(descriptors, {
                server = server.name,
                namespaced_name = namespaced_name,
                name = namespaced_name,
                description = prompt.description,
                arguments = deepcopy(prompt.arguments or {}),
            })
        end
    end

    table.sort(descriptors, function(left, right)
        return left.namespaced_name < right.namespaced_name
    end)

    return descriptors
end

---@param tool_name string
---@return string
local function flattened_tool_name(tool_name)
    return tool_name:gsub('/', '__')
end

---@return { server_name: string, tool: mcp.ToolSpec }[]
local function list_effective_tools()
    local items = {}

    for _, server in ipairs(M.list_servers()) do
        for _, tool in ipairs(server.tools or {}) do
            table.insert(items, {
                server_name = server.name,
                tool = tool,
            })
        end
    end

    return items
end

---@param namespaced_name string
---@param opts? { allow_flattened_fallback?: boolean }
---@return mcp.ToolSpec?, string?
function M.find_tool(namespaced_name, opts)
    assert(
        type(namespaced_name) == 'string' and namespaced_name ~= '',
        'namespaced tool name must be a non-empty string'
    )

    opts = opts or {}
    local allow_flattened_fallback = opts.allow_flattened_fallback ~= false
    local best_server_name
    local requested_server_name, requested_tool_name = namespaced_name:match('^(.-)/(.-)$')

    local effective_tools = list_effective_tools()

    for _, item in ipairs(effective_tools) do
        local prefix = item.server_name .. '/'

        if vim.startswith(namespaced_name, prefix) then
            local tool_name = namespaced_name:sub(#prefix + 1)

            if
                tool_name ~= ''
                and item.tool.name == tool_name
                and (best_server_name == nil or #item.server_name > #best_server_name)
            then
                best_server_name = item.server_name
            end
        end
    end

    if best_server_name ~= nil then
        local tool_name = namespaced_name:sub(#best_server_name + 2)

        for _, item in ipairs(effective_tools) do
            if item.server_name == best_server_name and item.tool.name == tool_name then
                return deepcopy(item.tool), nil
            end
        end
    end

    if allow_flattened_fallback then
        local matching_tools = {}

        for _, item in ipairs(effective_tools) do
            local matches_flattened_name = flattened_tool_name(item.tool.name) == namespaced_name
            local matches_requested_server = requested_server_name ~= nil
                and requested_tool_name ~= nil
                and item.server_name == requested_server_name
                and flattened_tool_name(item.tool.name) == requested_tool_name

            if matches_flattened_name or matches_requested_server then
                table.insert(matching_tools, item)
            end
        end

        if #matching_tools == 1 then
            return deepcopy(matching_tools[1].tool), nil
        end

        if #matching_tools > 1 then
            table.sort(matching_tools, function(left, right)
                local left_name = string.format('%s/%s', left.server_name, left.tool.name)
                local right_name = string.format('%s/%s', right.server_name, right.tool.name)
                return left_name < right_name
            end)

            local candidates = vim.tbl_map(function(item)
                return string.format('%s/%s', item.server_name, item.tool.name)
            end, matching_tools)

            return nil,
                string.format(
                    'Ambiguous flattened tool name %s; matches: %s',
                    namespaced_name,
                    table.concat(candidates, ', ')
                )
        end
    end

    local server_name, tool_name = namespaced_name:match('^(.-)/(.-)$')

    if server_name == nil or tool_name == nil then
        return nil, string.format('Invalid namespaced tool name: %s', namespaced_name)
    end

    if servers[server_name] == nil then
        return nil, string.format('Unknown mcp server: %s', server_name)
    end

    return nil, string.format('Unknown tool %s on server %s', tool_name, server_name)
end

function M.reset()
    servers = {}
end

function M.normalize_tools(tools)
    return normalize_tools(tools)
end

return M
