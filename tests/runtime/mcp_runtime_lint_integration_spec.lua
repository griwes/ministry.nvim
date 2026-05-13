local function read_json_resource(plugin, uri, request_id)
    local response = plugin.handle_request('resources/read', {
        uri = uri,
    }, request_id, {})
    assert(
        response and response.result and response.result.contents and response.result.contents[1],
        'missing resource response'
    )
    return vim.json.decode(response.result.contents[1].text)
end

describe('mcp lint real-plugin integration', function()
    it('reads lint summary after loading real nvim-lint', function()
        local lazy_dir = vim.fn.stdpath('data') .. '/lazy/nvim-lint'
        if vim.fn.isdirectory(lazy_dir) == 0 then
            pending('nvim-lint is not installed in the isolated lazy test root')
            return
        end
        vim.opt.runtimepath:prepend(lazy_dir)

        local lint = require('lint')
        vim.bo.filetype = 'lua'
        lint.linters_by_ft.lua = { 'luacheck' }

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local payload = read_json_resource(plugin, 'neovim/lint://summary', 1)
        assert.is_true(payload.available)
        assert.are.equal('lua', payload.filetype)
        assert.are.same({ 'luacheck' }, payload.linters)
    end)
end)
