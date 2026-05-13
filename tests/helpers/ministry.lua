local M = {}

---@param plugin? ministry.Module
function M.reset(plugin)
    plugin = plugin or require('ministry')
    plugin.reset()
    require('ministry.core.config').set({
        approval = {
            enabled = false,
            persistence = false,
        },
    })
end

---@param plugin ministry.Module
---@param opts? table
---@return ministry.Config
function M.setup(plugin, opts)
    local applied = vim.deepcopy(opts or {})
    applied.approval = vim.tbl_deep_extend('force', {
        enabled = false,
        persistence = false,
    }, applied.approval or {})
    return plugin.setup(applied)
end

return M
