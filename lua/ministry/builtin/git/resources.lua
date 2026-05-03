local context = require('ministry.builtin.git.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'git://repository',
            name = 'Git Repository Summary',
            description = 'Structured current-buffer repository state from stratum.nvim when available.',
            mime_type = 'application/json',
            handler = function()
                return context.repository_summary()
            end,
        },
        {
            uri = 'git://overview',
            name = 'Git Repository Overview',
            description = 'Compact Stratum-backed repository, ref, changed-path, and current-path state for agent context.',
            mime_type = 'application/json',
            handler = function()
                return context.repository_overview()
            end,
        },
        {
            uri = 'git://path',
            name = 'Git Current Path State',
            description = 'Structured Stratum-backed Git state for the current buffer path.',
            mime_type = 'application/json',
            handler = function()
                return context.path_state()
            end,
        },
        {
            uri = 'git://paths',
            name = 'Git Repository Paths',
            description = 'Structured Stratum-backed changed-path lists and counts for the current buffer repository.',
            mime_type = 'application/json',
            handler = function()
                return context.repository_paths()
            end,
        },
        {
            uri = 'git://refs',
            name = 'Git Repository Refs',
            description = 'Structured Stratum-backed branch, upstream, operation, and remote state for the current buffer repository.',
            mime_type = 'application/json',
            handler = function()
                return context.repository_refs()
            end,
        },
    }
end

return M
