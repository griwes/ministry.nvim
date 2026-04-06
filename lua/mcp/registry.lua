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

---@param server mcp.ServerSpec
---@return mcp.ServerSpec
function M.register_server(server)
    validate_server(server)

    local normalized = {
        name = server.name,
        title = server.title,
        description = server.description,
        tools = normalized_items(server.tools),
        resources = normalized_items(server.resources),
        resource_templates = normalized_items(server.resource_templates),
        prompts = normalized_items(server.prompts),
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

---@param server_name string
---@param tool mcp.ToolSpec
function M.register_tool(server_name, tool)
    local server = ensure_server(server_name)
    assert(type(tool) == 'table', 'mcp tool spec must be a table')
    assert(type(tool.name) == 'string' and tool.name ~= '', 'mcp tool name must be a non-empty string')
    assert(type(tool.handler) == 'function', 'mcp tool handler must be a function')
    table.insert(server.tools, deepcopy(tool))
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
    assert(type(resource) == 'table', 'mcp resource spec must be a table')
    assert(type(resource.uri) == 'string' and resource.uri ~= '', 'mcp resource uri must be a non-empty string')
    assert(type(resource.handler) == 'function', 'mcp resource handler must be a function')
    table.insert(server.resources, deepcopy(resource))
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
    assert(type(resource_template) == 'table', 'mcp resource template spec must be a table')
    assert(type(resource_template.name) == 'string' and resource_template.name ~= '', 'mcp resource template name must be a non-empty string')
    assert(type(resource_template.uri_template) == 'string' and resource_template.uri_template ~= '', 'mcp resource template uri_template must be a non-empty string')
    assert(type(resource_template.handler) == 'function', 'mcp resource template handler must be a function')
    table.insert(server.resource_templates, deepcopy(resource_template))
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
    assert(type(prompt) == 'table', 'mcp prompt spec must be a table')
    assert(type(prompt.name) == 'string' and prompt.name ~= '', 'mcp prompt name must be a non-empty string')
    assert(type(prompt.handler) == 'function', 'mcp prompt handler must be a function')
    table.insert(server.prompts, deepcopy(prompt))
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
            table.insert(descriptors, {
                server = server.name,
                namespaced_name = string.format('%s/%s', server.name, tool.name),
                name = tool.name,
                title = tool.name,
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
            table.insert(descriptors, {
                server = server.name,
                namespaced_uri = string.format('%s/%s', server.name, resource.uri),
                uri = resource.uri,
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
function M.list_prompt_descriptors()
    local descriptors = {}

    for _, server in ipairs(M.list_servers()) do
        for _, prompt in ipairs(server.prompts or {}) do
            table.insert(descriptors, {
                server = server.name,
                namespaced_name = string.format('%s/%s', server.name, prompt.name),
                name = prompt.name,
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

---@param namespaced_name string
---@return mcp.ToolSpec?, string?
function M.find_tool(namespaced_name)
    assert(type(namespaced_name) == 'string' and namespaced_name ~= '', 'namespaced tool name must be a non-empty string')

    local server_name, tool_name = namespaced_name:match('^(.-)/(.-)$')

    if server_name == nil or tool_name == nil then
        return nil, string.format('Invalid namespaced tool name: %s', namespaced_name)
    end

    local server = servers[server_name]

    if server == nil then
        return nil, string.format('Unknown mcp server: %s', server_name)
    end

    for _, tool in ipairs(server.tools or {}) do
        if tool.name == tool_name then
            return deepcopy(tool), nil
        end
    end

    return nil, string.format('Unknown tool %s on server %s', tool_name, server_name)
end

function M.reset()
    servers = {}
end

return M
