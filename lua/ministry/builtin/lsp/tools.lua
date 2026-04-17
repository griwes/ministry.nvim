local context = require('ministry.builtin.lsp.context')

local M = {}

local function require_integer(arguments, name)
    local value = type(arguments) == 'table' and arguments[name] or nil

    if type(value) ~= 'number' or value % 1 ~= 0 then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be an integer', name),
            }
    end

    return value, nil
end

local function require_nonnegative_integer(arguments, name)
    local value, err = require_integer(arguments, name)

    if err ~= nil then
        return nil, err
    end

    if value < 0 then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be a non-negative integer', name),
            }
    end

    return value, nil
end

local function require_string(arguments, name)
    local value = type(arguments) == 'table' and arguments[name] or nil

    if type(value) ~= 'string' then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be a string', name),
            }
    end

    return value, nil
end

local function optional_integer(arguments, name)
    local value = type(arguments) == 'table' and arguments[name] or nil

    if value == nil then
        return nil, nil
    end

    return require_integer(arguments, name)
end

local function optional_nonnegative_integer(arguments, name)
    local value = type(arguments) == 'table' and arguments[name] or nil

    if value == nil then
        return nil, nil
    end

    return require_nonnegative_integer(arguments, name)
end

local function optional_boolean(arguments, name)
    local value = type(arguments) == 'table' and arguments[name] or nil

    if value == nil then
        return nil, nil
    end

    if type(value) ~= 'boolean' then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be a boolean', name),
            }
    end

    return value, nil
end

local function ensure_buffer(arguments)
    local bufnr, bufnr_err = require_integer(arguments, 'bufnr')

    if bufnr_err ~= nil then
        return nil, bufnr_err
    end

    return context.ensure_buffer(bufnr)
end

local function location_tool(method_name, loader)
    return {
        name = method_name,
        description = string.format(
            'Query %s locations for a buffer position through active Neovim LSP clients.',
            method_name:gsub('_', ' ')
        ),
        input_schema = {
            type = 'object',
            properties = {
                bufnr = {
                    type = 'integer',
                },
                line = {
                    type = 'integer',
                },
                character = {
                    type = 'integer',
                },
                include_declaration = {
                    type = 'boolean',
                },
            },
            required = { 'bufnr', 'line', 'character' },
        },
        handler = function(arguments)
            local buffer, buffer_err = ensure_buffer(arguments)
            if buffer_err ~= nil then
                return nil, buffer_err
            end

            local line, line_err = require_nonnegative_integer(arguments, 'line')
            if line_err ~= nil then
                return nil, line_err
            end

            local character, char_err = require_nonnegative_integer(arguments, 'character')
            if char_err ~= nil then
                return nil, char_err
            end

            local include_declaration, include_err = optional_boolean(arguments, 'include_declaration')
            if include_err ~= nil then
                return nil, include_err
            end

            local locations, errors = loader(buffer.bufnr, line, character, include_declaration)

            return {
                bufnr = buffer.bufnr,
                path = buffer.path,
                locations = locations,
                errors = errors,
            }
        end,
    }
end

local function range_integers(arguments)
    local line, line_err = require_nonnegative_integer(arguments, 'line')
    if line_err ~= nil then
        return nil, nil, nil, nil, line_err
    end

    local character, char_err = require_nonnegative_integer(arguments, 'character')
    if char_err ~= nil then
        return nil, nil, nil, nil, char_err
    end

    local end_line, end_line_err = optional_nonnegative_integer(arguments, 'end_line')
    if end_line_err ~= nil then
        return nil, nil, nil, nil, end_line_err
    end

    local end_character, end_char_err = optional_nonnegative_integer(arguments, 'end_character')
    if end_char_err ~= nil then
        return nil, nil, nil, nil, end_char_err
    end

    return line, character, end_line, end_character, nil
end

