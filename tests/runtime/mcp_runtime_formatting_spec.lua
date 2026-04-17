describe('mcp formatting builtin surfaces', function()
    local original_conform

    before_each(function()
        require('ministry').reset()
        original_conform = package.loaded['conform']
    end)

    after_each(function()
        package.loaded['conform'] = original_conform
    end)

    it('returns a stable unavailable payload when formatter state is absent', function()
        package.loaded['conform'] = nil

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/formatting://summary',
        }, 1, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_false(payload.available)
        assert.are.equal(vim.bo.filetype, payload.filetype)
        assert.are.same({}, payload.formatters)
    end)

    it('returns normalized configured formatter names', function()
        vim.bo.filetype = 'lua'
        package.loaded['conform'] = {
            formatters_by_ft = {
                lua = { 'stylua', 'trim_whitespace' },
            },
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/formatting://summary',
        }, 2, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal('lua', payload.filetype)
        assert.are.same({ 'stylua', 'trim_whitespace' }, payload.formatters)
    end)
end)
