local config = require('mcp.config')
local builtin_editor = require('mcp.builtin.editor.init')
local builtin_terminal = require('mcp.builtin.terminal')
local builtin_terminal_runtime = require('mcp.builtin.terminal_runtime')
local dispatch = require('mcp.dispatch')
local endpoint = require('mcp.endpoint')
local registry = require('mcp.registry')
local router = require('mcp.router')
local server = require('mcp.server')
local http_server = require('mcp.http_server')

---@class mcp.Module
local M = {}

local builtin_neovim_overrides = nil
local builtin_neovim_mode = 'builtin'

local function socket_transport_supported()
    local pipe = vim.uv.new_pipe(false)
    local supports_socket = pipe ~= nil and pipe.bind2 ~= nil

    if pipe ~= nil and pipe.close ~= nil then
        local closing = pipe.is_closing ~= nil and pipe:is_closing() or false
        if not closing then
            pipe:close()
        end
    end

    return supports_socket
end

local function builtin_neovim_server_spec()
    local editor_server = builtin_editor.server_spec()
    local applied = config.get()
    local tools = {
        editor = builtin_editor.tools_tree(),
    }

    if applied.enable_terminal_tools then
        tools.terminal = builtin_terminal.tools_tree()
    end

    return {
        name = 'neovim',
        title = 'Neovim',
        description = 'Built-in Neovim-local MCP capability surfaces.',
        tools = tools,
        resources = editor_server.resources,
        resource_templates = editor_server.resource_templates,
        prompts = editor_server.prompts,
    }
end

local function merge_tool_specs(existing_tools, builtin_tools)
    local merged = {}
    local positions = {}

    for _, tool in ipairs(registry.normalize_tools(builtin_tools)) do
        table.insert(merged, tool)
        positions[tool.name] = #merged
    end

    for _, tool in ipairs(registry.normalize_tools(existing_tools)) do
        local position = positions[tool.name]
        if position ~= nil then
            merged[position] = tool
        else
            table.insert(merged, tool)
            positions[tool.name] = #merged
        end
    end

    return merged
end

local function merge_named_specs(existing_items, builtin_items, key)
    local merged = {}
    local positions = {}

    for _, item in ipairs(builtin_items or {}) do
        table.insert(merged, vim.tbl_extend('force', {}, item))
        positions[item[key]] = #merged
    end

    for _, item in ipairs(existing_items or {}) do
        local position = positions[item[key]]
        if position ~= nil then
            merged[position] = vim.tbl_extend('force', {}, merged[position], item)
        else
            table.insert(merged, item)
            positions[item[key]] = #merged
        end
    end

    return merged
end

local function snapshot_neovim_overrides(existing)
    if existing == nil then
        return nil
    end

    return {
        title = existing.title,
        description = existing.description,
        tools = existing.tools,
        resources = existing.resources,
        resource_templates = existing.resource_templates,
        prompts = existing.prompts,
    }
end

local function tool_specs_equal(left, right)
    if left == right then
        return true
    end

    if left == nil or right == nil then
        return false
    end

    local left_schema = left.input_schema or left.inputSchema
    local right_schema = right.input_schema or right.inputSchema

    return left.handler == right.handler
        and left.description == right.description
        and vim.deep_equal(left_schema, right_schema)
end

local function strip_builtin_tool_overrides(existing_tools, builtin_tools)
    if existing_tools == nil then
        return nil
    end

    local builtin_by_name = {}
    for _, tool in ipairs(registry.normalize_tools(builtin_tools)) do
        builtin_by_name[tool.name] = tool
    end

    local overrides = {}
    for _, tool in ipairs(registry.normalize_tools(existing_tools)) do
        local builtin_tool = builtin_by_name[tool.name]
        if not tool_specs_equal(tool, builtin_tool) then
            table.insert(overrides, tool)
        end
    end

    return overrides
end

local function strip_builtin_named_overrides(existing_items, builtin_items, key)
    if existing_items == nil then
        return nil
    end

    local builtin_by_key = {}
    for _, item in ipairs(builtin_items or {}) do
        builtin_by_key[item[key]] = item
    end

    local overrides = {}
    for _, item in ipairs(existing_items or {}) do
        if builtin_by_key[item[key]] == nil then
            table.insert(overrides, item)
        end
    end

    return overrides
end

local function snapshot_user_neovim_overrides(existing)
    if existing == nil then
        return nil
    end

    local builtin = builtin_neovim_server_spec()

    return {
        title = existing.title ~= builtin.title and existing.title or nil,
        description = existing.description ~= builtin.description and existing.description or nil,
        tools = strip_builtin_tool_overrides(existing.tools, builtin.tools),
        resources = strip_builtin_named_overrides(existing.resources, builtin.resources, 'uri'),
        resource_templates = strip_builtin_named_overrides(existing.resource_templates, builtin.resource_templates, 'uri_template'),
        prompts = strip_builtin_named_overrides(existing.prompts, builtin.prompts, 'name'),
    }
end

