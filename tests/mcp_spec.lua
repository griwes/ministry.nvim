describe('mcp', function()
    before_each(function()
        require('mcp').reset()
    end)

    it('loads and exposes setup', function()
        local plugin = require('mcp')

        assert.are.equal('function', type(plugin.setup))
    end)

    it('registers namespaced logical servers and tools', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            tools = {
                {
                    name = 'read_buffer',
                    handler = function()
                        return {}
                    end,
                },
            },
        })

        plugin.register_tool('editor', {
            name = 'write_buffer',
            description = 'Write a buffer through Neovim-owned semantics.',
            input_schema = {
                type = 'object',
                properties = {
                    path = { type = 'string' },
                },
            },
            handler = function()
                return {}
            end,
        })

        local servers = plugin.list_servers()
        local tools = plugin.list_tool_descriptors()

        assert.are.equal(1, #servers)
        assert.are.equal('editor', servers[1].name)
        assert.are.equal(2, #tools)
        assert.are.equal('editor/read_buffer', tools[1].namespaced_name)
        assert.are.equal('editor/write_buffer', tools[2].namespaced_name)
    end)

    it('describes a Unix-socket bridge endpoint', function()
        local plugin = require('mcp')
        plugin.setup({
            socket_prefix = 'custom_mcp',
            bridge_command = 'socat',
        })

        local endpoint = plugin.endpoint()

        assert.are.equal('socket', endpoint.transport)
        assert.are.equal('abstract', endpoint.socket_kind)
        assert.is_true(vim.startswith(endpoint.socket_name, 'custom_mcp_'))
        assert.are.equal('socat', endpoint.command)
        assert.are.same({ '-', 'ABSTRACT-CONNECT:' .. endpoint.socket_name }, endpoint.args)
    end)

    it('dispatches namespaced tool calls through the unified registry', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            tools = {
                {
                    name = 'echo',
                    handler = function(arguments, ctx)
                        return {
                            echoed = arguments.value,
                            source = ctx.source,
                        }
                    end,
                },
            },
        })

        local result, err = plugin.call_tool('editor/echo', {
            value = 'hello',
        }, {
            source = 'test',
        })

        assert.is_nil(err)
        assert.are.same({
            echoed = 'hello',
            source = 'test',
        }, result)
    end)

    it('returns a structured error for unknown namespaced tools', function()
        local plugin = require('mcp')
        plugin.register_server({
            name = 'editor',
        })

        local result, err = plugin.call_tool('editor/missing', {}, {})

        assert.is_nil(result)
        assert.is_not_nil(err)
        assert.are.equal(-32601, err.code)
    end)

    it('registers resources and prompts under the same logical server', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
        })

        plugin.register_resource('editor', {
            uri = 'buffer://current',
            name = 'Current Buffer',
            description = 'Returns current buffer metadata.',
            handler = function()
                return {}
            end,
        })

        plugin.register_prompt('editor', {
            name = 'summarize_buffer',
            description = 'Summarize the active buffer.',
            handler = function()
                return {}
            end,
        })

        local resources = plugin.list_resource_descriptors()
        local prompts = plugin.list_prompt_descriptors()

        assert.are.equal(1, #resources)
        assert.are.equal('editor/buffer://current', resources[1].namespaced_uri)
        assert.are.equal(1, #prompts)
        assert.are.equal('editor/summarize_buffer', prompts[1].namespaced_name)
    end)
end)
