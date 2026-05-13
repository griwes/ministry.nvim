describe('mcp lint builtin surfaces', function()
    local original_lint

    before_each(function()
        require('tests.helpers.ministry').reset()
        original_lint = package.loaded['lint']
    end)

    after_each(function()
        package.loaded['lint'] = original_lint
    end)

    it('returns a stable unavailable payload when lint state is absent', function()
        package.loaded['lint'] = nil

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/lint://summary',
        }, 1, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_false(payload.available)
        assert.are.equal(vim.bo.filetype, payload.filetype)
        assert.are.same({}, payload.linters)
        assert.are.same({}, payload.running)
    end)

    it('returns normalized lint configuration and running state', function()
        vim.bo.filetype = 'lua'
        package.loaded['lint'] = {
            linters_by_ft = {
                lua = { 'luacheck' },
            },
            get_running = function()
                return { 'luacheck' }
            end,
        }

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/lint://summary',
        }, 2, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal('lua', payload.filetype)
        assert.are.same({ 'luacheck' }, payload.linters)
        assert.are.same({ 'luacheck' }, payload.running)
    end)
end)
