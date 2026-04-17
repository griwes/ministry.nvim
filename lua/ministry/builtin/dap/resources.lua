local context = require('ministry.builtin.dap.context')

local M = {}

---@return ministry.ResourceSpec[]
function M.specs()
    return {
        {
            uri = 'dap://summary',
            name = 'DAP Summary',
            description = 'Lightweight summary of the active dap.nvim debugger session.',
            mime_type = 'application/json',
            handler = function()
                return context.summary()
            end,
        },
        {
            uri = 'dap://breakpoints',
            name = 'DAP Breakpoints',
            description = 'Current dap.nvim breakpoints with editor-visible file paths.',
            mime_type = 'application/json',
            handler = function()
                return context.breakpoints()
            end,
        },
        {
            uri = 'dap://threads',
            name = 'DAP Threads',
            description = 'Debugger thread state for the active dap.nvim session.',
            mime_type = 'application/json',
            handler = function()
                return context.threads()
            end,
        },
    }
end

---@return ministry.ResourceTemplateSpec[]
function M.templates()
    return {
        {
            name = 'DAP Stack',
            uri_template = 'dap://stack/{thread_id}',
            description = 'Stack frames for a debugger thread in the active dap.nvim session.',
            mime_type = 'application/json',
            handler = function(arguments)
                local value = arguments and tonumber(arguments.thread_id) or nil
                return context.stack(value)
            end,
        },
        {
            name = 'DAP Scopes',
            uri_template = 'dap://scopes/{frame_id}',
            description = 'Debugger scopes for a frame in the active dap.nvim session.',
            mime_type = 'application/json',
            handler = function(arguments)
                local value = arguments and tonumber(arguments.frame_id) or nil
                return context.scopes(value)
            end,
        },
        {
            name = 'DAP Variables',
            uri_template = 'dap://variables/{variables_reference}',
            description = 'Debugger variables for a variablesReference in the active dap.nvim session.',
            mime_type = 'application/json',
            handler = function(arguments)
                local value = arguments and tonumber(arguments.variables_reference) or nil
                return context.variables(value)
            end,
        },
    }
end

return M
