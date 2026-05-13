describe('mcp mason builtin surfaces', function()
    local original_registry

    before_each(function()
        require('tests.helpers.ministry').reset()
        original_registry = package.loaded['mason-registry']
    end)

    after_each(function()
        package.loaded['mason-registry'] = original_registry
    end)

    it('returns a stable unavailable payload when Mason is absent', function()
        package.loaded['mason-registry'] = nil

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/mason://inventory',
        }, 1, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_false(payload.available)
        assert.are.same({}, payload.packages)
    end)

    it('returns installed Mason packages in stable order', function()
        package.loaded['mason-registry'] = {
            get_installed_packages = function()
                return {
                    {
                        name = 'stylua',
                    },
                    {
                        get_name = function()
                            return 'lua-language-server'
                        end,
                    },
                    {
                        name = 'debugpy',
                    },
                }
            end,
        }

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/mason://inventory',
        }, 2, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.same({
            { name = 'debugpy' },
            { name = 'lua-language-server' },
            { name = 'stylua' },
        }, payload.packages)
    end)
end)
