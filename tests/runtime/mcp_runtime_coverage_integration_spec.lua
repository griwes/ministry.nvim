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

describe('mcp coverage real-plugin integration', function()
    it('reads the coverage summary resource after loading the real plugin', function()
        local lazy_dir = vim.fn.stdpath('data') .. '/lazy/nvim-coverage'
        if vim.fn.isdirectory(lazy_dir) == 0 then
            pending('nvim-coverage is not installed in the isolated lazy test root')
            return
        end
        vim.opt.runtimepath:prepend(lazy_dir)

        local report = require('coverage.report')
        report.cache({
            totals = {
                statements = 1,
                missing = 0,
                coverage = 100,
            },
            files = {
                {
                    filename = vim.fs.normalize(vim.fn.getcwd() .. '/coverage-fixture.lua'),
                    statements = 1,
                    missing = 0,
                    coverage = 100,
                },
            },
        }, 'lua')

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local payload = read_json_resource(plugin, 'neovim/coverage://summary', 1)
        assert.is_true(payload.available)
        assert.are.equal('lua', payload.language)
        assert.are.equal(1, #payload.files)

        report.clear()
    end)
end)
