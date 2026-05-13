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

describe('mcp formatting real-plugin integration', function()
    it('reads formatting summary after loading real conform.nvim', function()
        local lazy_dir = vim.fn.stdpath('data') .. '/lazy/conform.nvim'
        if vim.fn.isdirectory(lazy_dir) == 0 then
            pending('conform.nvim is not installed in the isolated lazy test root')
            return
        end
        vim.opt.runtimepath:prepend(lazy_dir)

        local conform = require('conform')
        vim.bo.filetype = 'lua'
        conform.formatters_by_ft.lua = { 'stylua' }

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local payload = read_json_resource(plugin, 'neovim/formatting://summary', 1)
        assert.is_true(payload.available)
        assert.are.equal('lua', payload.filetype)
        assert.are.same({ 'stylua' }, payload.formatters)
    end)
end)