local function sync_builtin_neovim_state(existing)
    if existing == nil then
        builtin_neovim_overrides = nil
        builtin_neovim_mode = 'builtin'
        return
    end

    builtin_neovim_overrides = snapshot_user_neovim_overrides(existing)
    builtin_neovim_mode = builtin_neovim_overrides == nil and 'custom' or 'overrides'
end

local function register_builtin_neovim_server(existing)
    if builtin_neovim_mode == 'custom' then
        return
    end

    local builtin = builtin_neovim_server_spec()
    local overrides = existing or builtin_neovim_overrides

    if overrides == nil then
        registry.register_server(builtin)
        builtin_neovim_overrides = nil
        builtin_neovim_mode = 'builtin'
        return
    end

    builtin_neovim_overrides = snapshot_neovim_overrides(overrides)
    builtin_neovim_mode = 'overrides'

    registry.register_server({
        name = 'neovim',
        title = overrides.title or builtin.title,
        description = overrides.description or builtin.description,
        tools = merge_tool_specs(overrides.tools, builtin.tools),
        resources = merge_named_specs(overrides.resources, builtin.resources, 'uri'),
        resource_templates = merge_named_specs(overrides.resource_templates, builtin.resource_templates, 'uri_template'),
        prompts = merge_named_specs(overrides.prompts, builtin.prompts, 'name'),
    })
end

---@param opts? Partial<mcp.Config>
---@return mcp.Config
function M.setup(opts)
    local applied = config.set(opts)

    register_builtin_neovim_server(builtin_neovim_overrides)

    if applied.auto_start then
        local transport = applied.transport or 'socket'
        if transport == 'http' then
            server.start(transport)
        elseif transport == 'socket' and socket_transport_supported() then
            server.start(transport)
        end
    end

    return applied
end

---@param server mcp.ServerSpec
---@return mcp.ServerSpec
function M.register_server(server)
    local registered = registry.register_server(server)

    if server.name == 'neovim' then
        sync_builtin_neovim_state(registered)
    end

    return registered
end

---@param server_name string
function M.unregister_server(server_name)
    registry.unregister_server(server_name)

    if server_name == 'neovim' then
        builtin_neovim_overrides = nil
        builtin_neovim_mode = 'builtin'
    end
end

---@param server_name string
---@param tool mcp.ToolSpec
function M.register_tool(server_name, tool)
    registry.register_tool(server_name, tool)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param tool_name string
function M.unregister_tool(server_name, tool_name)
    registry.unregister_tool(server_name, tool_name)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param resource mcp.ResourceSpec
function M.register_resource(server_name, resource)
    registry.register_resource(server_name, resource)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param uri string
function M.unregister_resource(server_name, uri)
    registry.unregister_resource(server_name, uri)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param resource_template mcp.ResourceTemplateSpec
function M.register_resource_template(server_name, resource_template)
    registry.register_resource_template(server_name, resource_template)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param template_name string
function M.unregister_resource_template(server_name, template_name)
    registry.unregister_resource_template(server_name, template_name)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param prompt mcp.PromptSpec
function M.register_prompt(server_name, prompt)
    registry.register_prompt(server_name, prompt)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param prompt_name string
function M.unregister_prompt(server_name, prompt_name)
    registry.unregister_prompt(server_name, prompt_name)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@return mcp.ServerSpec[]
function M.list_servers()
    return registry.list_servers()
end

---@return table[]
function M.list_tool_descriptors()
    return registry.list_tool_descriptors()
end

---@return table[]
function M.list_resource_descriptors()
    return registry.list_resource_descriptors()
end

---@return table[]
function M.list_prompt_descriptors()
    return registry.list_prompt_descriptors()
end

---@param namespaced_name string
---@param arguments table|nil
---@param context table|nil
---@return table|nil, table|nil
function M.call_tool(namespaced_name, arguments, context)
    return dispatch.call_tool(namespaced_name, arguments, context)
end

---@param method string|nil
---@param params table|nil
---@param id integer|string|nil
---@param context table|nil
---@return table|nil
function M.handle_request(method, params, id, context)
    return router.handle_request(method, params, id, context)
end

---@param transport? 'socket'|'http'
---@return boolean, string?
function M.start(transport)
    return server.start(transport or config.get().transport or 'socket')
end

---@return boolean, string?
function M.start_all()
    return server.start_all()
end

function M.stop()
    server.stop()
end

---@return boolean
function M.running()
    return server.running()
end

---@return mcp.EndpointDescriptor
function M.endpoint()
    return endpoint.describe()
end

---@return table
function M.endpoint_invocation()
    return endpoint.describe().invocation
end

---@return mcp.EndpointDescriptor?
function M.http_endpoint()
    local host, port = http_server.bound_address()

    if host == nil or port == nil then
        return nil
    end

    return endpoint.describe_http(host, port)
end

function M.reset()
    builtin_neovim_overrides = nil
    builtin_neovim_mode = 'builtin'

    server.stop()
    http_server.stop()
    builtin_terminal_runtime.reset()
    endpoint.reset()
    config.reset()
    registry.reset()
end

return M
