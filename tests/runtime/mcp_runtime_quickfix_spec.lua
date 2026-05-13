describe('mcp quickfix builtin surfaces', function()
    before_each(function()
        require('tests.helpers.ministry').reset()
        vim.cmd('silent! cexpr []')
        vim.cmd('silent! lexpr []')
    end)

    after_each(function()
        vim.cmd('silent! cexpr []')
        vim.cmd('silent! lexpr []')
    end)

    it('returns structured quickfix and location-list summaries', function()
        local quickfix_file = vim.fs.normalize(vim.fn.getcwd() .. '/quickfix.lua')
        local loclist_file = vim.fs.normalize(vim.fn.getcwd() .. '/loclist.lua')

        vim.fn.setqflist({}, ' ', {
            title = 'Workspace Problems',
            context = { source = 'tests', scope = 'workspace' },
            items = {
                {
                    filename = quickfix_file,
                    lnum = 3,
                    col = 5,
                    text = 'Quickfix problem',
                    type = 'E',
                },
            },
        })
        vim.fn.setqflist({}, 'a', { idx = 1 })

        vim.fn.setloclist(0, {}, ' ', {
            title = 'Window Problems',
            context = { source = 'tests', scope = 'window' },
            items = {
                {
                    filename = loclist_file,
                    lnum = 8,
                    col = 2,
                    text = 'Location problem',
                    type = 'W',
                },
            },
        })
        vim.fn.setloclist(0, {}, 'a', { idx = 1 })

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local qf_response = plugin.handle_request('resources/read', {
            uri = 'neovim/quickfix://summary',
        }, 1, {})
        local qf_payload = vim.json.decode(qf_response.result.contents[1].text)

        assert.are.equal('quickfix', qf_payload.kind)
        assert.are.equal('Workspace Problems', qf_payload.title)
        assert.are.equal(1, qf_payload.size)
        assert.are.equal(1, qf_payload.idx)
        assert.is_true(qf_payload.has_current)
        assert.are.equal(quickfix_file, qf_payload.items[1].path)
        assert.are.equal('Quickfix problem', qf_payload.items[1].text)
        assert.are.equal('E', qf_payload.items[1].type)
        assert.are.same({ source = 'tests', scope = 'workspace' }, qf_payload.context)

        local ll_response = plugin.handle_request('resources/read', {
            uri = 'neovim/location-list://current',
        }, 2, {})
        local ll_payload = vim.json.decode(ll_response.result.contents[1].text)

        assert.are.equal('location_list', ll_payload.kind)
        assert.are.equal('Window Problems', ll_payload.title)
        assert.are.equal(1, ll_payload.size)
        assert.are.equal(1, ll_payload.idx)
        assert.is_true(ll_payload.has_current)
        assert.are.equal(loclist_file, ll_payload.items[1].path)
        assert.are.equal('Location problem', ll_payload.items[1].text)
        assert.are.equal('W', ll_payload.items[1].type)
        assert.are.same({ source = 'tests', scope = 'window' }, ll_payload.context)
    end)

    it('returns stable empty quickfix and location-list payloads', function()
        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local qf_response = plugin.handle_request('resources/read', {
            uri = 'neovim/quickfix://summary',
        }, 3, {})
        local qf_payload = vim.json.decode(qf_response.result.contents[1].text)

        assert.are.equal('quickfix', qf_payload.kind)
        assert.are.equal(':silent! cexpr []', qf_payload.title)
        assert.are.equal(0, qf_payload.size)
        assert.are.equal(0, qf_payload.idx)
        assert.is_false(qf_payload.has_current)
        assert.is_nil(qf_payload.current_item)
        assert.are.same({}, qf_payload.items)

        local ll_response = plugin.handle_request('resources/read', {
            uri = 'neovim/location-list://current',
        }, 4, {})
        local ll_payload = vim.json.decode(ll_response.result.contents[1].text)

        assert.are.equal('location_list', ll_payload.kind)
        assert.are.equal(':silent! lexpr []', ll_payload.title)
        assert.are.equal(0, ll_payload.size)
        assert.are.equal(0, ll_payload.idx)
        assert.is_false(ll_payload.has_current)
        assert.is_nil(ll_payload.current_item)
        assert.are.same({}, ll_payload.items)
    end)
end)
