local context = require('ministry.builtin.dap.context')

local M = {}

local function action_tool(name, description, handler)
    return {
        name = name,
        description = description,
        input_schema = {
            type = 'object',
            properties = {},
        },
        handler = function()
            return handler()
        end,
    }
end

---@return ministry.ToolSpec[]
function M.specs()
    return {
        action_tool('continue', 'Continue execution in the active dap.nvim session.', context.continue),
        action_tool('pause', 'Pause execution in the active dap.nvim session.', context.pause),
        action_tool('step_over', 'Step over in the active dap.nvim session.', context.step_over),
        action_tool('step_into', 'Step into in the active dap.nvim session.', context.step_into),
        action_tool('step_out', 'Step out in the active dap.nvim session.', context.step_out),
        action_tool('terminate', 'Terminate the active dap.nvim session.', context.terminate),
        action_tool('disconnect', 'Disconnect the active dap.nvim session.', context.disconnect),
    }
end

return M
