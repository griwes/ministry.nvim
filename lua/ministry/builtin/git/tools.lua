local context = require('ministry.builtin.git.context')

local M = {}

---@param arguments table|nil
---@param name string
---@return string?, table?
local function optional_string(arguments, name)
    local value = nil
    if type(arguments) == 'table' then
        value = rawget(arguments, name)
    end
    if value == nil then
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

---@param arguments table|nil
---@param name string
---@return boolean?, table?
local function optional_boolean(arguments, name)
    local value = nil
    if type(arguments) == 'table' then
        value = rawget(arguments, name)
    end
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

---@return ministry.ToolSpec[]
function M.specs()
    return {
        {
            name = 'overview',
            description = 'Read compact Stratum-backed Git repository, ref, changed-path, and path state.',
            input_schema = {
                type = 'object',
                properties = {
                    path = {
                        type = 'string',
                    },
                },
            },
            handler = function(arguments)
                local path, path_err = optional_string(arguments, 'path')
                if path_err ~= nil then
                    return nil, path_err
                end

                return context.repository_overview(path)
            end,
        },
        {
            name = 'list_refs',
            description = 'Read Stratum-backed Git branch, upstream, operation, and remote state for a repository.',
            input_schema = {
                type = 'object',
                properties = {
                    path = {
                        type = 'string',
                    },
                    include_tags = {
                        type = 'boolean',
                    },
                    include_stashes = {
                        type = 'boolean',
                    },
                    include_worktrees = {
                        type = 'boolean',
                    },
                    include_submodules = {
                        type = 'boolean',
                    },
                },
            },
            handler = function(arguments)
                local path, path_err = optional_string(arguments, 'path')
                if path_err ~= nil then
                    return nil, path_err
                end

                local include_tags, tags_err = optional_boolean(arguments, 'include_tags')
                if tags_err ~= nil then
                    return nil, tags_err
                end

                local include_stashes, stashes_err = optional_boolean(arguments, 'include_stashes')
                if stashes_err ~= nil then
                    return nil, stashes_err
                end

                local include_worktrees, worktrees_err = optional_boolean(arguments, 'include_worktrees')
                if worktrees_err ~= nil then
                    return nil, worktrees_err
                end

                local include_submodules, submodules_err = optional_boolean(arguments, 'include_submodules')
                if submodules_err ~= nil then
                    return nil, submodules_err
                end

                return context.repository_refs(path, {
                    include_tags = include_tags == true,
                    include_stashes = include_stashes == true,
                    include_worktrees = include_worktrees == true,
                    include_submodules = include_submodules == true,
                })
            end,
        },
        {
            name = 'list_paths',
            description = 'Read Stratum-backed changed-path lists for a repository, defaulting to the current buffer repository.',
            input_schema = {
                type = 'object',
                properties = {
                    path = {
                        type = 'string',
                    },
                    include_entries = {
                        type = 'boolean',
                    },
                },
            },
            handler = function(arguments)
                local path, path_err = optional_string(arguments, 'path')
                if path_err ~= nil then
                    return nil, path_err
                end

                local include_entries, entries_err = optional_boolean(arguments, 'include_entries')
                if entries_err ~= nil then
                    return nil, entries_err
                end

                return context.repository_paths(path, {
                    include_entries = include_entries == true,
                })
            end,
        },
        {
            name = 'path_state',
            description = 'Read Stratum-backed Git state for a path, defaulting to the current buffer path.',
            input_schema = {
                type = 'object',
                properties = {
                    path = {
                        type = 'string',
                    },
                },
            },
            handler = function(arguments)
                local path, path_err = optional_string(arguments, 'path')
                if path_err ~= nil then
                    return nil, path_err
                end

                return context.path_state(path)
            end,
        },
    }
end

return M
