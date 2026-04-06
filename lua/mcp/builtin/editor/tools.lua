local context = require('mcp.builtin.editor.context')
local diff = require('mcp.builtin.editor.diff')
local io = require('mcp.builtin.editor.io')

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

local function require_string(arguments, name)
    if type(arguments) ~= 'table' or type(arguments[name]) ~= 'string' then
        return nil,
            {
                code = -32602,
                message = string.format('Invalid arguments: %s must be a string', name),
            }
    end

    return arguments[name], nil
end

---@return mcp.ToolSpec[]
function M.specs()
    return {
        {
            name = 'list_buffers',
            description = 'List editor buffers with stable Neovim buffer ids.',
            input_schema = {
                type = 'object',
                properties = {},
            },
            handler = function()
                return {
                    buffers = context.list_buffers(),
                }
            end,
        },
        {
            name = 'read_buffer',
            description = 'Read a buffer by stable Neovim buffer id.',
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
                local bufnr, err = require_integer(arguments, 'bufnr')

                if err ~= nil then
                    return nil, err
                end

                local ctx, ctx_err = context.by_id(bufnr)

                if ctx_err ~= nil then
                    return nil, ctx_err
                end

                return {
                    bufnr = ctx.bufnr,
                    path = ctx.name,
                    filetype = ctx.filetype,
                    modified = ctx.modified,
                    content = table.concat(ctx.lines, '\n'),
                }
            end,
        },
        {
            name = 'diff_buffer',
            description = 'Compute a diff between a buffer selected by buffer id and provided content.',
            input_schema = {
                type = 'object',
                properties = {
                    bufnr = {
                        type = 'integer',
                    },
                    content = {
                        type = 'string',
                    },
                },
                required = { 'bufnr', 'content' },
            },
            handler = function(arguments)
                local bufnr, bufnr_err = require_integer(arguments, 'bufnr')

                if bufnr_err ~= nil then
                    return nil, bufnr_err
                end

                local content, err = require_string(arguments, 'content')

                if err ~= nil then
                    return nil, err
                end

                return diff.buffer(bufnr, content)
            end,
        },
        {
            name = 'write_buffer',
            description = 'Write a buffer selected by buffer id through Neovim-owned buffer semantics.',
            input_schema = {
                type = 'object',
                properties = {
                    bufnr = {
                        type = 'integer',
                    },
                    content = {
                        type = 'string',
                    },
                },
                required = { 'bufnr', 'content' },
            },
            handler = function(arguments)
                local bufnr, bufnr_err = require_integer(arguments, 'bufnr')

                if bufnr_err ~= nil then
                    return nil, bufnr_err
                end

                local content, err = require_string(arguments, 'content')

                if err ~= nil then
                    return nil, err
                end

                return io.write_buffer(bufnr, content)
            end,
        },
        {
            name = 'apply_diff_buffer',
            description = 'Apply content changes to a buffer selected by buffer id through a diff-based Neovim-owned edit path.',
            input_schema = {
                type = 'object',
                properties = {
                    bufnr = {
                        type = 'integer',
                    },
                    content = {
                        type = 'string',
                    },
                },
                required = { 'bufnr', 'content' },
            },
            handler = function(arguments)
                local bufnr, bufnr_err = require_integer(arguments, 'bufnr')

                if bufnr_err ~= nil then
                    return nil, bufnr_err
                end

                local content, err = require_string(arguments, 'content')

                if err ~= nil then
                    return nil, err
                end

                return diff.apply_buffer(bufnr, content)
            end,
        },
        {
            name = 'diff_current_buffer',
            description = 'Compute a diff between the current buffer and provided content.',
            input_schema = {
                type = 'object',
                properties = {
                    content = {
                        type = 'string',
                    },
                },
                required = { 'content' },
            },
            handler = function(arguments)
                local content, err = require_string(arguments, 'content')

                if err ~= nil then
                    return nil, err
                end

                return diff.current_buffer(content)
            end,
        },
        {
            name = 'write_current_buffer',
            description = 'Write the current buffer through Neovim-owned buffer semantics.',
            input_schema = {
                type = 'object',
                properties = {
                    content = {
                        type = 'string',
                    },
                },
                required = { 'content' },
            },
            handler = function(arguments)
                local content, err = require_string(arguments, 'content')

                if err ~= nil then
                    return nil, err
                end

                return io.write_current_buffer(content)
            end,
        },
        {
            name = 'apply_diff_current_buffer',
            description = 'Apply content changes to the current buffer through a diff-based Neovim-owned edit path.',
            input_schema = {
                type = 'object',
                properties = {
                    content = {
                        type = 'string',
                    },
                },
                required = { 'content' },
            },
            handler = function(arguments)
                local content, err = require_string(arguments, 'content')

                if err ~= nil then
                    return nil, err
                end

                return diff.apply_current_buffer(content)
            end,
        },
        {
            name = 'diff_file',
            description = 'Compute a diff between a file on disk and provided content.',
            input_schema = {
                type = 'object',
                properties = {
                    path = {
                        type = 'string',
                    },
                    content = {
                        type = 'string',
                    },
                },
                required = { 'path', 'content' },
            },
            handler = function(arguments)
                local path, path_err = require_string(arguments, 'path')

                if path_err ~= nil then
                    return nil, path_err
                end

                local content, content_err = require_string(arguments, 'content')

                if content_err ~= nil then
                    return nil, content_err
                end

                return diff.file(path, content)
            end,
        },
        {
            name = 'write_file',
            description = 'Write a file on disk and reload any matching loaded buffer.',
            input_schema = {
                type = 'object',
                properties = {
                    path = {
                        type = 'string',
                    },
                    content = {
                        type = 'string',
                    },
                },
                required = { 'path', 'content' },
            },
            handler = function(arguments)
                local path, path_err = require_string(arguments, 'path')

                if path_err ~= nil then
                    return nil, path_err
                end

                local content, content_err = require_string(arguments, 'content')

                if content_err ~= nil then
                    return nil, content_err
                end

                return io.write_file(path, content)
            end,
        },
        {
            name = 'apply_diff_file',
            description = 'Apply content changes to a file on disk and reload any matching loaded buffer.',
            input_schema = {
                type = 'object',
                properties = {
                    path = {
                        type = 'string',
                    },
                    content = {
                        type = 'string',
                    },
                },
                required = { 'path', 'content' },
            },
            handler = function(arguments)
                local path, path_err = require_string(arguments, 'path')

                if path_err ~= nil then
                    return nil, path_err
                end

                local content, content_err = require_string(arguments, 'content')

                if content_err ~= nil then
                    return nil, content_err
                end

                return diff.apply_file(path, content)
            end,
        },
    }
end

return M
