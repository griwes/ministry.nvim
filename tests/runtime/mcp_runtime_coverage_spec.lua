describe('mcp coverage builtin surfaces', function()
    local original_report

    before_each(function()
        require('ministry').reset()
        original_report = package.loaded['coverage.report']
    end)

    after_each(function()
        package.loaded['coverage.report'] = original_report
    end)

    it('returns a stable unavailable payload when coverage state is absent', function()
        package.loaded['coverage.report'] = {
            is_cached = function()
                return false
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/coverage://summary',
        }, 1, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_false(payload.available)
        assert.is_nil(payload.language)
        assert.is_nil(payload.totals)
        assert.are.same({}, payload.files)
    end)

    it('returns normalized cached coverage summaries', function()
        package.loaded['coverage.report'] = {
            is_cached = function()
                return true
            end,
            get = function()
                return {
                    totals = {
                        statements = 10,
                        missing = 2,
                        coverage = 80,
                    },
                    files = {
                        {
                            filename = '/tmp/z.lua',
                            statements = 5,
                            missing = 1,
                            coverage = 80,
                        },
                        {
                            filename = '/tmp/a.lua',
                            statements = 5,
                            missing = 1,
                            coverage = 80,
                        },
                    },
                }
            end,
            language = function()
                return 'lua'
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/coverage://summary',
        }, 2, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal('lua', payload.language)
        assert.are.same({
            statements = 10,
            missing = 2,
            coverage = 80,
        }, payload.totals)
        assert.are.same({
            {
                filename = '/tmp/a.lua',
                statements = 5,
                missing = 1,
                coverage = 80,
            },
            {
                filename = '/tmp/z.lua',
                statements = 5,
                missing = 1,
                coverage = 80,
            },
        }, payload.files)
    end)
end)
