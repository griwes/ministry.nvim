local resources = require('ministry.builtin.navigation.resources')

local M = {}

---@return ministry.ServerSpec
function M.server_spec()
    return {
        name = 'navigation',
        title = 'Navigation',
        description = 'Built-in Neovim navigation-anchor observation surfaces.',
        resources = resources.specs(),
        namespaces = {
            resources = {
                navigation = 'Builtin Neovim mark and navigation anchors.',
            },
        },
    }
end

return M
