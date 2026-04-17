local function read_json_resource(plugin, uri, request_id)
    local response = plugin.handle_request('resources/read', {
        uri = uri,
    }, request_id, {})
    assert(response and response.result and response.result.contents and response.result.contents[1], 'missing resource response')
    return vim.json.decode(response.result.contents[1].text)
end

describe('mcp mason real-plugin integration', function()
    it('reads the Mason inventory resource after loading the real plugin', function()
        local lazy_dir = vim.fn.stdpath('data') .. '/lazy/mason.nvim'
        if vim.fn.isdirectory(lazy_dir) == 0 then
            pending('mason.nvim is not installed in the isolated lazy test root')
            return
        end
        vim.opt.runtimepath:prepend(lazy_dir)

        local mason = require('mason')
        mason.setup({})

        local plugin = require('ministry')
        plugin.setup()

        local payload = read_json_resource(plugin, 'neovim/mason://inventory', 1)
        assert.is_true(type(payload.available) == 'boolean')
        assert.is_true(type(payload.packages) == 'table')
    end)
end)
