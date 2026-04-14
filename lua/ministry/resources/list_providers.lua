local M = {}

---@type table<string, table<string, fun(item: table, item_id: string): table<string, any>|nil>>
local providers = {}

---@param list_name any
---@param owner any
---@return table|nil
local function validate_registration(list_name, owner)
    if type(list_name) ~= 'string' or list_name == '' then
        return {
            code = -32602,
            message = 'Invalid arguments: list_name must be a non-empty string',
        }
    end

    if type(owner) ~= 'string' or owner == '' then
        return {
            code = -32602,
            message = 'Invalid arguments: owner must be a non-empty string',
        }
    end

    return nil
end

---@param list_name string
---@param owner string
---@param callback any
---@return table|nil, table|nil
function M.register(list_name, owner, callback)
    local validation_err = validate_registration(list_name, owner)
    if validation_err ~= nil then
        return nil, validation_err
    end

    if type(callback) ~= 'function' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: callback must be a function',
            }
    end

    providers[list_name] = providers[list_name] or {}
    providers[list_name][owner] = callback

    return {
        list_name = list_name,
        owner = owner,
        registered = true,
    }, nil
end

---@param list_name string
---@param owner string
---@return table|nil, table|nil
function M.unregister(list_name, owner)
    local validation_err = validate_registration(list_name, owner)
    if validation_err ~= nil then
        return nil, validation_err
    end

    local list_providers = providers[list_name]
    if list_providers ~= nil then
        list_providers[owner] = nil

        if next(list_providers) == nil then
            providers[list_name] = nil
        end
    end

    return {
        list_name = list_name,
        owner = owner,
        registered = false,
    }, nil
end

---@param list_name string
---@param item_id string|integer
---@param item table
---@return table
function M.apply(list_name, item_id, item)
    local list_providers = providers[list_name]

    if list_providers == nil then
        return vim.deepcopy(item)
    end

    local merged = vim.deepcopy(item)
    local owners = vim.tbl_keys(list_providers)
    table.sort(owners)
    local normalized_item_id = tostring(item_id)

    for _, owner in ipairs(owners) do
        local callback = list_providers[owner]
        local ok, data = pcall(callback, vim.deepcopy(item), normalized_item_id)

        if ok and type(data) == 'table' then
            merged = vim.tbl_deep_extend('force', merged, vim.deepcopy(data))
        end
    end

    return merged
end

function M.reset()
    providers = {}
end

return M
