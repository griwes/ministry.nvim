local config = require('ministry.core.config')
local runtime = require('ministry.builtin.terminal_runtime')

local M = {}

local function terminal_tools_disabled_error()
    return {
        code = -32601,
        message = 'Terminal tools are disabled; set enable_terminal_tools = true to opt in',
    }
end

---@param value any
---@param name string
---@param required boolean|nil
---@return nil, table|nil
local function validate_string(value, name, required)
    if value == nil then
        if required then
            return nil,
                {
                    code = -32602,
                    message = string.format('Invalid arguments: %s must be a string', name),
                }
        end

        return nil, nil
    end

    if type(value) ~= 'string' then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be a string', name),
            }
    end

    return value, nil
end

---@param value any
---@param name string
---@param required boolean|nil
---@return string[]|nil, table|nil
local function validate_string_list(value, name, required)
    if value == nil then
        if required then
            return nil,
                {
                    code = -32602,
                    message = string.format('Invalid arguments: %s must be an array of strings', name),
                }
        end

        return nil, nil
    end

    if type(value) ~= 'table' or vim.islist(value) == false then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be an array of strings', name),
            }
    end

    local result = {}
    for _, item in ipairs(value) do
        if type(item) ~= 'string' then
            return nil,
                {
                    code = -32602,
                    message = string.format('Invalid arguments: %s must be an array of strings', name),
                }
        end
        table.insert(result, item)
    end

    if #result == 0 then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be a non-empty array of strings', name),
            }
    end

    return result, nil
end

---@param value any
---@param name string
---@param maximum integer
---@return integer|nil, table|nil
local function validate_timeout(value, name, maximum)
    if value == nil then
        return nil, nil
    end

    if type(value) ~= 'number' or value % 1 ~= 0 or value < 0 or value > maximum then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be an integer between 0 and %d', name, maximum),
            }
    end

    return value, nil
end

---@return table
function M.tools_tree()
    return {
        create = {
            description = 'Create a Neovim-owned terminal process surface.',
            input_schema = {
                type = 'object',
                properties = {
                    command = {
                        type = 'array',
                        items = { type = 'string' },
                        minItems = 1,
                    },
                    cwd = { type = 'string' },
                },
                required = { 'command' },
            },
            handler = function(arguments)
                if not config.get().enable_terminal_tools then
                    return nil, terminal_tools_disabled_error()
                end

                local command, command_err = validate_string_list(arguments.command, 'command', true)
                if command_err ~= nil then
                    return nil, command_err
                end

                local cwd, cwd_err = validate_string(arguments.cwd, 'cwd', false)
                if cwd_err ~= nil then
                    return nil, cwd_err
                end

                return runtime.create(command, cwd)
            end,
        },
        output = {
            description = 'Read output from a Neovim-owned terminal process surface.',
            input_schema = {
                type = 'object',
                properties = {
                    terminal_id = { type = 'string' },
                },
                required = { 'terminal_id' },
            },
            handler = function(arguments)
                if not config.get().enable_terminal_tools then
                    return nil, terminal_tools_disabled_error()
                end

                local terminal_id, terminal_id_err = validate_string(arguments.terminal_id, 'terminal_id', true)
                if terminal_id_err ~= nil then
                    return nil, terminal_id_err
                end

                return runtime.output(terminal_id)
            end,
        },
        wait = {
            description = 'Poll for a Neovim-owned terminal process to exit using a bounded wait.',
            input_schema = {
                type = 'object',
                properties = {
                    terminal_id = { type = 'string' },
                    timeout_ms = {
                        type = 'integer',
                        minimum = 0,
                        maximum = config.get().terminal.max_wait_timeout_ms,
                    },
                },
                required = { 'terminal_id' },
            },
            handler = function(arguments)
                if not config.get().enable_terminal_tools then
                    return nil, terminal_tools_disabled_error()
                end

                local terminal_id, terminal_id_err = validate_string(arguments.terminal_id, 'terminal_id', true)
                if terminal_id_err ~= nil then
                    return nil, terminal_id_err
                end

                local timeout_ms, timeout_err =
                    validate_timeout(arguments.timeout_ms, 'timeout_ms', config.get().terminal.max_wait_timeout_ms)
                if timeout_err ~= nil then
                    return nil, timeout_err
                end

                return runtime.wait(terminal_id, timeout_ms)
            end,
        },
        release = {
            description = 'Release a Neovim-owned terminal process surface.',
            input_schema = {
                type = 'object',
                properties = {
                    terminal_id = { type = 'string' },
                },
                required = { 'terminal_id' },
            },
            handler = function(arguments)
                if not config.get().enable_terminal_tools then
                    return nil, terminal_tools_disabled_error()
                end

                local terminal_id, terminal_id_err = validate_string(arguments.terminal_id, 'terminal_id', true)
                if terminal_id_err ~= nil then
                    return nil, terminal_id_err
                end

                return runtime.release(terminal_id)
            end,
        },
    }
end

---@return ministry.ResourceSpec[]
function M.resources_specs()
    return {
        {
            uri = 'terminals://list',
            name = 'Terminal List',
            description = 'Lightweight session-global summary of Ministry-owned terminal runtime entries.',
            mime_type = 'application/json',
            handler = function()
                if not config.get().enable_terminal_tools then
                    return nil, terminal_tools_disabled_error()
                end

                return {
                    terminals = runtime.list(),
                }
            end,
        },
    }
end

return M
