local registry = require('ministry.core.registry')

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

    local packed = { pcall(tool.handler, arguments or {}, context or {}) }
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
