local config = require('mcp.config')
local dispatch = require('mcp.dispatch')
local endpoint = require('mcp.endpoint')
local registry = require('mcp.registry')

---@class mcp.Module
local M = {}

---@param opts? Partial<mcp.Config>
---@return mcp.Config
function M.setup(opts)
    return config.set(opts)
end

---@param server mcp.ServerSpec
---@return mcp.ServerSpec
function M.register_server(server)
    return registry.register_server(server)
end

---@param server_name string
function M.unregister_server(server_name)
    registry.unregister_server(server_name)
end

---@param server_name string
---@param tool mcp.ToolSpec
function M.register_tool(server_name, tool)
    registry.register_tool(server_name, tool)
end

---@param server_name string
---@param tool_name string
function M.unregister_tool(server_name, tool_name)
    registry.unregister_tool(server_name, tool_name)
end

---@param server_name string
---@param resource mcp.ResourceSpec
function M.register_resource(server_name, resource)
    registry.register_resource(server_name, resource)
end

---@param server_name string
---@param uri string
function M.unregister_resource(server_name, uri)
    registry.unregister_resource(server_name, uri)
end

---@param server_name string
---@param resource_template mcp.ResourceTemplateSpec
function M.register_resource_template(server_name, resource_template)
    registry.register_resource_template(server_name, resource_template)
end

---@param server_name string
---@param template_name string
function M.unregister_resource_template(server_name, template_name)
    registry.unregister_resource_template(server_name, template_name)
end

---@param server_name string
---@param prompt mcp.PromptSpec
function M.register_prompt(server_name, prompt)
    registry.register_prompt(server_name, prompt)
end

---@param server_name string
---@param prompt_name string
function M.unregister_prompt(server_name, prompt_name)
    registry.unregister_prompt(server_name, prompt_name)
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

---@return mcp.EndpointDescriptor
function M.endpoint()
    return endpoint.describe()
end

function M.reset()
    config.reset()
    registry.reset()
end

return M