---@return ministry.ToolSpec[]
function M.specs()
    return {
        {
            name = 'list_diagnostics',
            description = 'List diagnostics for the workspace or a specific buffer through Neovim diagnostics state.',
            input_schema = {
                type = 'object',
                properties = {
                    bufnr = {
                        type = 'integer',
                    },
                },
            },
            handler = function(arguments)
                local bufnr, bufnr_err = optional_integer(arguments, 'bufnr')

                if bufnr_err ~= nil then
                    return nil, bufnr_err
                end

                if bufnr ~= nil then
                    local buffer, buffer_err = context.ensure_buffer(bufnr)
                    if buffer_err ~= nil then
                        return nil, buffer_err
                    end

                    return {
                        bufnr = buffer.bufnr,
                        path = buffer.path,
                        diagnostics = context.diagnostics(buffer.bufnr),
                    }
                end

                return {
                    diagnostics = context.diagnostics(nil),
                }
            end,
        },
        {
            name = 'document_symbols',
            description = 'List document symbols for a buffer through active Neovim LSP clients.',
            input_schema = {
                type = 'object',
                properties = {
                    bufnr = {
                        type = 'integer',
                    },
                },
                required = { 'bufnr' },
            },
            handler = function(arguments)
                local buffer, buffer_err = ensure_buffer(arguments)
                if buffer_err ~= nil then
                    return nil, buffer_err
                end

                local clients, errors = context.document_symbols(buffer.bufnr)

                return {
                    bufnr = buffer.bufnr,
                    path = buffer.path,
                    clients = clients,
                    errors = errors,
                }
            end,
        },
        {
            name = 'code_actions',
            description = 'List code actions for a buffer range through active Neovim LSP clients.',
            input_schema = {
                type = 'object',
                properties = {
                    bufnr = {
                        type = 'integer',
                    },
                    line = {
                        type = 'integer',
                    },
                    character = {
                        type = 'integer',
                    },
                    end_line = {
                        type = 'integer',
                    },
                    end_character = {
                        type = 'integer',
                    },
                },
                required = { 'bufnr', 'line', 'character' },
            },
            handler = function(arguments)
                local buffer, buffer_err = ensure_buffer(arguments)
                if buffer_err ~= nil then
                    return nil, buffer_err
                end

                local line, character, end_line, end_character, range_err = range_integers(arguments)
                if range_err ~= nil then
                    return nil, range_err
                end

                local actions, errors = context.code_actions(buffer.bufnr, line, character, end_line, end_character)

                return {
                    bufnr = buffer.bufnr,
                    path = buffer.path,
                    actions = actions,
                    errors = errors,
                }
            end,
        },
        {
            name = 'rename',
            description = 'Request a symbol rename through active Neovim LSP clients and return the resulting workspace edits.',
            input_schema = {
                type = 'object',
                properties = {
                    bufnr = {
                        type = 'integer',
                    },
                    line = {
                        type = 'integer',
                    },
                    character = {
                        type = 'integer',
                    },
                    new_name = {
                        type = 'string',
                    },
                },
                required = { 'bufnr', 'line', 'character', 'new_name' },
            },
            handler = function(arguments)
                local buffer, buffer_err = ensure_buffer(arguments)
                if buffer_err ~= nil then
                    return nil, buffer_err
                end

                local line, line_err = require_nonnegative_integer(arguments, 'line')
                if line_err ~= nil then
                    return nil, line_err
                end

                local character, char_err = require_nonnegative_integer(arguments, 'character')
                if char_err ~= nil then
                    return nil, char_err
                end

                local new_name, name_err = require_string(arguments, 'new_name')
                if name_err ~= nil then
                    return nil, name_err
                end

                local edits, errors = context.rename(buffer.bufnr, line, character, new_name)

                return {
                    bufnr = buffer.bufnr,
                    path = buffer.path,
                    new_name = new_name,
                    edits = edits,
                    errors = errors,
                }
            end,
        },
        {
            name = 'workspace_symbols',
            description = 'Query workspace symbols through active Neovim LSP clients.',
            input_schema = {
                type = 'object',
                properties = {
                    query = {
                        type = 'string',
                    },
                },
                required = { 'query' },
            },
            handler = function(arguments)
                local query, query_err = require_string(arguments, 'query')
                if query_err ~= nil then
                    return nil, query_err
                end

                local clients, errors = context.workspace_symbols(query)

                return {
                    query = query,
                    clients = clients,
                    errors = errors,
                }
            end,
        },
        location_tool('definitions', context.definitions),
        location_tool('declarations', context.declarations),
        location_tool('type_definitions', context.type_definitions),
        location_tool('implementations', context.implementations),
        location_tool('references', context.references),
    }
end

return M
