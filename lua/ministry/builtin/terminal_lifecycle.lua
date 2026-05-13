local M = {}

---@class ministry.TerminalLifecycleListener
---@field created? fun(terminal: table)
---@field released? fun(terminal: table)
---@field reset? fun()

---@type table<string, ministry.TerminalLifecycleListener>
local listeners = {}

---@param owner any
---@return table|nil
local function validate_owner(owner)
    if type(owner) ~= 'string' or owner == '' then
        return {
            code = -32602,
            message = 'Invalid arguments: owner must be a non-empty string',
        }
    end

    return nil
end

---@param listener any
---@return table|nil
local function validate_listener(listener)
    if type(listener) ~= 'table' then
        return {
            code = -32602,
            message = 'Invalid arguments: listener must be a table',
        }
    end

    local has_callback = false
    for _, event in ipairs({ 'created', 'released', 'reset' }) do
        if listener[event] ~= nil and type(listener[event]) ~= 'function' then
            return {
                code = -32602,
                message = string.format('Invalid arguments: listener.%s must be a function', event),
            }
        end

        has_callback = has_callback or listener[event] ~= nil
    end

    if not has_callback then
        return {
            code = -32602,
            message = 'Invalid arguments: listener must define at least one lifecycle callback',
        }
    end

    return nil
end

---@param owner string
---@param listener ministry.TerminalLifecycleListener
---@return table|nil, table|nil
function M.register(owner, listener)
    local validation_err = validate_owner(owner) or validate_listener(listener)
    if validation_err ~= nil then
        return nil, validation_err
    end

    listeners[owner] = listener
    return {
        owner = owner,
        registered = true,
    }, nil
end

---@param owner string
---@return table|nil, table|nil
function M.unregister(owner)
    local validation_err = validate_owner(owner)
    if validation_err ~= nil then
        return nil, validation_err
    end

    listeners[owner] = nil
    return {
        owner = owner,
        registered = false,
    }, nil
end

---@param event 'created'|'released'|'reset'
---@param terminal? table
local function emit(event, terminal)
    local owners = vim.tbl_keys(listeners)
    table.sort(owners)

    for _, owner in ipairs(owners) do
        local callback = listeners[owner][event]
        if callback ~= nil then
            pcall(callback, terminal ~= nil and vim.deepcopy(terminal) or nil)
        end
    end
end

---@param terminal table
function M.created(terminal)
    emit('created', terminal)
end

---@param terminal table
function M.released(terminal)
    emit('released', terminal)
end

function M.reset()
    emit('reset')
    listeners = {}
end

return M
