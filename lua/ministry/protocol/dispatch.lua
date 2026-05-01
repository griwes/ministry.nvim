local registry = require('ministry.core.registry')
local approval = require('ministry.approval.policy')

local M = {}

---@param namespaced_name string
---@param arguments table|nil
---@param context table|nil
---@return table|nil, table|nil
function M.call_tool(namespaced_name, arguments, context)
    local tool, find_error = registry.find_tool(namespaced_name)

    if tool == nil then
        return nil, {
            code = -32601,
            message = find_error,
        }
    end

    local call_arguments = arguments or {}
    local call_context = context or {}
    local approved, approval_error = approval.check_tool(namespaced_name, call_arguments, call_context)
    if not approved then
        return nil, approval_error
    end

    local packed = { pcall(tool.handler, call_arguments, call_context) }
    local ok = packed[1]
    local result = packed[2]
    local handler_error = packed[3]
    local warning = packed[4]

    if not ok then
        return nil, {
            code = -32000,
            message = tostring(result),
        }
    end

    if handler_error ~= nil then
        return nil, handler_error, warning
    end

    return result or {}, nil, warning
end

return M
