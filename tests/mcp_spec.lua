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
                read_buffer = {
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

    it('replaces duplicate registrations for the same logical capability', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            tools = {
                read_buffer = {
                    description = 'original tool',
                    handler = function()
                        return { version = 1 }
                    end,
                },
            },
            resources = {
                {
                    uri = 'file:///buffer',
                    name = 'original resource',
                    handler = function()
                        return { contents = {} }
                    end,
                },
            },
            resource_templates = {
                {
                    name = 'buffer-template',
                    uri_template = 'file:///buffer/{id}',
                    handler = function()
                        return { contents = {} }
                    end,
                },
            },
            prompts = {
                {
                    name = 'explain',
                    handler = function()
                        return { messages = {} }
                    end,
                },
            },
        })

        plugin.register_tool('editor', {
            name = 'read_buffer',
            description = 'updated tool',
            handler = function()
                return { version = 2 }
            end,
        })
        plugin.register_resource('editor', {
            uri = 'file:///buffer',
            name = 'updated resource',
            handler = function()
                return { contents = { { uri = 'file:///buffer', text = 'updated' } } }
            end,
        })
        plugin.register_resource_template('editor', {
            name = 'buffer-template',
            uri_template = 'file:///buffer/{id}',
            handler = function()
                return { contents = { { uri = 'file:///buffer/1', text = 'updated' } } }
            end,
        })
        plugin.register_prompt('editor', {
            name = 'explain',
            handler = function()
                return {
                    messages = {
                        {
                            role = 'user',
                            content = { { type = 'text', text = 'updated' } },
                        },
                    },
                }
            end,
        })

        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'editor'
        end)

        assert.are.equal(1, #server.tools)
        assert.are.equal('updated tool', server.tools[1].description)
        assert.are.equal(1, #server.resources)
        assert.are.equal('updated resource', server.resources[1].name)
        assert.are.equal(1, #server.resource_templates)
        assert.are.equal('buffer-template', server.resource_templates[1].name)
        assert.are.equal(1, #server.prompts)
        assert.are.equal('explain', server.prompts[1].name)
    end)

    it('replaces resource templates when existing entries conflict across name and uri template', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            resource_templates = {
                {
                    name = 'buffer-template',
                    uri_template = 'file:///buffer/{id}',
                    handler = function()
                        return { contents = {} }
                    end,
                },
                {
                    name = 'other-template',
                    uri_template = 'file:///buffer/{buffer_id}',
                    handler = function()
                        return { contents = {} }
                    end,
                },
            },
        })

        plugin.register_resource_template('editor', {
            name = 'buffer-template',
            uri_template = 'file:///buffer/{buffer_id}',
            handler = function()
                return { contents = { { uri = 'file:///buffer/1', text = 'updated' } } }
            end,
        })

        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'editor'
        end)

        assert.are.equal(1, #server.resource_templates)
        assert.are.equal('buffer-template', server.resource_templates[1].name)
        assert.are.equal('file:///buffer/{buffer_id}', server.resource_templates[1].uri_template)
    end)

    it('flattens nested tool registration using slash-delimited paths', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                editor = {
                    list_buffers = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
                terminal = {
                    create = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
            },
        })

        local tools = plugin.list_tool_descriptors()

        assert.are.equal('neovim', tools[1].server)
        assert.are.equal('neovim/editor/list_buffers', tools[1].namespaced_name)
        assert.are.equal('neovim/editor/list_buffers', tools[1].name)
        assert.are.equal('neovim/terminal/create', tools[2].namespaced_name)
        assert.are.equal('neovim/terminal/create', tools[2].name)
    end)

    it('keeps explicit flat tool names unchanged', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            tools = require('mcp.builtin.editor.tools').specs(),
        })

        local tools = plugin.list_tool_descriptors()
        local names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, tools)

        assert.is_true(vim.tbl_contains(names, 'editor/list_buffers'))
        assert.is_true(vim.tbl_contains(names, 'editor/read_buffer'))
    end)

    it('treats data-driven tool specs as leaf tools when flattening', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        description = 'Create terminal',
                        input_schema = {
                            type = 'object',
                            properties = {},
                        },
                    },
                },
            },
        })

        local tools = plugin.list_tool_descriptors()

        assert.are.equal(1, #tools)
        assert.are.equal('neovim/terminal/create', tools[1].namespaced_name)
        assert.are.equal('Create terminal', tools[1].description)
    end)

    it('rejects nested entries with non-callable handlers during flattening', function()
        local plugin = require('mcp')

        local ok, err = pcall(function()
            plugin.register_server({
                name = 'neovim',
                tools = {
                    terminal = {
                        handler = 'oops',
                        create = {
                            description = 'Create terminal',
                            input_schema = {
                                type = 'object',
                                properties = {},
                            },
                        },
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.matches('mcp tool handler must be a function', tostring(err), 1, true)
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
        assert.are.equal('editor/summarize_buffer', prompts[1].name)
    end)

    it('rejects initialize requests with unsupported protocol versions', function()
        local plugin = require('mcp')

        local response = plugin.handle_request('initialize', {
            protocolVersion = '2099-01-01',
        }, 11, {})

        assert.is_not_nil(response.error)
        assert.are.equal(-32602, response.error.code)
        assert.are.equal('Unsupported protocol version: 2099-01-01', response.error.message)
    end)

    it('passes through structured MCP tool results', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            tools = {
                {
                    name = 'echo',
                    handler = function()
                        return {
                            content = {
                                {
                                    type = 'text',
                                    text = 'hello',
                                },
                                {
                                    type = 'image',
                                    data = 'Zm9v',
                                    mimeType = 'image/png',
                                },
                            },
                            isError = false,
                        }
                    end,
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            name = 'editor/echo',
            arguments = {},
        }, 12, {})

        assert.is_nil(call.error)
        assert.are.same({
            content = {
                {
                    type = 'text',
                    text = 'hello',
                },
                {
                    type = 'image',
                    data = 'Zm9v',
                    mimeType = 'image/png',
                },
            },
            isError = false,
        }, call.result)
    end)

    it('includes warnings for structured tools/call results without deep-copying nested values', function()
        local plugin = require('mcp')
        local marker = function()
            return true
        end
        local warning = {
            code = -32001,
            message = 'non-fatal warning',
        }

        plugin.register_server({
            name = 'editor',
            tools = {
                {
                    name = 'echo',
                    handler = function()
                        return {
                            content = {
                                {
                                    type = 'text',
                                    text = 'hello',
                                },
                            },
                            marker = marker,
                        }, nil, warning
                    end,
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            name = 'editor/echo',
            arguments = {},
        }, 12, {})

        assert.is_nil(call.error)
        assert.are.equal('hello', call.result.content[1].text)
        assert.are.equal(marker, call.result.marker)
        assert.are.same(warning, call.result.warning)
    end)

    it('includes warnings for content-list tools/call results', function()
        local plugin = require('mcp')
        local warning = {
            code = -32001,
            message = 'non-fatal warning',
        }

        plugin.register_server({
            name = 'editor',
            tools = {
                {
                    name = 'echo',
                    handler = function()
                        return {
                            {
                                type = 'text',
                                text = 'hello',
                            },
                        }, nil, warning
                    end,
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            name = 'editor/echo',
            arguments = {},
        }, 13, {})

        assert.is_nil(call.error)
        assert.are.same({
            content = {
                {
                    type = 'text',
                    text = 'hello',
                },
            },
            warning = warning,
        }, call.result)
    end)

    it('implements MCP resource and prompt companion methods for advertised capabilities', function()
        local plugin = require('mcp')
        local resource_request
        local prompt_request

        plugin.register_server({
            name = 'editor',
        })

        plugin.register_resource('editor', {
            uri = 'buffer://current',
            mime_type = 'application/json',
            handler = function(arguments)
                resource_request = arguments
                return {
                    contents = {
                        {
                            uri = arguments.namespaced_uri,
                            text = vim.json.encode({ ok = true }),
                        },
                    },
                }
            end,
        })

        plugin.register_resource_template('editor', {
            name = 'buffer',
            uri_template = 'buffer://{bufnr}',
            description = 'Buffer template.',
            mime_type = 'application/json',
            handler = function()
                return {}
            end,
        })

        plugin.register_prompt('editor', {
            name = 'summarize_buffer',
            handler = function(request)
                prompt_request = request
                return {
                    messages = {
                        {
                            role = 'user',
                            content = {
                                type = 'text',
                                text = request.arguments.topic,
                            },
                        },
                    },
                }
            end,
        })

        local resource_list = plugin.handle_request('resources/list', {}, 20, {})
        local template_list = plugin.handle_request('resources/templates/list', {}, 21, {})
        local resource_read = plugin.handle_request('resources/read', {
            uri = 'editor/buffer://current',
        }, 22, {})
        local prompt_list = plugin.handle_request('prompts/list', {}, 23, {})
        local prompt_get = plugin.handle_request('prompts/get', {
            name = 'editor/summarize_buffer',
            arguments = {
                topic = 'hello',
            },
        }, 24, {})

        assert.is_nil(resource_list.error)
        assert.are.equal('editor/buffer://current', resource_list.result.resources[1].namespaced_uri)
        assert.is_nil(template_list.error)
        assert.are.equal('buffer://{bufnr}', template_list.result.resourceTemplates[1].uriTemplate)
        assert.is_nil(resource_read.error)
        assert.are.equal('buffer://current', resource_request.uri)
        assert.are.equal('editor/buffer://current', resource_request.namespaced_uri)
        assert.are.equal('editor/buffer://current', resource_read.result.contents[1].uri)
        assert.are.equal('application/json', resource_read.result.contents[1].mimeType)
        assert.is_nil(prompt_list.error)
        assert.are.equal('editor/summarize_buffer', prompt_list.result.prompts[1].namespaced_name)
        assert.are.equal('editor/summarize_buffer', prompt_list.result.prompts[1].name)
        assert.is_nil(prompt_get.error)
        assert.are.equal('hello', prompt_get.result.messages[1].content.text)
        assert.are.equal('summarize_buffer', prompt_request.name)
        assert.are.equal('editor/summarize_buffer', prompt_request.namespaced_name)
    end)

    it('normalizes scalar resource and prompt handler results', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
        })

        plugin.register_resource('editor', {
            uri = 'buffer://scalar',
            handler = function()
                return 7
            end,
        })

        plugin.register_prompt('editor', {
            name = 'scalar_prompt',
            handler = function()
                return 9
            end,
        })

        local resource_read = plugin.handle_request('resources/read', {
            uri = 'editor/buffer://scalar',
        }, 25, {})
        local prompt_get = plugin.handle_request('prompts/get', {
            name = 'editor/scalar_prompt',
        }, 26, {})

        assert.is_nil(resource_read.error)
        assert.are.equal('editor/buffer://scalar', resource_read.result.contents[1].uri)
        assert.are.equal('7', resource_read.result.contents[1].text)
        assert.is_nil(prompt_get.error)
        assert.are.equal('9', prompt_get.result.messages[1].content.text)
    end)

    it('prefers the longest matching server prefix for resources and prompts', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
        })
        plugin.register_server({
            name = 'editor/alt',
        })

        plugin.register_resource('editor', {
            uri = 'buffer://shared',
            handler = function()
                return 'base'
            end,
        })
        plugin.register_resource('editor/alt', {
            uri = 'buffer://shared',
            handler = function()
                return 'nested'
            end,
        })

        plugin.register_prompt('editor', {
            name = 'shared',
            handler = function()
                return 'base-prompt'
            end,
        })
        plugin.register_prompt('editor/alt', {
            name = 'shared',
            handler = function()
                return 'nested-prompt'
            end,
        })

        local resource_read = plugin.handle_request('resources/read', {
            uri = 'editor/alt/buffer://shared',
        }, 27, {})
        local prompt_get = plugin.handle_request('prompts/get', {
            name = 'editor/alt/shared',
        }, 28, {})

        assert.is_nil(resource_read.error)
        assert.are.equal('nested', resource_read.result.contents[1].text)
        assert.is_nil(prompt_get.error)
        assert.are.equal('nested-prompt', prompt_get.result.messages[1].content.text)
    end)

    it('returns method-not-found for unknown router methods', function()
        local plugin = require('mcp')

        local response = plugin.handle_request('wat', {}, 13, {})

        assert.is_not_nil(response.error)
        assert.are.equal(-32601, response.error.code)
        assert.are.equal('Method not found: wat', response.error.message)
    end)

    it('returns tool dispatch failures from tools/call', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            tools = {
                {
                    name = 'explode',
                    handler = function()
                        error('boom')
                    end,
                },
            },
        })

        local response = plugin.handle_request('tools/call', {
            name = 'editor/explode',
            arguments = {},
        }, 14, {})

        assert.is_not_nil(response.error)
        assert.are.equal(-32000, response.error.code)
        assert.truthy(string.find(response.error.message, 'boom', 1, true))
    end)
    it('routes unified MCP requests for initialize, listing, and tool calls', function()
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

        local initialize = plugin.handle_request('initialize', {
            protocolVersion = '2025-06-18',
        }, 1, {})
        local list = plugin.handle_request('tools/list', {}, 2, {})
        local call = plugin.handle_request(
            'tools/call',
            {
                name = 'editor/echo',
                arguments = {
                    value = 'hello',
                },
            },
            3,
            {
                source = 'router-test',
            }
        )

        assert.are.equal('2025-06-18', initialize.result.protocolVersion)
        assert.are.equal('editor/echo', list.result.tools[1].namespaced_name)
        assert.are.equal('editor/echo', list.result.tools[1].name)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = 'hello',
                    source = 'router-test',
                }),
            },
        }, call.result.content)
    end)

    it('accepts standard MCP tools/call requests using the advertised tool name', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        local list = plugin.handle_request('tools/list', {}, 1, {})
        local advertised_name = list.result.tools[1].name
        local call = plugin.handle_request('tools/call', {
            name = advertised_name,
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 2, {})

        assert.are.equal('neovim/terminal/create', advertised_name)
        assert.is_nil(call.error)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = { 'printf', 'hello' },
                }),
            },
        }, call.result.content)
    end)

    it('keeps flattened tool discovery aligned with effective tool lookup', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'alpha',
            tools = {
                terminal = {
                    create = {
                        handler = function()
                            return { server = 'alpha' }
                        end,
                    },
                },
            },
        })

        plugin.register_server({
            name = 'beta',
            tools = {
                workspace = {
                    sync = {
                        handler = function()
                            return { server = 'beta' }
                        end,
                    },
                },
            },
        })

        plugin.register_tool('alpha', {
            name = 'workspace/sync',
            handler = function()
                return { server = 'alpha' }
            end,
        })

        local descriptors = plugin.list_tool_descriptors()
        local names = vim.tbl_map(function(tool)
            return tool.name
        end, descriptors)
        local registry = require('mcp.registry')
        local ambiguous_tool, ambiguous_err = registry.find_tool('workspace__sync')

        assert.is_true(vim.tbl_contains(names, 'alpha/workspace/sync'))
        assert.is_true(vim.tbl_contains(names, 'beta/workspace/sync'))
        assert.is_nil(ambiguous_tool)
        assert.matches('Ambiguous flattened tool name workspace__sync', ambiguous_err, 1, true)
        assert.matches('alpha/workspace/sync', ambiguous_err, 1, true)
        assert.matches('beta/workspace/sync', ambiguous_err, 1, true)
    end)

    it('accepts unique flattened tools/call names', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            name = 'terminal__create',
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 3, {})

        assert.is_nil(call.error)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = { 'printf', 'hello' },
                }),
            },
        }, call.result.content)
    end)

    it('rejects ambiguous flattened tools/call names', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'alpha',
            tools = {
                terminal = {
                    create = {
                        handler = function()
                            return { server = 'alpha' }
                        end,
                    },
                },
            },
        })

        plugin.register_server({
            name = 'beta',
            tools = {
                terminal = {
                    create = {
                        handler = function()
                            return { server = 'beta' }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            name = 'terminal__create',
            arguments = {},
        }, 4, {})

        assert.is_nil(call.result)
        assert.is_not_nil(call.error)
        assert.are.equal(-32601, call.error.code)
        assert.matches('Ambiguous flattened tool name terminal__create', call.error.message, 1, true)
        assert.matches('alpha/terminal/create', call.error.message, 1, true)
        assert.matches('beta/terminal/create', call.error.message, 1, true)
    end)

    it('accepts tools/call requests that provide server and tool separately', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'neovim',
            tool = 'terminal/create',
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 4, {})

        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = { 'printf', 'hello' },
                }),
            },
        }, call.result.content)
    end)

    it('accepts tools/call requests that provide server with a flattened tool name', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'neovim',
            tool = 'terminal__create',
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 5, {})

        assert.is_nil(call.error)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = { 'printf', 'hello' },
                }),
            },
        }, call.result.content)
    end)

    it('accepts split tools/call payloads with unique flattened tool names', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                editor = {
                    list_buffers = {
                        handler = function()
                            return {
                                ok = true,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'neovim',
            tool = 'editor__list_buffers',
        }, 7, {})

        assert.is_nil(call.error)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    ok = true,
                }),
            },
        }, call.result.content)
    end)

    it('does not double-prefix split tools/call payloads whose tool is already qualified', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    wait = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.terminal_id,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'neovim',
            tool = 'neovim/terminal/wait',
            arguments = {
                terminal_id = 'term-123',
            },
        }, 6, {})

        assert.is_nil(call.error)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = 'term-123',
                }),
            },
        }, call.result.content)
    end)

    it('does not treat prefix-collision server names as already qualified', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'ed',
            tools = {
                editor = {
                    run = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        plugin.register_server({
            name = 'editor',
            tools = {
                run = {
                    handler = function()
                        error('wrong server')
                    end,
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'ed',
            tool = 'editor/run',
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 6, {})

        assert.is_nil(call.error)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = { 'printf', 'hello' },
                }),
            },
        }, call.result.content)
    end)

    it('accepts the exact split payload shape over the advertised socat bridge', function()
        local plugin = require('mcp')

        plugin.setup({ enable_terminal_tools = true })

        local ok, err = plugin.start_all()
        assert.is_true(ok)
        assert.is_nil(err)

        local endpoint = plugin.endpoint()
        local payload = vim.json.encode({
            jsonrpc = '2.0',
            id = 99,
            method = 'tools/call',
            params = {
                server = 'neovim',
                tool = 'terminal/create',
                arguments = {
                    command = { 'printf', 'hello' },
                },
            },
        })

        local shell_script =
            string.format("cat <<'EOF' | socat - ABSTRACT-CONNECT:%s\n%s\nEOF", endpoint.socket_name, payload)
        local result = vim.system({ 'sh', '-lc', shell_script }, {
            text = true,
        }):wait()

        assert.are.equal(0, result.code)
        local response_line =
            vim.trim((result.stdout or ''):match('(%b{})') or (result.stderr or ''):match('(%b{})') or '')
        local response = vim.json.decode(response_line)
        assert.are.equal(99, response.id)
        assert.is_nil(response.error)
        assert.are.same('text', response.result.content[1].type)
    end)

    it('accepts tools/call requests that provide serverName and toolName separately', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            serverName = 'neovim',
            toolName = 'terminal/create',
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 6, {})

        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = { 'printf', 'hello' },
                }),
            },
        }, call.result.content)
    end)

    it('does not infer routing from tools/call arguments.server and arguments.tool', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            arguments = {
                server = 'neovim',
                tool = 'terminal/create',
                command = { 'printf', 'hello' },
            },
        }, 8, {})

        assert.are.same({
            code = -32602,
            message = 'Missing tool identifier',
        }, call.error)
    end)

    it('preserves arguments.server and arguments.tool when routing is provided by name', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                echo = {
                    server = {
                        handler = function(arguments)
                            return {
                                server = arguments.server,
                                tool = arguments.tool,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            name = 'neovim/echo/server',
            arguments = {
                server = 'payload-server',
                tool = 'payload-tool',
            },
        }, 9, {})

        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    server = 'payload-server',
                    tool = 'payload-tool',
                }),
            },
        }, call.result.content)
    end)

    it('preserves arguments.server and arguments.tool when routing is provided by top-level server and tool', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                echo = {
                    server = {
                        handler = function(arguments)
                            return {
                                server = arguments.server,
                                tool = arguments.tool,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'neovim',
            tool = 'echo/server',
            arguments = {
                server = 'payload-server',
                tool = 'payload-tool',
            },
        }, 10, {})

        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    server = 'payload-server',
                    tool = 'payload-tool',
                }),
            },
        }, call.result.content)
    end)

    it('rejects tools/call requests that provide only tool without server context', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                terminal = {
                    create = {
                        handler = function(arguments)
                            return {
                                echoed = arguments.command,
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            tool = 'terminal/create',
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 8, {})

        assert.is_not_nil(call.error)
        assert.are.equal(-32602, call.error.code)
        assert.are.equal('Missing tool identifier', call.error.message)
    end)

    it('starts and stops the live server lifecycle', function()
        local plugin = require('mcp')

        local ok, err = plugin.start()

        assert.is_true(ok)
        assert.is_nil(err)
        assert.is_true(plugin.running())

        plugin.stop()

        assert.is_false(plugin.running())
    end)

    it('clears listener state when socket startup fails', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local original_new_pipe = vim.uv.new_pipe
        local pipe = {
            bind2 = function()
                return 0
            end,
            listen = function()
                return nil, 'listen failed'
            end,
            is_closing = function()
                return false
            end,
            close = function() end,
        }

        vim.uv.new_pipe = function()
            return pipe
        end

        local ok, err = plugin.start()

        vim.uv.new_pipe = original_new_pipe

        assert.is_false(ok)
        assert.are.equal('listen failed', err)
        assert.is_false(plugin.running())
        assert.are.same({
            has_listener = false,
            listener_closing = false,
            client_count = 0,
        }, server.debug_state())
    end)

    it('serves parse errors and closes a client on socket read failure', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local original_new_pipe = vim.uv.new_pipe
        local listener_read_cb
        local accepted_client
        local writes = {}
        local client_closed = false
        local accepted = false
        local notify_messages = {}
        local original_notify = vim.notify
        local listener_pipe = {
            bind2 = function()
                return 0
            end,
            listen = function(_, _, cb)
                listener_read_cb = cb
                return true
            end,
            accept = function(_, client)
                accepted = true
                accepted_client = client
                return true
            end,
            is_closing = function()
                return false
            end,
            close = function() end,
        }
        local client_pipe
        client_pipe = {
            read_start = function(_, cb)
                client_pipe._read_cb = cb
                return true
            end,
            read_stop = function() end,
            write = function(_, message)
                table.insert(writes, vim.json.decode(message))
            end,
            is_closing = function()
                return client_closed
            end,
            close = function()
                client_closed = true
            end,
        }
        local pipe_count = 0

        vim.notify = function(message)
            table.insert(notify_messages, message)
        end

        vim.uv.new_pipe = function()
            pipe_count = pipe_count + 1
            if pipe_count == 1 then
                return listener_pipe
            end

            return client_pipe
        end

        local ok, err = plugin.start()
        assert.is_true(ok)
        assert.is_nil(err)

        listener_read_cb(nil)
        assert.is_true(accepted)
        assert.is_not_nil(accepted_client)

        client_pipe._read_cb(nil, '{bad json}\n')
        client_pipe._read_cb('read failed', nil)

        vim.wait(1000, function()
            return writes[1] ~= nil and #notify_messages > 0
        end)

        assert.are.equal(-32700, writes[1].error.code)
        assert.is_true(client_closed)
        assert.is_true(notify_messages[1]:find('mcp socket client read error: read failed', 1, true) ~= nil)
        assert.are.same({
            has_listener = true,
            listener_closing = false,
            client_count = 0,
        }, server.debug_state())

        plugin.stop()
        vim.uv.new_pipe = original_new_pipe
        vim.notify = original_notify
    end)

    it('clears buffered malformed HTTP payloads before closing the client', function()
        local http_server = require('mcp.http_server')
        local original_send_json_response = http_server._send_json_response
        local sent_response
        local client_closed = false
        local client = {
            _mcp_http_buffer = nil,
            read_start = function(_, cb)
                client._read_cb = cb
                return true
            end,
            read_stop = function() end,
            is_closing = function()
                return client_closed
            end,
            close = function()
                client_closed = true
            end,
        }

        http_server._send_json_response = function(_, _, encoded, keep_alive, http_version)
            sent_response = {
                body = vim.json.decode(encoded),
                keep_alive = keep_alive,
                http_version = http_version,
            }
            client:close()
        end

        http_server._start_client_read(client, nil)
        client._read_cb(nil, '{bad json}\n')

        assert.is_not_nil(sent_response)
        assert.are.equal(-32700, sent_response.body.error.code)
        assert.are.equal('', client._mcp_http_buffer)
        assert.is_true(client_closed)

        http_server._send_json_response = original_send_json_response
    end)

    it('registers the built-in editor server during setup', function()
        local plugin = require('mcp')

        plugin.setup({ enable_terminal_tools = true })

        local servers = plugin.list_servers()
        local tools = plugin.list_tool_descriptors()
        local resources = plugin.list_resource_descriptors()
        local prompts = plugin.list_prompt_descriptors()

        local server_names = vim.tbl_map(function(server)
            return server.name
        end, servers)
        local tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, tools)
        local resource_names = vim.tbl_map(function(resource)
            return resource.namespaced_uri
        end, resources)
        local prompt_names = vim.tbl_map(function(prompt)
            return prompt.namespaced_name
        end, prompts)

        local listed, listed_err = plugin.call_tool('neovim/editor/list_buffers', {}, {})

        assert.is_nil(listed_err)
        assert.is_true(vim.tbl_contains(server_names, 'neovim'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
        assert.is_false(vim.tbl_contains(tool_names, 'neovim/editor/read_current_buffer'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/editor/list_buffers'))
        assert.is_false(vim.tbl_contains(resource_names, 'neovim/buffer://current'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/buffers://list'))
        assert.are.same({}, prompt_names)
        assert.are.equal(1, #listed.buffers)
        assert.are.equal(1, listed.buffers[1].bufnr)
        assert.is_table(listed.buffers[1].lines)
    end)

    it('advertises terminal tools when explicitly enabled', function()
        local plugin = require('mcp')

        plugin.setup({ enable_terminal_tools = true })

        local tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_true(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
    end)

    it('does not advertise terminal tools by default', function()
        local plugin = require('mcp')

        plugin.setup()

        local tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_false(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
    end)

    it('drops built-in terminal tools when setup disables them after enabling', function()
        local plugin = require('mcp')

        plugin.setup({ enable_terminal_tools = true })
        plugin.setup({ enable_terminal_tools = false })

        local tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_false(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/editor/list_buffers'))
    end)

    it('merges built-ins into an existing neovim server during setup', function()
        local plugin = require('mcp')
        local builtin_editor = require('mcp.builtin.editor.init')
        local original_server_spec = builtin_editor.server_spec
        local builtin_resource_template = {
            uri_template = 'buffers://{bufnr}',
            name = 'Built-in Buffer Template',
            handler = function()
                return {}
            end,
        }

        local ok, err = pcall(function()
            builtin_editor.server_spec = function()
                local spec = original_server_spec()
                spec.resource_templates = { builtin_resource_template }
                return spec
            end

            plugin.register_server({
                name = 'neovim',
                tools = {
                    custom = {
                        ping = {
                            handler = function()
                                return { ok = true }
                            end,
                        },
                    },
                },
                resources = {
                    {
                        uri = 'custom://status',
                        name = 'Custom Status',
                        handler = function()
                            return {}
                        end,
                    },
                },
                resource_templates = {
                    {
                        uri_template = 'custom://status/{id}',
                        name = 'Custom Status Template',
                        handler = function()
                            return {}
                        end,
                    },
                },
                prompts = {
                    {
                        name = 'custom_prompt',
                        handler = function()
                            return {}
                        end,
                    },
                },
            })

            plugin.setup({ enable_terminal_tools = true })
            plugin.setup({ enable_terminal_tools = true })

            local tools = plugin.list_tool_descriptors()
            local resources = plugin.list_resource_descriptors()
            local prompts = plugin.list_prompt_descriptors()
            local server = vim.iter(plugin.list_servers()):find(function(item)
                return item.name == 'neovim'
            end)
            local builtin_server = builtin_editor.server_spec()
            local tool_names = vim.tbl_map(function(tool)
                return tool.namespaced_name
            end, tools)
            local resource_names = vim.tbl_map(function(resource)
                return resource.namespaced_uri
            end, resources)
            local prompt_names = vim.tbl_map(function(prompt)
                return prompt.namespaced_name
            end, prompts)

            local custom_result = plugin.call_tool('neovim/custom/ping', {}, {})
            local builtin_result = plugin.call_tool('neovim/editor/list_buffers', {}, {})

            assert.is_true(vim.tbl_contains(tool_names, 'neovim/custom/ping'))
            assert.is_true(vim.tbl_contains(tool_names, 'neovim/editor/list_buffers'))
            assert.is_true(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/custom/ping'
                end, tool_names))
            )
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/editor/list_buffers'
                end, tool_names))
            )
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/terminal/create'
                end, tool_names))
            )
            assert.is_true(vim.tbl_contains(resource_names, 'neovim/custom://status'))
            assert.is_true(vim.tbl_contains(resource_names, 'neovim/buffers://list'))
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/custom://status'
                end, resource_names))
            )
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/buffers://list'
                end, resource_names))
            )
            assert.is_true(vim.tbl_contains(prompt_names, 'neovim/custom_prompt'))
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/custom_prompt'
                end, prompt_names))
            )
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(template)
                    return template.uri_template == 'custom://status/{id}'
                end, server.resource_templates or {}))
            )
            for _, template in ipairs(builtin_server.resource_templates or {}) do
                assert.are.equal(
                    1,
                    vim.tbl_count(vim.tbl_filter(function(item)
                        return item.uri_template == template.uri_template
                    end, server.resource_templates or {}))
                )
            end
            assert.are.same({ ok = true }, custom_result)
            assert.are.equal(1, #builtin_result.buffers)
        end)

        builtin_editor.server_spec = original_server_spec
        assert.is_true(ok, err)
    end)

    it('exposes a bridge-friendly endpoint invocation descriptor', function()
        local plugin = require('mcp')
        plugin.setup({
            socket_prefix = 'invoke_mcp',
            bridge_command = 'socat',
        })

        local invocation = plugin.endpoint_invocation()
        local endpoint = plugin.endpoint()

        assert.are.equal('socat', invocation.command)
        assert.are.same({ '-', 'ABSTRACT-CONNECT:' .. endpoint.socket_name }, invocation.args)
    end)

    it('describes an HTTP endpoint when configured', function()
        local plugin = require('mcp')
        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 8877,
        })

        local endpoint = plugin.endpoint()

        assert.are.equal('http', endpoint.transport)
        assert.are.equal('http://127.0.0.1:8877/mcp', endpoint.url)
        assert.are.equal(8877, endpoint.http_port)
    end)

    it('brackets IPv6 hosts in advertised HTTP endpoints', function()
        local plugin = require('mcp')
        plugin.setup({
            transport = 'http',
            http_host = '::1',
            http_port = 8877,
        })

        local endpoint = plugin.endpoint()

        assert.are.equal('http://[::1]:8877/mcp', endpoint.url)
    end)

    it('does not advertise a concrete HTTP port before startup binds an ephemeral port', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')

        local endpoint = nil
        local invocation = nil
        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
            })

            http_server.stop()
            endpoint = plugin.endpoint()
            invocation = plugin.endpoint_invocation()
        end, debug.traceback)

        plugin.reset()

        if not ok then
            error(err)
        end

        assert.are.equal('http', endpoint.transport)
        assert.is_nil(endpoint.url)
        assert.are.equal(0, endpoint.http_port)
        assert.are.same({}, invocation)
    end)

    it('restores defaults for omitted config on repeated setup calls', function()
        local plugin = require('mcp')

        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 8877,
            enable_terminal_tools = true,
        })

        plugin.setup({
            http_host = '127.0.0.2',
        })

        local endpoint = plugin.endpoint()
        local config = require('mcp.config').get()

        assert.are.equal('socket', config.transport)
        assert.are.equal('127.0.0.2', config.http_host)
        assert.are.equal(0, config.http_port)
        assert.is_false(config.enable_terminal_tools)
        assert.are.equal('socket', endpoint.transport)
    end)

    it('starts the configured HTTP transport during setup by default', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local start_calls = {}
        local http_start_calls = 0
        local original_start = server.start
        local original_start_http = server.start_http

        server.start = function(transport)
            table.insert(start_calls, transport)
            return true, nil
        end

        server.start_http = function()
            http_start_calls = http_start_calls + 1
            return true, nil
        end

        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 8877,
            })

            assert.are.same({ 'http' }, start_calls)
            assert.are.equal(0, http_start_calls)
        end, debug.traceback)

        server.start_http = original_start_http
        server.start = original_start

        if not ok then
            error(err)
        end
    end)

    it('starts HTTP during setup by default when socket transport is unavailable', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local start_calls = {}
        local http_start_calls = 0
        local original_start = server.start
        local original_start_http = server.start_http
        local original_new_pipe = vim.uv.new_pipe

        server.start = function(transport)
            table.insert(start_calls, transport)
            return true, nil
        end

        server.start_http = function()
            http_start_calls = http_start_calls + 1
            return true, nil
        end

        vim.uv.new_pipe = function()
            return {
                close = function() end,
            }
        end

        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 8877,
            })

            assert.are.same({ 'http' }, start_calls)
            assert.are.equal(0, http_start_calls)
        end, debug.traceback)

        vim.uv.new_pipe = original_new_pipe
        server.start_http = original_start_http
        server.start = original_start

        if not ok then
            error(err)
        end
    end)

    it('preserves keyed entries when sanitizing mixed warning tables', function()
        local plugin = require('mcp')
        plugin.register_server({
            name = 'test',
            tools = {
                {
                    name = 'warn',
                    handler = function()
                        return 'ok', nil, { 'warning', code = 1 }
                    end,
                },
            },
        })

        local response = plugin.handle_request('tools/call', {
            name = 'test/warn',
            arguments = {},
        }, 1, {})

        assert.are.same({
            jsonrpc = '2.0',
            id = 1,
            result = {
                content = {
                    {
                        type = 'text',
                        text = 'ok',
                    },
                },
                warning = { 'warning', code = 1 },
            },
        }, response)
    end)

    it('preserves list ordering when sanitizing warning arrays', function()
        local plugin = require('mcp')
        plugin.register_server({
            name = 'test-ordered',
            tools = {
                {
                    name = 'warn',
                    handler = function()
                        return 'ok', nil, { 'first', 'second', 'third' }
                    end,
                },
            },
        })

        local response = plugin.handle_request('tools/call', {
            name = 'test-ordered/warn',
            arguments = {},
        }, 1, {})

        assert.are.same({ 'first', 'second', 'third' }, response.result.warning)
    end)

    it('starts the configured socket transport during setup when bind2 is supported', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local start_calls = {}
        local original_start = server.start
        local original_new_pipe = vim.uv.new_pipe
        local pipe_closed = false
        local new_pipe_arg

        server.start = function(transport)
            table.insert(start_calls, transport)
            return true, nil
        end

        vim.uv.new_pipe = function(ipc)
            new_pipe_arg = ipc
            return {
                bind2 = function()
                    return 0
                end,
                is_closing = function()
                    return pipe_closed
                end,
                close = function()
                    pipe_closed = true
                end,
            }
        end

        local ok, err = xpcall(function()
            plugin.setup({ transport = 'socket' })

            assert.are.same({ 'socket' }, start_calls)
            assert.is_false(new_pipe_arg)
            assert.is_true(pipe_closed)
        end, debug.traceback)

        vim.uv.new_pipe = original_new_pipe
        server.start = original_start

        if not ok then
            error(err)
        end
    end)

    it('skips socket startup during setup when bind2 is unavailable', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local start_calls = {}
        local original_start = server.start
        local original_new_pipe = vim.uv.new_pipe
        local new_pipe_arg

        server.start = function(transport)
            table.insert(start_calls, transport)
            return true, nil
        end

        vim.uv.new_pipe = function(ipc)
            new_pipe_arg = ipc
            return {
                close = function() end,
            }
        end

        local ok, err = xpcall(function()
            plugin.setup({ transport = 'socket' })

            assert.are.same({}, start_calls)
            assert.is_false(new_pipe_arg)
        end, debug.traceback)

        vim.uv.new_pipe = original_new_pipe
        server.start = original_start

        if not ok then
            error(err)
        end
    end)

    it('skips socket startup during setup when socket probing is unavailable', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local start_calls = {}
        local original_start = server.start
        local original_new_pipe = vim.uv.new_pipe
        local new_pipe_arg

        server.start = function(transport)
            table.insert(start_calls, transport)
            return true, nil
        end

        vim.uv.new_pipe = function(ipc)
            new_pipe_arg = ipc
            return nil
        end

        local ok, err = xpcall(function()
            plugin.setup({ transport = 'socket' })

            assert.are.same({}, start_calls)
            assert.is_false(new_pipe_arg)
        end, debug.traceback)

        vim.uv.new_pipe = original_new_pipe
        server.start = original_start

        if not ok then
            error(err)
        end
    end)

    it('does not auto-start transports during setup when auto_start is false', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local start_calls = {}
        local http_start_calls = 0
        local original_start = server.start
        local original_start_http = server.start_http

        server.start = function(transport)
            table.insert(start_calls, transport)
            return true, nil
        end

        server.start_http = function()
            http_start_calls = http_start_calls + 1
            return true, nil
        end

        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                auto_start = false,
                http_host = '127.0.0.1',
                http_port = 8877,
            })

            assert.are.same({}, start_calls)
            assert.are.equal(0, http_start_calls)
        end, debug.traceback)

        server.start_http = original_start_http
        server.start = original_start

        if not ok then
            error(err)
        end
    end)

    it('uses the configured transport for default start and endpoint invocation', function()
        local plugin = require('mcp')
        local server = require('mcp.server')
        local start_calls = {}
        local original_start = server.start

        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 8877,
        })

        server.start = function(transport)
            table.insert(start_calls, transport)
            return true, nil
        end

        local ok, err = xpcall(function()
            local start_ok, start_err = plugin.start()
            local invocation = plugin.endpoint_invocation()

            assert.is_true(start_ok)
            assert.is_nil(start_err)
            assert.are.same({ 'http' }, start_calls)
            assert.are.same({ url = 'http://127.0.0.1:8877/mcp' }, invocation)
        end, debug.traceback)

        server.start = original_start

        if not ok then
            error(err)
        end
    end)

    it('reports the bound HTTP endpoint after setup starts an ephemeral server', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')

        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 0,
        })

        local ok, err = xpcall(function()
            local host, port = http_server.bound_address()
            local endpoint = plugin.endpoint()

            assert.are.equal('127.0.0.1', host)
            assert.is_true(type(port) == 'number' and port > 0)
            assert.are.equal('http', endpoint.transport)
            assert.are.equal(port, endpoint.http_port)
            assert.are.equal(string.format('http://127.0.0.1:%d/mcp', port), endpoint.url)
        end, debug.traceback)

        plugin.reset()

        if not ok then
            error(err)
        end
    end)

    it('exposes the active HTTP endpoint after start', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')

        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 0,
        })

        local ok, err = xpcall(function()
            local started, start_err = plugin.start('http')
            local endpoint = plugin.http_endpoint()
            local host, port = http_server.bound_address()

            assert.is_true(started)
            assert.is_nil(start_err)
            assert.are.equal('127.0.0.1', host)
            assert.is_true(type(port) == 'number' and port > 0)
            assert.are.equal('http', endpoint.transport)
            assert.are.equal(string.format('http://127.0.0.1:%d/mcp', port), endpoint.url)
            assert.are.equal(port, endpoint.http_port)
        end, debug.traceback)

        plugin.reset()

        if not ok then
            error(err)
        end
    end)

    it('stops the HTTP server during reset', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')

        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 0,
        })

        local started, start_err = plugin.start('http')
        assert.is_true(started)
        assert.is_nil(start_err)
        assert.is_not_nil(plugin.http_endpoint())

        plugin.reset()

        assert.is_nil(plugin.http_endpoint())
        local host, port = http_server.bound_address()
        assert.is_nil(host)
        assert.is_nil(port)
    end)

    it('validates resources during server registration', function()
        local plugin = require('mcp')

        local ok, err = pcall(function()
            plugin.register_server({
                name = 'editor',
                resources = {
                    {
                        uri = 'buffer://current',
                        handler = 'oops',
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.matches('mcp resource handler must be a function', tostring(err), 1, true)
    end)

    it('validates resource templates during server registration', function()
        local plugin = require('mcp')

        local ok, err = pcall(function()
            plugin.register_server({
                name = 'editor',
                resource_templates = {
                    {
                        name = 'buffer',
                        uri_template = 'buffer://{bufnr}',
                        handler = 'oops',
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.matches('mcp resource template handler must be a function', tostring(err), 1, true)
    end)

    it('validates prompts during server registration', function()
        local plugin = require('mcp')

        local ok, err = pcall(function()
            plugin.register_server({
                name = 'editor',
                prompts = {
                    {
                        name = 'summarize',
                        handler = 'oops',
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.matches('mcp prompt handler must be a function', tostring(err), 1, true)
    end)

    it('waits for the full HTTP request body before decoding', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local request = vim.json.encode({
            jsonrpc = '2.0',
            id = 7,
            method = 'initialize',
            params = {
                protocolVersion = '2025-06-18',
            },
        })
        local headers = table.concat({
            'POST /mcp HTTP/1.1',
            'Host: 127.0.0.1',
            'Content-Type: application/json',
            string.format('Content-Length: %d', #request),
            '',
            '',
        }, '\r\n')
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(nil, headers)
        assert.are.equal(0, #writes)
        callback(nil, request:sub(1, 12))
        assert.are.equal(0, #writes)
        callback(nil, request:sub(13))
        vim.wait(1000, function()
            return #writes == 1
        end)

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"protocolVersion":"2025-06-18"', 1, true) ~= nil)
    end)

    it('waits for the full HTTP request body when Content-Length is measured in bytes', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local request = vim.json.encode({
            jsonrpc = '2.0',
            id = 8,
            method = 'ping',
            params = {
                message = 'żółw',
            },
        })
        local byte_length = #request
        local char_length = vim.fn.strchars(request)
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        assert.is_true(byte_length > char_length)

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', byte_length),
                '',
                '',
            }, '\r\n')
        )
        callback(nil, request:sub(1, char_length))
        assert.are.equal(0, #writes)
        callback(nil, request:sub(char_length + 1))
        vim.wait(1000, function()
            return #writes == 1
        end)

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
    end)

    it('waits for exact Content-Length bytes before parsing a pipelined request', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body1 = vim.json.encode({
            jsonrpc = '2.0',
            id = 1,
            method = 'ping',
            params = {
                message = 'line1\n',
            },
        })
        local body2 = '{"jsonrpc":"2.0","id":2,"method":"ping"}'
        local headers1 = table.concat({
            'POST /mcp HTTP/1.1',
            'Host: 127.0.0.1',
            'Content-Type: application/json',
            string.format('Content-Length: %d', #body1),
            '',
            '',
        }, '\r\n')
        local request2 = table.concat({
            'POST /mcp HTTP/1.1',
            'Host: 127.0.0.1',
            'Content-Type: application/json',
            string.format('Content-Length: %d', #body2),
            '',
            body2,
        }, '\r\n')
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(nil, headers1 .. body1:sub(1, -2))

        assert.are.equal(0, #writes)

        callback(nil, body1:sub(-1) .. request2)
        vim.wait(1000, function()
            return #writes == 2
        end)

        assert.are.equal(2, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"id":1', 1, true) ~= nil)
        assert.truthy(writes[2]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[2]:find('"id":2', 1, true) ~= nil)
    end)

    it('consumes the full request body before parsing the next pipelined request', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body1 = '{"jsonrpc":"2.0","id":1,"method":"ping"}'
        local body2 = '{"jsonrpc":"2.0","id":2,"method":"ping"}'
        local request = function(body)
            return table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        end
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(nil, request(body1) .. request(body2))

        vim.wait(1000, function()
            return #writes == 2
        end)

        assert.are.equal(2, #writes)
        assert.truthy(writes[1]:find('"id":1', 1, true) ~= nil)
        assert.truthy(writes[2]:find('"id":2', 1, true) ~= nil)
    end)

    it('preserves additional pipelined requests buffered before scheduled dispatch resumes', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body1 = '{"jsonrpc":"2.0","id":1,"method":"ping"}'
        local body2 = '{"jsonrpc":"2.0","id":2,"method":"ping"}'
        local body3 = '{"jsonrpc":"2.0","id":3,"method":"ping"}'
        local request = function(body)
            return table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        end
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(nil, request(body1) .. '\r\n' .. request(body2) .. '\r\n' .. request(body3))

        assert.are.equal(3, #writes)
        assert.truthy(writes[1]:find('"id":1', 1, true) ~= nil)
        assert.truthy(writes[2]:find('"id":2', 1, true) ~= nil)
        assert.truthy(writes[3]:find('"id":3', 1, true) ~= nil)
    end)

    it('accepts JSON-RPC batch requests', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = vim.json.encode({
            {
                jsonrpc = '2.0',
                id = 1,
                method = 'ping',
            },
            {
                jsonrpc = '2.0',
                id = 2,
                method = 'ping',
            },
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"id":1', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"id":2', 1, true) ~= nil)
    end)

    it('omits notification entries from JSON-RPC batch responses', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = vim.json.encode({
            {
                jsonrpc = '2.0',
                method = 'ping',
            },
            {
                jsonrpc = '2.0',
                id = 2,
                method = 'ping',
            },
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"id":2', 1, true) ~= nil)
        assert.falsy(writes[1]:find('"id":null', 1, true) ~= nil)
    end)

    it('returns 204 No Content for JSON-RPC notifications over HTTP', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","method":"ping"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Content-Length:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Connection: keep-alive', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Methods: POST, OPTIONS', 1, true) ~= nil)
    end)

    it('omits Content-Length for direct 204 responses', function()
        local send_response = require('mcp.http_server')._send_response
        local writes = {}
        local client = {
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
        }

        send_response(client, 204, '', {}, true, 'HTTP/1.1')

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Content-Length:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Connection: keep-alive', 1, true) ~= nil)
        assert.are.equal('HTTP/1.1 204 No Content\r\nConnection: keep-alive\r\n\r\n', writes[1])
    end)

    it('drops response bodies for direct 204 responses', function()
        local send_response = require('mcp.http_server')._send_response
        local writes = {}
        local client = {
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
        }

        send_response(client, 204, 'ignored body', {}, true, 'HTTP/1.1')

        assert.are.equal(1, #writes)
        assert.are.equal('HTTP/1.1 204 No Content\r\nConnection: keep-alive\r\n\r\n', writes[1])
    end)

    it('returns 204 No Content for notification-only JSON-RPC batches over HTTP', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = vim.json.encode({
            {
                jsonrpc = '2.0',
                method = 'ping',
            },
            {
                jsonrpc = '2.0',
                method = 'ping',
            },
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Content-Length:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Connection: keep-alive', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Methods: POST, OPTIONS', 1, true) ~= nil)
    end)

    it('rejects OPTIONS /mcp when the Accept header is unsupported', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'OPTIONS /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: text/plain',
                'Content-Length: 0',
                '',
                '',
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 406 Not Acceptable', 1, true) ~= nil)
        assert.truthy(writes[1]:find('unsupported accept header', 1, true) ~= nil)
    end)

    it('responds to OPTIONS /mcp preflight requests with CORS headers', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local origin = 'https://example.com'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'OPTIONS /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Origin: ' .. origin,
                'Access-Control-Request-Method: POST',
                'Accept: application/json',
                'Content-Length: 0',
                '',
                '',
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Content-Type: application/json', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Methods: POST, OPTIONS', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Headers: Content%-Type, Accept') ~= nil)
    end)

    it('does not reflect non-local origins on successful MCP responses', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local origin = 'https://example.com'
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 9,
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Origin: ' .. origin,
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. origin, 1, true) ~= nil)
        assert.truthy(writes[1]:find('Vary: Origin', 1, true) ~= nil)
    end)


    it('allows localhost origins only for loopback hosts', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local origin = 'http://[::1]:3000'
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 9,
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Origin: ' .. origin,
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. origin, 1, true) ~= nil)
    end)



    it('reflects localhost origins for loopback IPv4 listeners', function()
        local http_server = require('mcp.http_server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 111,
            method = 'ping',
        })
        local writes = {}
        local callback
        local origin = 'http://localhost:3000'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Origin: ' .. origin,
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. origin, 1, true) ~= nil)
        assert.truthy(writes[1]:find('Vary: Origin', 1, true) ~= nil)
    end)

    it('reflects localhost origins for loopback IPv6 listeners', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 112,
            method = 'ping',
        })
        local writes = {}
        local callback
        local origin = 'http://localhost:3000'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        plugin.setup({
            transport = {
                type = 'http',
                http = {
                    host = '::1',
                    port = 0,
                },
            },
        })

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: [::1]',
                'Origin: ' .. origin,
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. origin, 1, true) ~= nil)
        assert.truthy(writes[1]:find('Vary: Origin', 1, true) ~= nil)
    end)

    it('allows localhost hostname origins without a port', function()
        local http_server = require('mcp.http_server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 11,
            method = 'ping',
        })
        local writes = {}
        local callback
        local origin = 'https://localhost'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Origin: ' .. origin,
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. origin, 1, true) ~= nil)
        assert.truthy(writes[1]:find('Vary: Origin', 1, true) ~= nil)
    end)

    it('allows loopback origins beyond hard-coded localhost literals', function()
        local http_server = require('mcp.http_server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 12,
            method = 'ping',
        })
        local cases = {
            {
                host = '127.0.0.2',
                origin = 'https://localhost:3000',
            },
            {
                host = '127.0.0.2',
                origin = 'https://127.0.0.2:3000',
            },
            {
                host = '[::1]',
                origin = 'http://[::ffff:127.0.0.2]:3000',
            },
            {
                host = '[::1]',
                origin = 'http://[::ffff:7f00:2]:3000',
            },
            {
                host = '127.0.0.2',
                origin = 'http://[::ffff:127.0.0.2]:3000',
            },
            {
                host = '127.0.0.2',
                origin = 'http://[::ffff:7f00:2]:3000',
            },
        }

        for _, case in ipairs(cases) do
            local writes = {}
            local callback
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            http_server._start_client_read(client)
            callback(
                nil,
                table.concat({
                    'POST /mcp HTTP/1.1',
                    'Host: ' .. case.host,
                    'Origin: ' .. case.origin,
                    'Content-Type: application/json',
                    string.format('Content-Length: %d', #body),
                    '',
                    body,
                }, '\r\n')
            )

            assert.are.equal(1, #writes)
            assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
            assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. case.origin, 1, true) ~= nil)
        end
    end)

    it('reflects origins that match the configured non-loopback host', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 13,
            method = 'ping',
        })
        local writes = {}
        local callback
        local origin = 'http://example.com:3000'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        plugin.setup({
            transport = {
                type = 'http',
                http = {
                    host = 'example.com',
                    port = 0,
                },
            },
        })

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: example.com',
                'Origin: ' .. origin,
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. origin, 1, true) ~= nil)
    end)

    it('reflects origins that match a configured IPv6 host', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 14,
            method = 'ping',
        })
        local writes = {}
        local callback
        local origin = 'http://[::1]:3000'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        plugin.setup({
            transport = {
                type = 'http',
                http = {
                    host = '::1',
                    port = 0,
                },
            },
        })

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: [::1]',
                'Origin: ' .. origin,
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. origin, 1, true) ~= nil)
    end)

    it('does not emit allow-origin for invalid Origin header values', function()
        local http_server = require('mcp.http_server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 10,
            method = 'ping',
        })

        local function request_with_origin(origin)
            local writes = {}
            local callback
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            http_server._start_client_read(client)
            callback(
                nil,
                table.concat({
                    'POST /mcp HTTP/1.1',
                    'Host: 127.0.0.1',
                    'Origin: ' .. origin,
                    'Content-Type: application/json',
                    string.format('Content-Length: %d', #body),
                    '',
                    body,
                }, '\r\n')
            )

            assert.are.equal(1, #writes)
            assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
            assert.falsy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) ~= nil)
            assert.falsy(writes[1]:find('Vary: Origin', 1, true) ~= nil)
        end

        for _, origin in ipairs({
            'null',
            '   ',
            'garbage',
            'https://example.com/path',
            'file://foo',
            'chrome-extension://extension-id',
            'https://[not-an-ipv6]',
            'https://[]',
            'https://[:::]',
            'https://[:]:443',
            'https://[....]:443',
            'https://[::ffff:999.1.1.1]:443',
            'https://[2001:db8:192.168.0.1]:443',
            'https://[127.0.0.1]',
            'https://example.com:',
            'https://[::1]:',
            'http://foo:bar:80',
            'https://foo:bar:443',
            'http://example.com',
        }) do
            request_with_origin(origin)
        end
    end)

    it('rejects empty JSON-RPC batches as invalid requests', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '[]'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"code":-32600', 1, true) ~= nil)
    end)

    it('accepts wildcard application accept headers', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"ping"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/*',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
    end)

    it('accepts text/event-stream accept headers for MCP compatibility', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: text/event-stream',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content-Type: application/json', 1, true) ~= nil)
    end)

    it('ignores optional text/event-stream when json is also accepted', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/json, text/event-stream',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content-Type: application/json', 1, true) ~= nil)
    end)

    it('rejects application/json when a more specific accept range sets q=0', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/json;q=0, */*',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 406 Not Acceptable', 1, true) ~= nil)
    end)

    it('prefers the highest ranked supported response content type', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/json;q=0.1, application/jsonrpc;q=1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/jsonrpc', 1) ~= nil)
    end)

    it('prefers q over specificity when choosing between response content types', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/json;q=1, application/jsonrpc;q=0.1, application/*+json;q=0.5',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/json\r\n', 1) ~= nil)
    end)

    it('prefers a more specific accept match over a higher-q wildcard for the same candidate', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/*;q=1, application/jsonrpc;q=0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/jsonrpc', 1) ~= nil)
    end)

    it('prefers the most specific accept match before header order', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/*;q=1, application/jsonrpc;q=1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/jsonrpc\r\n', 1) ~= nil)
    end)

    it('accepts wildcard fallback when a specific accept entry has q=0', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/json;q=0, */*;q=1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/json\r\n', 1) ~= nil)
    end)

    it('prefers more specific accept entries over higher q wildcards', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/*;q=1, application/json;q=0.5',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/json\r\n', 1) ~= nil)
    end)

    it('preserves accept header order for equally ranked content types', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/json, application/jsonrpc',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/json\r\n', 1) ~= nil)
    end)

    it('accepts structured +json media ranges for JSON responses', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/vnd.api+json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/json\r\n', 1) ~= nil)
    end)


    it('rejects folded headers as malformed requests', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Length: 47',
                ' 47',
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
        assert.truthy(writes[1]:find('invalid folded header', 1, true) ~= nil)
    end)

    it('rejects non-decimal content-length values', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Length: 1e3',
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
    end)

    it('accepts identical duplicate content-length headers', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
    end)

    it('rejects conflicting duplicate content-length headers', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                string.format('Content-Length: %d', #body + 1),
                '',
                '',
            }, '\r\n')
        )
        assert.are.equal(0, #writes)
        callback(nil, body)

        vim.wait(1000, function()
            return #writes >= 1
        end)
        assert.truthy(#writes >= 1)
        local response = table.concat(writes)
        assert.truthy(response:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
        assert.truthy(response:find('ambiguous content%-length', 1) ~= nil)
    end)


    it('rejects requests that use bare LF header framing', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
        assert.truthy(writes[1]:find('invalid http framing', 1, true) ~= nil)
    end)

    it('rejects duplicate content-type headers', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                'Content-Type: application/jsonrpc',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
        assert.truthy(writes[1]:find('duplicate content%-type', 1) ~= nil)
    end)

    it('combines repeated accept headers before content negotiation', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                'Accept: text/plain',
                'Accept: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content%-Type: application/json\r\n', 1) ~= nil)
    end)

    it('combines repeated connection headers when deciding keep-alive', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local closed = false
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function()
                closed = true
            end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Connection: keep-alive',
                'Connection: close',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        vim.wait(1000, function()
            return #writes == 1
        end)
        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('Connection: close', 1, true) ~= nil)
        assert.is_true(closed)
    end)

    it('responds to malformed HTTP/1.0 requests with the matching protocol version', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.0',
                'Host: 127.0.0.1',
                'Content-Length: 1e3',
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.0 400 Bad Request', 1, true) ~= nil)
    end)

    it('uses the standard reason phrase for HTTP 505 responses', function()
        local http_server = require('mcp.http_server')

        local function make_client()
            local writes = {}
            local callback
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            http_server._start_client_read(client)
            return writes, function(err, chunk)
                callback(err, chunk)
            end
        end

        local parser_writes, parser_callback = make_client()
        parser_callback(
            nil,
            table.concat({
                'POST /mcp HTTP/2.0',
                'Host: 127.0.0.1',
                'Content-Length: 0',
                '',
                '',
            }, '\r\n')
        )

        assert.are.equal(1, #parser_writes)
        assert.truthy(parser_writes[1]:find('HTTP/1.1 505 HTTP Version Not Supported', 1, true) ~= nil)
        assert.truthy(parser_writes[1]:find('Content-Type: application/json', 1, true) ~= nil)

        local request_writes, request_callback = make_client()
        request_callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: application/json, text/event-stream',
                'Content-Type: application/json',
                'MCP-Protocol-Version: 2025-03-26',
                'Content-Length: 0',
                '',
                '',
            }, '\r\n')
        )
        request_callback(
            nil,
            table.concat({
                'POST /mcp HTTP/2.0',
                'Host: 127.0.0.1',
                'Content-Length: 0',
                '',
                '',
            }, '\r\n')
        )

        assert.are.equal(2, #request_writes)
        assert.truthy(request_writes[2]:find('HTTP/1.1 505 HTTP Version Not Supported', 1, true) ~= nil)
        assert.truthy(request_writes[2]:find('Content-Type: application/json', 1, true) ~= nil)
    end)

    it('rejects transfer-encoding request framing', function()
        local http_server = require('mcp.http_server')

        local function run(lines)
            local writes = {}
            local callback
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            http_server._start_client_read(client)
            callback(nil, table.concat(lines, '\r\n'))
            return writes[1]
        end

        local transfer_encoding_only = run({
            'POST /mcp HTTP/1.1',
            'Host: 127.0.0.1',
            'Transfer-Encoding: chunked',
            '',
            '',
        })

        local both_headers = run({
            'POST /mcp HTTP/1.1',
            'Host: 127.0.0.1',
            'Transfer-Encoding: chunked',
            'Content-Length: 0',
            '',
            '',
        })

        assert.truthy(transfer_encoding_only:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
        assert.truthy(transfer_encoding_only:find('unsupported transfer-encoding', 1, true) ~= nil)
        assert.truthy(both_headers:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
        assert.truthy(both_headers:find('unsupported transfer-encoding', 1, true) ~= nil)
    end)

    it('accepts any media type with */* accept headers', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"ping"}'
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Accept: */*',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
    end)

    it('returns correct HTTP errors for invalid method and route', function()
        local http_server = require('mcp.http_server')

        local function run(raw)
            local writes = {}
            local callback
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            http_server._start_client_read(client)
            callback(nil, raw)
            return writes[1]
        end

        local method_response = run(table.concat({
            'GET /mcp HTTP/1.1',
            'Host: 127.0.0.1',
            'Content-Type: application/json',
            'Content-Length: 0',
            '',
            '',
        }, '\r\n'))
        local route_response = run(table.concat({
            'POST /missing HTTP/1.1',
            'Host: 127.0.0.1',
            'Content-Type: application/json',
            'Content-Length: 0',
            '',
            '',
        }, '\r\n'))

        assert.truthy(method_response:find('HTTP/1.1 405 Method Not Allowed', 1, true) ~= nil)
        assert.truthy(route_response:find('HTTP/1.1 404 Not Found', 1, true) ~= nil)
    end)

    it('accepts application/jsonrpc request bodies', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 9,
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/jsonrpc',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
    end)

    it('allows only supported JSON request content types', function()
        local http_server = require('mcp.http_server')

        local function run(content_type)
            local writes = {}
            local callback
            local body = vim.json.encode({
                jsonrpc = '2.0',
                id = 9,
                method = 'ping',
            })
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            http_server._start_client_read(client)
            callback(
                nil,
                table.concat({
                    'POST /mcp HTTP/1.1',
                    'Host: 127.0.0.1',
                    'Content-Type: ' .. content_type,
                    string.format('Content-Length: %d', #body),
                    '',
                    body,
                }, '\r\n')
            )

            assert.are.equal(1, #writes)
            return writes[1]
        end

        local application_json = run('application/json')
        local application_json_with_charset = run('application/json; charset=utf-8')
        local application_json_with_whitespace_charset = run('application/json ; charset=utf-8')
        local application_jsonrpc = run('application/jsonrpc')
        local application_jsonrpc_with_charset = run('application/jsonrpc; charset=utf-8')
        local structured_json = run('application/vnd.api+json')
        local non_json = run('application/vnd.api+xml')

        assert.truthy(application_json:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(application_json_with_charset:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(application_json_with_whitespace_charset:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(application_jsonrpc:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(application_jsonrpc_with_charset:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(structured_json:find('HTTP/1.1 415 Unsupported Media Type', 1, true) ~= nil)
        assert.truthy(structured_json:find('"error":"unsupported content type"', 1, true) ~= nil)
        assert.truthy(non_json:find('HTTP/1.1 415 Unsupported Media Type', 1, true) ~= nil)
        assert.truthy(non_json:find('"error":"unsupported content type"', 1, true) ~= nil)
    end)

    it('rejects JSON POST requests without a Content-Type header', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 9,
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 415 Unsupported Media Type', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"error":"unsupported content type"', 1, true) ~= nil)
    end)

    it('rejects JSON-RPC requests with non-table params', function()
        local http_server = require('mcp.http_server')

        local function run(params)
            local writes = {}
            local callback
            local body = vim.json.encode({
                jsonrpc = '2.0',
                id = 10,
                method = 'ping',
                params = params,
            })
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            http_server._start_client_read(client)
            callback(
                nil,
                table.concat({
                    'POST /mcp HTTP/1.1',
                    'Host: 127.0.0.1',
                    'Content-Type: application/json',
                    string.format('Content-Length: %d', #body),
                    '',
                    body,
                }, '\r\n')
            )

            return writes[1]
        end

        local invalid_string = run('bad')
        local invalid_boolean = run(true)

        assert.truthy(invalid_string:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(invalid_string:find('"code":-32600', 1, true) ~= nil)
        assert.truthy(invalid_boolean:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(invalid_boolean:find('"code":-32600', 1, true) ~= nil)
    end)

    it('returns HTTP 200 with JSON-RPC error bodies for JSON-RPC failures', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')

        plugin.setup()

        local function run(payload)
            local writes = {}
            local callback
            local client = {
                read_start = function(_, cb)
                    callback = cb
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
                write = function(_, response, cb)
                    table.insert(writes, response)
                    if cb ~= nil then
                        cb()
                    end
                end,
            }

            local body = vim.json.encode(payload)
            http_server._start_client_read(client)
            callback(
                nil,
                table.concat({
                    'POST /mcp HTTP/1.1',
                    'Host: 127.0.0.1',
                    'Content-Type: application/json',
                    string.format('Content-Length: %d', #body),
                    '',
                    body,
                }, '\r\n')
            )

            return writes[1]
        end

        local not_found = run({
            jsonrpc = '2.0',
            id = 1,
            method = 'missing/method',
        })
        local invalid_params = run({
            jsonrpc = '2.0',
            id = 2,
            method = 'tools/call',
            params = {
                name = 'neovim/editor/list_buffers',
                arguments = 'bad',
            },
        })
        local custom_error = run({
            jsonrpc = '2.0',
            id = 3,
            method = 'tools/call',
            params = {
                name = 'neovim/editor/read_buffer',
                arguments = {
                    bufnr = -1,
                },
            },
        })

        assert.truthy(not_found:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(not_found:find('"code":-32601', 1, true) ~= nil)
        assert.truthy(invalid_params:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(invalid_params:find('"code":-32602', 1, true) ~= nil)
        assert.truthy(custom_error:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(custom_error:find('"code":-32000', 1, true) ~= nil)
    end)

    it('requires Content-Length for HTTP request bodies', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local stopped = false
        local closed = false
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function()
                stopped = true
            end,
            close = function()
                closed = true
            end,
            is_closing = function()
                return closed
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                '',
                '{"jsonrpc":"2.0","id":1,"method":"ping"}',
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 400 Bad Request', 1, true) ~= nil)
        assert.truthy(writes[1]:find('missing content%-length') ~= nil)
        assert.is_true(stopped)
        assert.is_true(closed)
    end)

    it('accepts LF-only HTTP requests', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 9,
            method = 'ping',
            params = {},
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function() end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\n')
        )

        vim.wait(1000, function()
            return #writes == 1
        end)

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"jsonrpc":"2.0"', 1, true) ~= nil)
    end)

    it('rejects non-string HTTP response bodies explicitly', function()
        local send_response = require('mcp.http_server')._send_response
        local client = {
            write = function() end,
        }

        assert.has_error(function()
            send_response(client, 200, {}, nil, false, 'HTTP/1.1')
        end, 'http response body must be a string')
    end)

    it('accepts bodyless HTTP requests without Content-Length', function()
        local http_server = require('mcp.http_server')
        local endpoint = require('mcp.endpoint')
        local original_handle = endpoint.handle
        local writes = {}
        local callback
        local stopped = false
        local closed = false

        endpoint.handle = function(decoded)
            return {
                jsonrpc = '2.0',
                id = decoded.id,
                result = {
                    ok = true,
                },
            }
        end

        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function()
                stopped = true
            end,
            close = function()
                closed = true
            end,
            is_closing = function()
                return closed
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'GET /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                '',
                '',
            }, '\r\n')
        )

        endpoint.handle = original_handle

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"ok":true', 1, true) ~= nil)
        assert.falsy(writes[1]:find('missing content%-length') ~= nil)
        assert.is_true(stopped)
        assert.is_true(closed)
    end)

    it('notifies on HTTP accept failure', function()
        local http_server = require('mcp.http_server')
        local endpoint = require('mcp.endpoint')
        local original_new_tcp = vim.uv.new_tcp
        local original_notify = vim.notify
        local original_describe = endpoint.describe
        local listener_cb
        local notify_messages = {}
        local listener_closed = false
        local first_tcp = true

        endpoint.describe = function()
            return {
                http_host = '127.0.0.1',
                http_port = 8123,
            }
        end

        vim.notify = function(message)
            table.insert(notify_messages, message)
        end

        vim.uv.new_tcp = function()
            if first_tcp then
                first_tcp = false
                return {
                    bind = function()
                        return 0
                    end,
                    listen = function(_, _, cb)
                        listener_cb = cb
                        return true
                    end,
                    accept = function()
                        return 1, 'accept failed'
                    end,
                    is_closing = function()
                        return listener_closed
                    end,
                    close = function()
                        listener_closed = true
                    end,
                }
            end

            return {
                is_closing = function()
                    return false
                end,
                close = function() end,
            }
        end

        local ok, err = pcall(function()
            local started, start_err = http_server.start()
            assert.is_true(started)
            assert.is_nil(start_err)

            listener_cb(nil)
            vim.wait(1000, function()
                return #notify_messages > 0
            end)

            assert.is_true(notify_messages[1]:find('mcp http accept error: accept failed', 1, true) ~= nil)
        end)

        http_server.stop()
        vim.uv.new_tcp = original_new_tcp
        vim.notify = original_notify
        endpoint.describe = original_describe

        if not ok then
            error(err)
        end
    end)

    it('implements identifier-based editor tools and real terminal tools', function()
        local plugin = require('mcp')
        plugin.setup({ enable_terminal_tools = true })

        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'before' })
        local current_bufnr = vim.api.nvim_get_current_buf()
        local listed = plugin.call_tool('neovim/editor/list_buffers', {}, {})
        local read_by_id, read_err_by_id = plugin.call_tool('neovim/editor/read_buffer', {
            bufnr = current_bufnr,
        }, {})
        local diff_by_id, diff_err_by_id = plugin.call_tool('neovim/editor/diff_buffer', {
            bufnr = current_bufnr,
            content = 'after\nvalue\n',
        }, {})
        local write_by_id, write_err_by_id = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = current_bufnr,
            content = 'after\nvalue\n',
        }, {})

        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_buffer', {
            bufnr = current_bufnr,
            content = 'after\nvalue\n',
        }, {})

        local terminal_result, terminal_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'printf', 'hello' },
        }, {})
        assert.is_nil(terminal_err)
        assert.is_not_nil(terminal_result)
        local wait_result, wait_err = plugin.call_tool('neovim/terminal/wait', {
            terminal_id = terminal_result.terminal_id,
        }, {})
        local output_result, output_err = plugin.call_tool('neovim/terminal/output', {
            terminal_id = terminal_result.terminal_id,
        }, {})
        local release_result, release_err = plugin.call_tool('neovim/terminal/release', {
            terminal_id = terminal_result.terminal_id,
        }, {})

        assert.is_true(#listed.buffers >= 1)
        assert.is_nil(read_err_by_id)
        assert.is_table(read_by_id)
        assert.are.equal(current_bufnr, read_by_id.bufnr)
        assert.is_nil(diff_err_by_id)
        assert.is_true(#diff_by_id.hunks >= 1)
        assert.is_nil(write_err_by_id)
        assert.is_true(write_by_id.modified)
        assert.is_nil(apply_err)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.is_true(apply_result.modified)
        assert.is_nil(terminal_err)
        assert.is_not_nil(terminal_result.terminal_id)
        assert.is_nil(wait_err)
        assert.are.equal(0, wait_result.exit_code)
        assert.is_nil(output_err)
        assert.is_true(output_result.stdout:find('hello', 1, true) ~= nil)
        assert.is_nil(release_err)
        assert.is_true(release_result.released)
    end)

    it('returns structured errors for identifier-based editor tool invalid arguments and invalid buffers', function()
        local plugin = require('mcp')
        plugin.setup()

        local current_bufnr = vim.api.nvim_get_current_buf()
        local invalid_bufnr = current_bufnr + 9999

        local read_missing_result, read_missing_err = plugin.call_tool('neovim/editor/read_buffer', {}, {})
        local read_invalid_result, read_invalid_err = plugin.call_tool('neovim/editor/read_buffer', {
            bufnr = 'nope',
        }, {})
        local read_missing_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/read_buffer',
            arguments = {},
        }, 201, {})
        local read_invalid_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/read_buffer',
            arguments = {
                bufnr = 'nope',
            },
        }, 202, {})
        local read_invalid_buffer_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/read_buffer',
            arguments = {
                bufnr = invalid_bufnr,
            },
        }, 203, {})
        local read_invalid_buffer_result, read_invalid_buffer_err = plugin.call_tool('neovim/editor/read_buffer', {
            bufnr = invalid_bufnr,
        }, {})

        local diff_missing_bufnr_result, diff_missing_bufnr_err = plugin.call_tool('neovim/editor/diff_buffer', {
            content = 'after\n',
        }, {})
        local diff_invalid_bufnr_result, diff_invalid_bufnr_err = plugin.call_tool('neovim/editor/diff_buffer', {
            bufnr = 'nope',
            content = 'after\n',
        }, {})
        local diff_missing_bufnr_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_buffer',
            arguments = {
                content = 'after\n',
            },
        }, 204, {})
        local diff_invalid_bufnr_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_buffer',
            arguments = {
                bufnr = 'nope',
                content = 'after\n',
            },
        }, 205, {})
        local diff_invalid_buffer_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_buffer',
            arguments = {
                bufnr = invalid_bufnr,
                content = 'after\n',
            },
        }, 206, {})
        local diff_invalid_buffer_result, diff_invalid_buffer_err = plugin.call_tool('neovim/editor/diff_buffer', {
            bufnr = invalid_bufnr,
            content = 'after\n',
        }, {})

        local write_missing_bufnr_result, write_missing_bufnr_err = plugin.call_tool('neovim/editor/write_buffer', {
            content = 'after\n',
        }, {})
        local write_invalid_bufnr_result, write_invalid_bufnr_err = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = 'nope',
            content = 'after\n',
        }, {})
        local write_missing_bufnr_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/write_buffer',
            arguments = {
                content = 'after\n',
            },
        }, 207, {})
        local write_invalid_bufnr_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/write_buffer',
            arguments = {
                bufnr = 'nope',
                content = 'after\n',
            },
        }, 208, {})
        local write_invalid_buffer_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/write_buffer',
            arguments = {
                bufnr = invalid_bufnr,
                content = 'after\n',
            },
        }, 209, {})
        local write_invalid_content_result, write_invalid_content_err = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = current_bufnr,
            content = false,
        }, {})
        local write_invalid_buffer_result, write_invalid_buffer_err = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = invalid_bufnr,
            content = 'after\n',
        }, {})

        local apply_missing_bufnr_result, apply_missing_bufnr_err = plugin.call_tool(
            'neovim/editor/apply_diff_buffer',
            {
                content = 'after\n',
            },
            {}
        )
        local apply_invalid_bufnr_result, apply_invalid_bufnr_err = plugin.call_tool(
            'neovim/editor/apply_diff_buffer',
            {
                bufnr = 'nope',
                content = 'after\n',
            },
            {}
        )
        local apply_missing_bufnr_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_buffer',
            arguments = {
                content = 'after\n',
            },
        }, 210, {})
        local apply_invalid_bufnr_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_buffer',
            arguments = {
                bufnr = 'nope',
                content = 'after\n',
            },
        }, 211, {})
        local apply_invalid_buffer_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_buffer',
            arguments = {
                bufnr = invalid_bufnr,
                content = 'after\n',
            },
        }, 212, {})
        local apply_invalid_content_result, apply_invalid_content_err = plugin.call_tool(
            'neovim/editor/apply_diff_buffer',
            {
                bufnr = current_bufnr,
                content = false,
            },
            {}
        )
        local apply_invalid_buffer_result, apply_invalid_buffer_err = plugin.call_tool(
            'neovim/editor/apply_diff_buffer',
            {
                bufnr = invalid_bufnr,
                content = 'after\n',
            },
            {}
        )

        assert.is_nil(read_missing_result)
        assert.are.equal(-32602, read_missing_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', read_missing_err.message)
        assert.is_nil(read_invalid_result)
        assert.are.equal(-32602, read_invalid_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', read_invalid_err.message)
        assert.are.equal(-32602, read_missing_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', read_missing_router.error.message)
        assert.are.equal(-32602, read_invalid_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', read_invalid_router.error.message)
        assert.are.equal(-32000, read_invalid_buffer_router.error.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            read_invalid_buffer_router.error.message
        )
        assert.is_nil(read_invalid_buffer_result)
        assert.are.equal(-32000, read_invalid_buffer_err.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            read_invalid_buffer_err.message
        )

        assert.is_nil(diff_missing_bufnr_result)
        assert.are.equal(-32602, diff_missing_bufnr_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', diff_missing_bufnr_err.message)
        assert.is_nil(diff_invalid_bufnr_result)
        assert.are.equal(-32602, diff_invalid_bufnr_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', diff_invalid_bufnr_err.message)
        assert.are.equal(-32602, diff_missing_bufnr_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', diff_missing_bufnr_router.error.message)
        assert.are.equal(-32602, diff_invalid_bufnr_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', diff_invalid_bufnr_router.error.message)
        assert.are.equal(-32000, diff_invalid_buffer_router.error.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            diff_invalid_buffer_router.error.message
        )
        assert.is_nil(diff_invalid_buffer_result)
        assert.are.equal(-32000, diff_invalid_buffer_err.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            diff_invalid_buffer_err.message
        )

        assert.is_nil(write_missing_bufnr_result)
        assert.are.equal(-32602, write_missing_bufnr_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', write_missing_bufnr_err.message)
        assert.is_nil(write_invalid_bufnr_result)
        assert.are.equal(-32602, write_invalid_bufnr_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', write_invalid_bufnr_err.message)
        assert.are.equal(-32602, write_missing_bufnr_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', write_missing_bufnr_router.error.message)
        assert.are.equal(-32602, write_invalid_bufnr_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', write_invalid_bufnr_router.error.message)
        assert.are.equal(-32000, write_invalid_buffer_router.error.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            write_invalid_buffer_router.error.message
        )
        assert.is_nil(write_invalid_content_result)
        assert.are.equal(-32602, write_invalid_content_err.code)
        assert.are.equal('Invalid arguments: content must be a string', write_invalid_content_err.message)
        assert.is_nil(write_invalid_buffer_result)
        assert.are.equal(-32000, write_invalid_buffer_err.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            write_invalid_buffer_err.message
        )

        assert.is_nil(apply_missing_bufnr_result)
        assert.are.equal(-32602, apply_missing_bufnr_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', apply_missing_bufnr_err.message)
        assert.is_nil(apply_invalid_bufnr_result)
        assert.are.equal(-32602, apply_invalid_bufnr_err.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', apply_invalid_bufnr_err.message)
        assert.are.equal(-32602, apply_missing_bufnr_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', apply_missing_bufnr_router.error.message)
        assert.are.equal(-32602, apply_invalid_bufnr_router.error.code)
        assert.are.equal('Invalid arguments: bufnr must be an integer', apply_invalid_bufnr_router.error.message)
        assert.are.equal(-32000, apply_invalid_buffer_router.error.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            apply_invalid_buffer_router.error.message
        )
        assert.is_nil(apply_invalid_content_result)
        assert.are.equal(-32602, apply_invalid_content_err.code)
        assert.are.equal('Invalid arguments: content must be a string', apply_invalid_content_err.message)
        assert.is_nil(apply_invalid_buffer_result)
        assert.are.equal(-32000, apply_invalid_buffer_err.code)
        assert.are.equal(
            string.format('Invalid buffer id: %s', tostring(invalid_bufnr)),
            apply_invalid_buffer_err.message
        )
    end)

    it('returns structured errors for editor/write_buffer invalid arguments and non-modifiable buffers', function()
        local plugin = require('mcp')
        plugin.setup()

        local current_bufnr = vim.api.nvim_get_current_buf()
        local invalid_result, invalid_err = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = current_bufnr,
        }, {})
        local missing_router = plugin.handle_request('tools/call', {
            name = 'neovim/editor/write_buffer',
            arguments = {
                bufnr = current_bufnr,
            },
        }, 15, {})

        vim.bo[current_bufnr].modifiable = false
        local readonly_result, readonly_err = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = current_bufnr,
            content = 'after',
        }, {})
        vim.bo[current_bufnr].modifiable = true

        assert.is_nil(invalid_result)
        assert.are.equal(-32602, invalid_err.code)
        assert.are.equal('Invalid arguments: content must be a string', invalid_err.message)
        assert.are.equal(-32602, missing_router.error.code)
        assert.are.equal('Invalid arguments: content must be a string', missing_router.error.message)
        assert.is_nil(readonly_result)
        assert.are.equal(-32000, readonly_err.code)
        assert.are.equal(string.format('Buffer %d is not modifiable', current_bufnr), readonly_err.message)
    end)

    it('returns an error when waiting for terminal completion in a fast event context', function()
        local plugin = require('mcp')
        plugin.setup()

        local terminal_result, terminal_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'sh', '-c', 'sleep 0.05; printf hello' },
        }, {})
        assert.is_nil(terminal_err)
        assert.is_not_nil(terminal_result)

        local original_in_fast_event = vim.in_fast_event
        vim.in_fast_event = function()
            return true
        end

        local wait_result, wait_err = plugin.call_tool('neovim/terminal/wait', {
            terminal_id = terminal_result.terminal_id,
        }, {})

        vim.in_fast_event = original_in_fast_event

        assert.is_nil(terminal_err)
        assert.is_nil(wait_result)
        assert.is_not_nil(wait_err)
        assert.truthy(string.find(wait_err.message, 'fast events', 1, true))
    end)

    it('returns a structured error when terminal wait produces no result', function()
        local runtime = require('mcp.builtin.terminal_runtime')
        local _, get_terminal = debug.getupvalue(runtime.output, 1)
        local _, terminals = debug.getupvalue(get_terminal, 1)
        local terminal_id = 'term-test-nil-wait'

        terminals[terminal_id] = {
            proc = {
                wait = function()
                    return nil
                end,
                kill = function() end,
            },
            stdout_chunks = {},
            stderr_chunks = {},
            completed = nil,
        }

        local wait_result, wait_err = runtime.wait(terminal_id)

        assert.is_nil(wait_result)
        assert.are.same({
            code = -32000,
            message = 'terminal wait failed to produce a completion result',
        }, wait_err)
    end)

    it('accumulates terminal output chunks before wait', function()
        local runtime = require('mcp.builtin.terminal_runtime')
        local _, get_terminal = debug.getupvalue(runtime.output, 1)
        local _, terminals = debug.getupvalue(get_terminal, 1)
        local terminal_id = 'term-test'

        terminals[terminal_id] = {
            proc = {
                wait = function()
                    return { code = 0 }
                end,
                kill = function() end,
            },
            stdout_chunks = { 'hello', ' world' },
            stderr_chunks = { 'err1', ' err2' },
            completed = { code = 0 },
        }

        local output_result, output_err = runtime.output(terminal_id)
        local release_result, release_err = runtime.release(terminal_id)

        assert.is_nil(output_err)
        assert.are.equal('hello world', output_result.stdout)
        assert.are.equal('err1 err2', output_result.stderr)
        assert.is_nil(release_err)
        assert.is_true(release_result.released)
    end)

    it('does not duplicate terminal output when completion already streamed chunks', function()
        local runtime = require('mcp.builtin.terminal_runtime')
        local _, get_terminal = debug.getupvalue(runtime.output, 1)
        local _, terminals = debug.getupvalue(get_terminal, 1)
        local terminal_id = 'term-test-dup'

        terminals[terminal_id] = {
            proc = {
                wait = function()
                    return {
                        code = 0,
                        stdout = 'hello world',
                        stderr = 'err1 err2',
                    }
                end,
                kill = function() end,
            },
            stdout_chunks = { 'hello', ' world' },
            stderr_chunks = { 'err1', ' err2' },
            completed = nil,
        }

        local wait_result, wait_err = runtime.wait(terminal_id)
        local output_result, output_err = runtime.output(terminal_id)
        local release_result, release_err = runtime.release(terminal_id)

        assert.is_nil(wait_err)
        assert.are.equal(0, wait_result.exit_code)
        assert.is_nil(output_err)
        assert.are.equal('hello world', output_result.stdout)
        assert.are.equal('err1 err2', output_result.stderr)
        assert.is_nil(release_err)
        assert.is_true(release_result.released)
    end)

    it('reports signal information for signaled terminal exits', function()
        local runtime = require('mcp.builtin.terminal_runtime')
        local _, get_terminal = debug.getupvalue(runtime.output, 1)
        local _, terminals = debug.getupvalue(get_terminal, 1)
        local terminal_id = 'term-test-signal'

        terminals[terminal_id] = {
            proc = {
                wait = function()
                    return {
                        code = nil,
                        signal = 15,
                    }
                end,
                kill = function() end,
            },
            stdout_chunks = {},
            stderr_chunks = {},
            completed = nil,
        }

        local wait_result, wait_err = runtime.wait(terminal_id)
        local release_result, release_err = runtime.release(terminal_id)

        assert.is_nil(wait_err)
        assert.are.equal(143, wait_result.exit_code)
        assert.are.equal(15, wait_result.signal)
        assert.is_nil(release_err)
        assert.is_true(release_result.released)
    end)

    it('captures completion callback output when only part of the stream arrived incrementally', function()
        local runtime = require('mcp.builtin.terminal_runtime')
        local _, get_terminal = debug.getupvalue(runtime.output, 1)
        local _, terminals = debug.getupvalue(get_terminal, 1)
        local _, append_output_if_missing = debug.getupvalue(runtime.create, 3)

        local cases = {
            {
                terminal_id = 'term-test-callback-prefix',
                stdout_chunks = { 'hello' },
                stderr_chunks = {},
                completed = {
                    code = 0,
                    stdout = 'hello world',
                    stderr = 'warn',
                },
                expected_stdout = 'hello world',
                expected_stderr = 'warn',
            },
            {
                terminal_id = 'term-test-callback-diverged-stdout',
                stdout_chunks = { 'hello wo', 'rld!' },
                stderr_chunks = { 'warn' },
                completed = {
                    code = 0,
                    stdout = 'hello world',
                    stderr = 'warn',
                },
                expected_stdout = 'hello world',
                expected_stderr = 'warn',
            },
            {
                terminal_id = 'term-test-callback-diverged-stderr',
                stdout_chunks = { 'done' },
                stderr_chunks = { 'warn!' },
                completed = {
                    code = 0,
                    stdout = 'done',
                    stderr = 'warn',
                },
                expected_stdout = 'done',
                expected_stderr = 'warn',
            },
        }

        for _, case in ipairs(cases) do
            terminals[case.terminal_id] = {
                proc = {
                    wait = function()
                        error('wait should not be called when completion callback already ran')
                    end,
                    kill = function() end,
                },
                stdout_chunks = vim.deepcopy(case.stdout_chunks),
                stderr_chunks = vim.deepcopy(case.stderr_chunks),
                completed = nil,
            }

            terminals[case.terminal_id].completed = case.completed

            append_output_if_missing(terminals[case.terminal_id].stdout_chunks, case.completed.stdout)
            append_output_if_missing(terminals[case.terminal_id].stderr_chunks, case.completed.stderr)

            local output_result, output_err = runtime.output(case.terminal_id)
            local release_result, release_err = runtime.release(case.terminal_id)

            assert.is_nil(output_err)
            assert.are.equal(case.expected_stdout, output_result.stdout)
            assert.are.equal(case.expected_stderr, output_result.stderr)
            assert.is_true(output_result.completed)
            assert.is_nil(release_err)
            assert.is_true(release_result.released)
        end
    end)

    it('normalizes relative cwd before spawning terminal commands', function()
        local runtime = require('mcp.builtin.terminal_runtime')
        local editor_io = require('mcp.builtin.editor.io')
        local original_system = vim.system
        local tempdir = vim.fn.tempname()
        local child = 'child'
        local absolute_cwd = editor_io.normalize_path(tempdir .. '/' .. child)
        local seen_opts

        vim.fn.mkdir(absolute_cwd, 'p')

        vim.system = function(command, opts, on_exit)
            seen_opts = opts
            if on_exit ~= nil then
                on_exit({ code = 0, signal = 0, stdout = '', stderr = '' })
            end
            return {
                wait = function()
                    return { code = 0, signal = 0, stdout = '', stderr = '' }
                end,
                kill = function() end,
            }
        end

        local original_cwd = vim.fn.getcwd()
        vim.cmd('cd ' .. vim.fn.fnameescape(tempdir))

        local result, err = runtime.create({ 'pwd' }, child)

        vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
        vim.system = original_system
        vim.fn.delete(tempdir, 'rf')

        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.are.equal(absolute_cwd, seen_opts.cwd)
    end)

    it('returns structured errors for terminal invalid arguments and released terminal lookups', function()
        local plugin = require('mcp')
        plugin.setup()

        local missing_command_result, missing_command_err = plugin.call_tool('neovim/terminal/create', {}, {})
        local invalid_command_result, invalid_command_err = plugin.call_tool('neovim/terminal/create', {
            command = 'printf hello',
        }, {})
        local invalid_cwd_result, invalid_cwd_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'printf', 'hello' },
            cwd = {},
        }, {})

        local missing_terminal_id_result, missing_terminal_id_err = plugin.call_tool('neovim/terminal/output', {}, {})
        local invalid_terminal_id_result, invalid_terminal_id_err = plugin.call_tool('neovim/terminal/wait', {
            terminal_id = {},
        }, {})
        local invalid_release_result, invalid_release_err = plugin.call_tool('neovim/terminal/release', {
            terminal_id = 1,
        }, {})

        local router_missing_command = plugin.handle_request('tools/call', {
            name = 'neovim/terminal/create',
            arguments = {},
        }, 101, {})
        local router_invalid_terminal_id = plugin.handle_request('tools/call', {
            name = 'neovim/terminal/wait',
            arguments = {
                terminal_id = {},
            },
        }, 102, {})

        local terminal_result, terminal_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'printf', 'hello' },
        }, {})
        assert.is_nil(terminal_err)
        assert.is_not_nil(terminal_result)
        local release_result, release_err = plugin.call_tool('neovim/terminal/release', {
            terminal_id = terminal_result.terminal_id,
        }, {})
        local released_output_result, released_output_err = plugin.call_tool('neovim/terminal/output', {
            terminal_id = terminal_result.terminal_id,
        }, {})
        local released_wait_result, released_wait_err = plugin.call_tool('neovim/terminal/wait', {
            terminal_id = terminal_result.terminal_id,
        }, {})

        assert.is_nil(missing_command_result)
        assert.are.equal(-32602, missing_command_err.code)
        assert.are.equal('Invalid arguments: command must be an array of strings', missing_command_err.message)
        assert.is_nil(invalid_command_result)
        assert.are.equal(-32602, invalid_command_err.code)
        assert.are.equal('Invalid arguments: command must be an array of strings', invalid_command_err.message)
        assert.is_nil(invalid_cwd_result)
        assert.are.equal(-32602, invalid_cwd_err.code)
        assert.are.equal('Invalid arguments: cwd must be a string', invalid_cwd_err.message)

        assert.is_nil(missing_terminal_id_result)
        assert.are.equal(-32602, missing_terminal_id_err.code)
        assert.are.equal('Invalid arguments: terminal_id must be a string', missing_terminal_id_err.message)
        assert.is_nil(invalid_terminal_id_result)
        assert.are.equal(-32602, invalid_terminal_id_err.code)
        assert.are.equal('Invalid arguments: terminal_id must be a string', invalid_terminal_id_err.message)
        assert.is_nil(invalid_release_result)
        assert.are.equal(-32602, invalid_release_err.code)
        assert.are.equal('Invalid arguments: terminal_id must be a string', invalid_release_err.message)

        assert.are.equal(-32602, router_missing_command.error.code)
        assert.are.equal('Invalid arguments: command must be an array of strings', router_missing_command.error.message)
        assert.are.equal(-32602, router_invalid_terminal_id.error.code)
        assert.are.equal('Invalid arguments: terminal_id must be a string', router_invalid_terminal_id.error.message)

        assert.is_nil(terminal_err)
        assert.is_nil(release_err)
        assert.is_true(release_result.released)
        assert.is_nil(released_output_result)
        assert.are.equal(-32000, released_output_err.code)
        assert.are.equal(
            string.format('Unknown terminal id: %s', terminal_result.terminal_id),
            released_output_err.message
        )
        assert.is_nil(released_wait_result)
        assert.are.equal(-32000, released_wait_err.code)
        assert.are.equal(
            string.format('Unknown terminal id: %s', terminal_result.terminal_id),
            released_wait_err.message
        )
    end)

    it('terminates a running terminal on release', function()
        local plugin = require('mcp')
        plugin.setup()

        local terminal_result, terminal_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'sleep', '10' },
        }, {})

        assert.is_nil(terminal_err)
        assert.is_not_nil(terminal_result)

        local release_result, release_err = plugin.call_tool('neovim/terminal/release', {
            terminal_id = terminal_result.terminal_id,
        }, {})

        assert.is_nil(release_err)
        assert.is_true(release_result.released)

        vim.wait(1000, function()
            local ps = vim.system({ 'sh', '-lc', 'ps -o command= | grep "[s]leep 10" || true' }, { text = true }):wait()
            return vim.trim(ps.stdout or '') == ''
        end)

        local ps = vim.system({ 'sh', '-lc', 'ps -o command= | grep "[s]leep 10" || true' }, { text = true }):wait()
        assert.are.equal('', vim.trim(ps.stdout or ''))
    end)

    it('implements editor/write_file and reloads a loaded matching buffer', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})
        local result, err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()

        assert.is_nil(diff_err)
        assert.is_true(#diff_result.hunks >= 1)
        assert.is_nil(err)
        assert.is_true(result.reloaded_buffer)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.is_false(vim.bo[0].modified)
        assert.are.equal('after\nvalue\n', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('treats empty decoded content as zero lines', function()
        local editor_io = require('mcp.builtin.editor.io')

        assert.are.same({}, editor_io.decode_content(''))
    end)

    it('writes empty file content without introducing a trailing newline', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/empty-file.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        local result, err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            content = '',
        }, {})

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()

        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.are.equal('', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('implements editor/write_file without failing when a matching buffer unloads before reload', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file-unloaded.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local bufnr = vim.api.nvim_get_current_buf()
        vim.cmd('enew')
        vim.api.nvim_buf_delete(bufnr, { force = true })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()

        assert.is_nil(err)
        assert.is_false(result.reloaded_buffer)
        assert.are.equal('after\nvalue\n', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('returns success with a warning when apply_diff_file reload fails after disk write', function()
        local plugin = require('mcp')
        local editor_io = require('mcp.builtin.editor.io')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/apply-diff-file-reload-warning.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local bufnr = vim.api.nvim_get_current_buf()
        local original_reload_buffer = editor_io.reload_buffer
        local reload_warning = {
            code = -32001,
            message = 'reload failed',
        }

        editor_io.reload_buffer = function(target_bufnr)
            assert.are.equal(bufnr, target_bufnr)
            return reload_warning
        end

        local result, err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        editor_io.reload_buffer = original_reload_buffer

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()

        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.is_true(result.reloaded_buffer)
        assert.are.equal('after\nvalue\n', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('does not return a warning when apply_diff_file reload succeeds', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/apply-diff-file-reload-success.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))

        local result, err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()

        assert.is_nil(err)
        assert.is_not_nil(result)
        assert.is_true(result.reloaded_buffer)
        assert.is_nil(result.warning)
        assert.are.equal('after\nvalue\n', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('reloads file-backed buffers via checktime semantics', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file-checktime.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        vim.bo.filetype = 'lua'

        local events = {}
        local group = vim.api.nvim_create_augroup('mcp-write-file-reload-test', { clear = true })
        vim.api.nvim_create_autocmd('BufReadPost', {
            group = group,
            buffer = vim.api.nvim_get_current_buf(),
            callback = function()
                table.insert(events, 'BufReadPost')
            end,
        })
        vim.api.nvim_create_autocmd('FileType', {
            group = group,
            buffer = vim.api.nvim_get_current_buf(),
            callback = function(args)
                table.insert(events, 'FileType:' .. vim.bo[args.buf].filetype)
            end,
        })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(err)
        assert.is_true(result.reloaded_buffer)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.is_true(vim.tbl_contains(events, 'BufReadPost'))
        assert.are.same({ 'BufReadPost', 'FileType:lua' }, events)

        vim.api.nvim_del_augroup_by_id(group)
        vim.fn.delete(root, 'rf')
    end)

    it('reloads hidden file-backed buffers after write_file', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file-hidden-buffer.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local bufnr = vim.api.nvim_get_current_buf()
        vim.bo[bufnr].filetype = 'lua'
        vim.cmd('enew')

        local events = {}
        local group = vim.api.nvim_create_augroup('mcp-write-file-hidden-reload-test', { clear = true })
        vim.api.nvim_create_autocmd('BufReadPost', {
            group = group,
            buffer = bufnr,
            callback = function()
                table.insert(events, 'BufReadPost')
            end,
        })
        vim.api.nvim_create_autocmd('FileType', {
            group = group,
            buffer = bufnr,
            callback = function(args)
                table.insert(events, 'FileType:' .. vim.bo[args.buf].filetype)
            end,
        })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(err)
        assert.is_true(result.reloaded_buffer)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.is_true(vim.tbl_contains(events, 'BufReadPost'))
        assert.are.same({ 'BufReadPost', 'FileType:lua' }, events)

        vim.api.nvim_del_augroup_by_id(group)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('keeps hidden-buffer reload autocommands from recursively re-entering write_file', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file-hidden-buffer-autocmd.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local bufnr = vim.api.nvim_get_current_buf()
        vim.cmd('enew')

        local enter_count = 0
        local nested_calls = 0
        local side_effect = root .. '/unexpected-side-effect.txt'
        local group = vim.api.nvim_create_augroup('mcp-write-file-hidden-reload-autocmd-test', { clear = true })
        vim.api.nvim_create_autocmd('BufReadPost', {
            group = group,
            buffer = bufnr,
            callback = function()
                enter_count = enter_count + 1
                if nested_calls == 0 then
                    nested_calls = nested_calls + 1
                    local nested_result, nested_err = plugin.call_tool('neovim/editor/write_file', {
                        path = side_effect,
                        content = 'nested\\n',
                    }, {})
                    assert.is_nil(nested_err)
                    assert.is_false(nested_result.reloaded_buffer)
                end
            end,
        })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\\nvalue\\n',
        }, {})

        assert.is_nil(err)
        assert.is_true(result.reloaded_buffer)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.are.equal(1, enter_count)
        assert.are.equal(1, nested_calls)
        assert.are.same({ 'nested' }, vim.fn.readfile(side_effect))

        vim.api.nvim_del_augroup_by_id(group)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('reloads hidden file-backed buffers when current window is floating', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file-hidden-buffer-floating.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local bufnr = vim.api.nvim_get_current_buf()
        vim.bo[bufnr].filetype = 'lua'
        vim.cmd('enew')

        local normal_win = vim.api.nvim_get_current_win()
        local float_buf = vim.api.nvim_create_buf(false, true)
        local float_win = vim.api.nvim_open_win(float_buf, true, {
            relative = 'editor',
            row = 1,
            col = 1,
            width = 20,
            height = 2,
            style = 'minimal',
        })

        local events = {}
        local group = vim.api.nvim_create_augroup('mcp-write-file-hidden-reload-floating-test', { clear = true })
        vim.api.nvim_create_autocmd('BufReadPost', {
            group = group,
            buffer = bufnr,
            callback = function()
                table.insert(events, 'BufReadPost')
            end,
        })
        vim.api.nvim_create_autocmd('FileType', {
            group = group,
            buffer = bufnr,
            callback = function(args)
                table.insert(events, 'FileType:' .. vim.bo[args.buf].filetype)
            end,
        })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(err)
        assert.is_true(result.reloaded_buffer)
        assert.are.same(float_win, vim.api.nvim_get_current_win())
        assert.is_true(vim.api.nvim_win_is_valid(normal_win))
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.are.same({ 'BufReadPost', 'FileType:lua' }, events)

        vim.api.nvim_del_augroup_by_id(group)
        vim.api.nvim_win_close(float_win, true)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('reloads hidden file-backed buffers from floating window without touching tab state', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file-hidden-buffer-floating-no-tab-fallback.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local bufnr = vim.api.nvim_get_current_buf()
        vim.bo[bufnr].filetype = 'lua'

        local original_tab = vim.api.nvim_get_current_tabpage()
        vim.t.mcp_hidden_reload_tab_marker = 'original'
        local float_buf = vim.api.nvim_create_buf(false, true)
        local float_win = vim.api.nvim_open_win(float_buf, true, {
            relative = 'editor',
            row = 1,
            col = 1,
            width = 20,
            height = 2,
            style = 'minimal',
        })
        vim.cmd('enew')

        local reopened_float_buf = vim.api.nvim_create_buf(false, true)
        local reopened_float_win = vim.api.nvim_open_win(reopened_float_buf, true, {
            relative = 'editor',
            row = 1,
            col = 1,
            width = 20,
            height = 2,
            style = 'minimal',
        })
        local reopened_float_initial_buf = vim.api.nvim_win_get_buf(reopened_float_win)
        vim.wo[reopened_float_win].winbar = 'hidden-reload-float'
        local reopened_float_initial_winbar = vim.wo[reopened_float_win].winbar

        local events = {}
        local group =
            vim.api.nvim_create_augroup('mcp-write-file-hidden-reload-floating-no-tab-fallback-test', { clear = true })
        vim.api.nvim_create_autocmd('BufReadPost', {
            group = group,
            buffer = bufnr,
            callback = function()
                table.insert(events, 'BufReadPost')
            end,
        })
        vim.api.nvim_create_autocmd('FileType', {
            group = group,
            buffer = bufnr,
            callback = function(args)
                table.insert(events, 'FileType:' .. vim.bo[args.buf].filetype)
            end,
        })
        vim.api.nvim_create_autocmd('TabNew', {
            group = group,
            callback = function()
                table.insert(events, 'TabNew')
            end,
        })
        vim.api.nvim_create_autocmd('TabClosed', {
            group = group,
            callback = function()
                table.insert(events, 'TabClosed')
            end,
        })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(err)
        assert.is_true(result.reloaded_buffer)
        assert.are.same(reopened_float_win, vim.api.nvim_get_current_win())
        assert.are.same(original_tab, vim.api.nvim_get_current_tabpage())
        assert.are.equal('original', vim.t.mcp_hidden_reload_tab_marker)
        assert.are.same(reopened_float_initial_buf, vim.api.nvim_win_get_buf(reopened_float_win))
        assert.are.equal(reopened_float_initial_winbar, vim.wo[reopened_float_win].winbar)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.are.same({ 'BufReadPost', 'FileType:lua' }, events)

        vim.api.nvim_del_augroup_by_id(group)
        vim.api.nvim_win_close(reopened_float_win, true)
        vim.t.mcp_hidden_reload_tab_marker = nil
        vim.api.nvim_buf_delete(bufnr, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('restores the original tabpage after hidden-buffer reload uses another tabpage window', function()
        local io_mod = require('mcp.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-cross-tab-restore.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        local original_tab = vim.api.nvim_get_current_tabpage()
        vim.t.mcp_hidden_reload_restore_marker = 'keep-me'
        vim.cmd('enew')

        local original_tab_count = #vim.api.nvim_list_tabpages()
        local reuse_buf = vim.api.nvim_create_buf(false, true)

        vim.cmd('tabnew')
        local reused_win = vim.api.nvim_get_current_win()
        vim.t.mcp_hidden_reload_restore_marker = 'other-tab'
        vim.api.nvim_win_set_buf(reused_win, reuse_buf)
        vim.cmd('tabprevious')

        vim.fn.writefile({ 'fresh' }, path)

        local reload_err = io_mod.reload_buffer(target_buf)

        assert.is_nil(reload_err)
        assert.are.same(original_tab, vim.api.nvim_get_current_tabpage())
        assert.are.equal('keep-me', vim.t.mcp_hidden_reload_restore_marker)
        assert.are.equal(reuse_buf, vim.api.nvim_win_get_buf(reused_win))
        assert.are.same({ 'fresh' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))

        vim.t.mcp_hidden_reload_restore_marker = nil
        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.api.nvim_buf_delete(reuse_buf, { force = true })
        vim.fn.delete(root, 'rf')

        while #vim.api.nvim_list_tabpages() > original_tab_count do
            vim.cmd('tabclose!')
        end
    end)

    it('reuses an existing normal window from another tabpage for hidden-buffer reload', function()
        local io_mod = require('mcp.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-cross-tab.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        vim.cmd('enew')

        local original_tab_count = #vim.api.nvim_list_tabpages()
        local reuse_buf = vim.api.nvim_create_buf(false, true)

        vim.cmd('tabnew')
        local reused_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(reused_win, reuse_buf)
        vim.cmd('tabprevious')

        vim.fn.writefile({ 'fresh' }, path)

        local synthetic_opened = false
        local original_open_win = vim.api.nvim_open_win
        vim.api.nvim_open_win = function(...)
            synthetic_opened = true
            return original_open_win(...)
        end

        local reload_err = io_mod.reload_buffer(target_buf)

        vim.api.nvim_open_win = original_open_win

        assert.is_nil(reload_err)
        assert.is_false(synthetic_opened)
        assert.are.equal(reuse_buf, vim.api.nvim_win_get_buf(reused_win))
        assert.are.same({ 'fresh' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))

        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.api.nvim_buf_delete(reuse_buf, { force = true })
        vim.fn.delete(root, 'rf')

        while #vim.api.nvim_list_tabpages() > original_tab_count do
            vim.cmd('tabclose!')
        end
    end)

    it('restores the original tabpage after hidden-buffer reload fails in a reused window', function()
        local io_mod = require('mcp.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-cross-tab-error.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        local original_tab = vim.api.nvim_get_current_tabpage()
        local original_win = vim.api.nvim_get_current_win()
        local original_view = vim.fn.winsaveview()
        vim.t.mcp_hidden_reload_restore_error_marker = 'keep-me'
        vim.cmd('enew')

        local original_tab_count = #vim.api.nvim_list_tabpages()
        local reuse_buf = vim.api.nvim_create_buf(false, true)

        vim.cmd('tabnew')
        local reused_win = vim.api.nvim_get_current_win()
        vim.t.mcp_hidden_reload_restore_error_marker = 'other-tab'
        vim.api.nvim_win_set_buf(reused_win, reuse_buf)
        vim.cmd('tabprevious')

        local original_cmd = vim.cmd
        local ok, reload_err = xpcall(function()
            vim.cmd = function(command)
                if command == 'silent checktime' then
                    error('checktime failed')
                end
                return original_cmd(command)
            end

            return io_mod.reload_buffer(target_buf)
        end, debug.traceback)
        vim.cmd = original_cmd
        if not ok then
            error(reload_err)
        end

        assert.is_not_nil(reload_err)
        assert.are.equal(-32000, reload_err.code)
        assert.matches('checktime failed', reload_err.message)
        assert.are.same(original_tab, vim.api.nvim_get_current_tabpage())
        assert.are.same(original_win, vim.api.nvim_get_current_win())
        assert.are.same(original_view, vim.fn.winsaveview())
        assert.are.equal('keep-me', vim.t.mcp_hidden_reload_restore_error_marker)
        assert.are.equal(reuse_buf, vim.api.nvim_win_get_buf(reused_win))

        vim.t.mcp_hidden_reload_restore_error_marker = nil
        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.api.nvim_buf_delete(reuse_buf, { force = true })
        vim.fn.delete(root, 'rf')

        while #vim.api.nvim_list_tabpages() > original_tab_count do
            vim.cmd('tabclose!')
        end
    end)

    it('reloads a hidden file-backed buffer without window APIs', function()
        local io_mod = require('mcp.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-headless.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        vim.cmd('enew')

        vim.fn.writefile({ 'after', 'value' }, path)

        local original_open_win = vim.api.nvim_open_win
        vim.api.nvim_open_win = function(...)
            error('window APIs unavailable')
        end

        local reload_err = io_mod.reload_buffer(target_buf)

        vim.api.nvim_open_win = original_open_win

        assert.is_nil(reload_err)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))

        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('does not clobber the current modified buffer when reloading a hidden buffer without window APIs', function()
        local io_mod = require('mcp.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-headless-protected.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        vim.cmd('enew')
        local visible_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(visible_buf, 0, -1, false, { 'unsaved change' })
        vim.bo[visible_buf].modified = true

        vim.fn.writefile({ 'after', 'value' }, path)

        local original_open_win = vim.api.nvim_open_win
        vim.api.nvim_open_win = function(...)
            error('window APIs unavailable')
        end

        local reload_err = io_mod.reload_buffer(target_buf)

        vim.api.nvim_open_win = original_open_win

        assert.is_nil(reload_err)
        assert.are.same(visible_buf, vim.api.nvim_get_current_buf())
        assert.are.same({ 'unsaved change' }, vim.api.nvim_buf_get_lines(visible_buf, 0, -1, false))
        assert.is_true(vim.bo[visible_buf].modified)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))

        vim.bo[visible_buf].modified = false
        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.api.nvim_buf_delete(visible_buf, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('cleans up the temporary fallback window when hidden-buffer reload checktime fails', function()
        local io_mod = require('mcp.builtin.editor.io')
        local bufnr = vim.api.nvim_create_buf(false, false)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'before' })

        local original_is_loaded = vim.api.nvim_buf_is_loaded
        local original_buf_call = vim.api.nvim_buf_call
        local original_win_findbuf = vim.fn.win_findbuf
        local original_tabpage_list_wins = vim.api.nvim_tabpage_list_wins
        local original_create_buf = vim.api.nvim_create_buf
        local original_open_win = vim.api.nvim_open_win
        local original_win_set_buf = vim.api.nvim_win_set_buf
        local original_win_is_valid = vim.api.nvim_win_is_valid
        local original_win_close = vim.api.nvim_win_close
        local original_buf_is_valid = vim.api.nvim_buf_is_valid
        local original_buf_delete = vim.api.nvim_buf_delete
        local original_cmd = vim.cmd

        vim.api.nvim_buf_is_loaded = function(target)
            if target == bufnr then
                return true
            end
            return original_is_loaded(target)
        end
        vim.api.nvim_buf_call = function(target, callback)
            if target == bufnr then
                return callback()
            end
            return original_buf_call(target, callback)
        end
        vim.fn.win_findbuf = function(target)
            if target == bufnr then
                return {}
            end
            return original_win_findbuf(target)
        end
        vim.api.nvim_tabpage_list_wins = function(_)
            return {}
        end

        local temp_buf = 987655
        local temp_win = 654321
        local deleted = false
        local closed = false
        vim.api.nvim_create_buf = function(listed, scratch)
            if listed == false and scratch == true then
                return temp_buf
            end
            return original_create_buf(listed, scratch)
        end
        vim.api.nvim_open_win = function(...)
            return temp_win
        end
        vim.api.nvim_win_set_buf = function(win, target)
            if win == temp_win and target == bufnr then
                return
            end
            return original_win_set_buf(win, target)
        end
        vim.api.nvim_win_is_valid = function(win)
            if win == temp_win then
                return not closed
            end
            return original_win_is_valid(win)
        end
        vim.api.nvim_win_close = function(win, force)
            if win == temp_win then
                closed = true
                return
            end
            return original_win_close(win, force)
        end
        vim.api.nvim_buf_is_valid = function(target)
            if target == temp_buf then
                return not deleted
            end
            return original_buf_is_valid(target)
        end
        vim.api.nvim_buf_delete = function(target, opts)
            if target == temp_buf then
                deleted = true
                return
            end
            return original_buf_delete(target, opts)
        end
        vim.cmd = function(command)
            if command == 'silent checktime' then
                error('checktime failed')
            end
            return original_cmd(command)
        end

        local reload_err = io_mod.reload_buffer(bufnr)

        vim.api.nvim_buf_is_loaded = original_is_loaded
        vim.api.nvim_buf_call = original_buf_call
        vim.fn.win_findbuf = original_win_findbuf
        vim.api.nvim_tabpage_list_wins = original_tabpage_list_wins
        vim.api.nvim_create_buf = original_create_buf
        vim.api.nvim_open_win = original_open_win
        vim.api.nvim_win_set_buf = original_win_set_buf
        vim.api.nvim_win_is_valid = original_win_is_valid
        vim.api.nvim_win_close = original_win_close
        vim.api.nvim_buf_is_valid = original_buf_is_valid
        vim.api.nvim_buf_delete = original_buf_delete
        vim.cmd = original_cmd
        vim.api.nvim_buf_delete(bufnr, { force = true })

        assert.is_not_nil(reload_err)
        assert.are.equal(-32000, reload_err.code)
        assert.matches('checktime failed', reload_err.message)
        assert.is_true(closed)
        assert.is_true(deleted)
    end)

    it('returns a structured error when hidden-buffer floating fallback window creation fails', function()
        local io_mod = require('mcp.builtin.editor.io')
        local bufnr = vim.api.nvim_create_buf(false, false)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'before' })

        local original_is_loaded = vim.api.nvim_buf_is_loaded
        local original_buf_call = vim.api.nvim_buf_call
        local original_win_findbuf = vim.fn.win_findbuf
        local original_tabpage_list_wins = vim.api.nvim_tabpage_list_wins
        local original_create_buf = vim.api.nvim_create_buf
        local original_open_win = vim.api.nvim_open_win
        local original_buf_is_valid = vim.api.nvim_buf_is_valid
        local original_buf_delete = vim.api.nvim_buf_delete

        vim.api.nvim_buf_is_loaded = function(target)
            if target == bufnr then
                return true
            end
            return original_is_loaded(target)
        end
        vim.api.nvim_buf_call = function(target, callback)
            if target == bufnr then
                return callback()
            end
            return original_buf_call(target, callback)
        end
        vim.fn.win_findbuf = function(target)
            if target == bufnr then
                return {}
            end
            return original_win_findbuf(target)
        end
        vim.api.nvim_tabpage_list_wins = function(_)
            return {}
        end

        local temp_buf = 987654
        local deleted = false
        vim.api.nvim_create_buf = function(listed, scratch)
            if listed == false and scratch == true then
                return temp_buf
            end
            return original_create_buf(listed, scratch)
        end
        vim.api.nvim_open_win = function(...)
            error('float unavailable')
        end
        vim.api.nvim_buf_is_valid = function(target)
            if target == temp_buf then
                return not deleted
            end
            return original_buf_is_valid(target)
        end
        vim.api.nvim_buf_delete = function(target, opts)
            if target == temp_buf then
                deleted = true
                return
            end
            return original_buf_delete(target, opts)
        end

        local reload_err = io_mod.reload_buffer(bufnr)

        vim.api.nvim_buf_is_loaded = original_is_loaded
        vim.api.nvim_buf_call = original_buf_call
        vim.fn.win_findbuf = original_win_findbuf
        vim.api.nvim_tabpage_list_wins = original_tabpage_list_wins
        vim.api.nvim_create_buf = original_create_buf
        vim.api.nvim_open_win = original_open_win
        vim.api.nvim_buf_is_valid = original_buf_is_valid
        vim.api.nvim_buf_delete = original_buf_delete
        vim.api.nvim_buf_delete(bufnr, { force = true })

        assert.is_not_nil(reload_err)
        assert.are.equal(-32000, reload_err.code)
        assert.matches('failed to create temporary reload window: .*float unavailable', reload_err.message)
        assert.is_true(deleted)
    end)

    it('keeps write and apply-diff current-buffer tools distinct', function()
        local plugin = require('mcp')
        plugin.setup()

        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'before' })

        local write_result, write_err = plugin.call_tool('neovim/editor/write_current_buffer', {
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(write_err)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.is_true(write_result.modified)
        assert.are.equal(vim.api.nvim_get_current_buf(), write_result.bufnr)
        assert.is_nil(write_result.applied_hunk_count)

        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'before' })
        vim.bo[0].modified = false

        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_current_buffer', {
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(apply_err)
        assert.is_true(apply_result.applied_hunk_count >= 1)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.is_true(apply_result.modified)
    end)

    it('keeps write/apply file tools distinct', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-apply-alias.txt'

        local write_result, write_err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(write_err)
        assert.is_false(write_result.reloaded_buffer)

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        vim.bo[0].modified = false

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\nmore\n',
        }, {})

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()
        assert.are.equal('after\nvalue\n', disk)

        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            content = 'after\nvalue\nmore\n',
        }, {})

        assert.is_nil(diff_err)
        assert.is_true(#diff_result.hunks >= 1)
        assert.is_nil(apply_err)
        assert.are.equal(vim.fn.fnamemodify(path, ':p'), apply_result.path)
        assert.is_true(apply_result.reloaded_buffer)
        assert.is_nil(apply_result.applied_hunk_count)
        assert.is_nil(write_result.applied_hunk_count)

        local post_apply_diff, post_apply_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\nmore\n',
        }, {})

        assert.is_nil(post_apply_err)
        assert.are.equal(0, #post_apply_diff.hunks)

        vim.fn.delete(root, 'rf')
    end)

    it('returns structured errors for editor diff tool invalid arguments', function()
        local plugin = require('mcp')
        plugin.setup()

        local current_bufnr = vim.api.nvim_get_current_buf()
        local diff_buffer_missing_result, diff_buffer_missing_err = plugin.call_tool('neovim/editor/diff_buffer', {
            bufnr = current_bufnr,
        }, {})
        local diff_buffer_invalid_result, diff_buffer_invalid_err = plugin.call_tool('neovim/editor/diff_buffer', {
            bufnr = current_bufnr,
            content = false,
        }, {})
        local diff_file_missing_path_result, diff_file_missing_path_err = plugin.call_tool('neovim/editor/diff_file', {
            content = 'after\n',
        }, {})
        local diff_file_invalid_path_result, diff_file_invalid_path_err = plugin.call_tool('neovim/editor/diff_file', {
            path = false,
            content = 'after\n',
        }, {})
        local diff_file_invalid_content_result, diff_file_invalid_content_err = plugin.call_tool(
            'neovim/editor/diff_file',
            {
                path = vim.fn.tempname(),
                content = false,
            },
            {}
        )

        assert.is_nil(diff_buffer_missing_result)
        assert.are.equal(-32602, diff_buffer_missing_err.code)
        assert.are.equal('Invalid arguments: content must be a string', diff_buffer_missing_err.message)

        assert.is_nil(diff_buffer_invalid_result)
        assert.are.equal(-32602, diff_buffer_invalid_err.code)
        assert.are.equal('Invalid arguments: content must be a string', diff_buffer_invalid_err.message)

        assert.is_nil(diff_file_missing_path_result)
        assert.are.equal(-32602, diff_file_missing_path_err.code)
        assert.are.equal('Invalid arguments: path must be a string', diff_file_missing_path_err.message)

        assert.is_nil(diff_file_invalid_path_result)
        assert.are.equal(-32602, diff_file_invalid_path_err.code)
        assert.are.equal('Invalid arguments: path must be a string', diff_file_invalid_path_err.message)

        assert.is_nil(diff_file_invalid_content_result)
        assert.are.equal(-32602, diff_file_invalid_content_err.code)
        assert.are.equal('Invalid arguments: content must be a string', diff_file_invalid_content_err.message)

        local router_diff_buffer_missing = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_buffer',
            arguments = {
                bufnr = current_bufnr,
            },
        })
        local router_diff_buffer_invalid = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_buffer',
            arguments = {
                bufnr = current_bufnr,
                content = false,
            },
        })
        local router_diff_file_missing_path = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_file',
            arguments = {
                content = 'after\n',
            },
        })
        local router_diff_file_invalid_path = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_file',
            arguments = {
                path = false,
                content = 'after\n',
            },
        })
        local router_diff_file_invalid_content = plugin.handle_request('tools/call', {
            name = 'neovim/editor/diff_file',
            arguments = {
                path = vim.fn.tempname(),
                content = false,
            },
        })

        assert.are.equal(-32602, router_diff_buffer_missing.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_diff_buffer_missing.error.message)

        assert.are.equal(-32602, router_diff_buffer_invalid.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_diff_buffer_invalid.error.message)

        assert.are.equal(-32602, router_diff_file_missing_path.error.code)
        assert.are.equal('Invalid arguments: path must be a string', router_diff_file_missing_path.error.message)

        assert.are.equal(-32602, router_diff_file_invalid_path.error.code)
        assert.are.equal('Invalid arguments: path must be a string', router_diff_file_invalid_path.error.message)

        assert.are.equal(-32602, router_diff_file_invalid_content.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_diff_file_invalid_content.error.message)
    end)

    it('rejects current-buffer and apply-diff tool invalid arguments', function()
        local plugin = require('mcp')
        plugin.setup()

        local write_missing_result, write_missing_err = plugin.call_tool('neovim/editor/write_current_buffer', {}, {})
        local write_invalid_result, write_invalid_err = plugin.call_tool('neovim/editor/write_current_buffer', {
            content = false,
        }, {})
        local apply_missing_result, apply_missing_err = plugin.call_tool(
            'neovim/editor/apply_diff_current_buffer',
            {},
            {}
        )
        local apply_invalid_result, apply_invalid_err = plugin.call_tool('neovim/editor/apply_diff_current_buffer', {
            content = false,
        }, {})
        local apply_buffer_missing_result, apply_buffer_missing_err = plugin.call_tool(
            'neovim/editor/apply_diff_buffer',
            {
                bufnr = vim.api.nvim_get_current_buf(),
            },
            {}
        )
        local apply_buffer_invalid_result, apply_buffer_invalid_err = plugin.call_tool(
            'neovim/editor/apply_diff_buffer',
            {
                bufnr = vim.api.nvim_get_current_buf(),
                content = false,
            },
            {}
        )
        local apply_file_missing_path_result, apply_file_missing_path_err = plugin.call_tool(
            'neovim/editor/apply_diff_file',
            {
                content = 'after\n',
            },
            {}
        )
        local apply_file_invalid_path_result, apply_file_invalid_path_err = plugin.call_tool(
            'neovim/editor/apply_diff_file',
            {
                path = false,
                content = 'after\n',
            },
            {}
        )
        local apply_file_invalid_content_result, apply_file_invalid_content_err = plugin.call_tool(
            'neovim/editor/apply_diff_file',
            {
                path = vim.fn.tempname(),
                content = false,
            },
            {}
        )

        assert.is_nil(write_missing_result)
        assert.are.equal(-32602, write_missing_err.code)
        assert.are.equal('Invalid arguments: content must be a string', write_missing_err.message)
        assert.is_nil(write_invalid_result)
        assert.are.equal(-32602, write_invalid_err.code)
        assert.are.equal('Invalid arguments: content must be a string', write_invalid_err.message)

        assert.is_nil(apply_missing_result)
        assert.are.equal(-32602, apply_missing_err.code)
        assert.are.equal('Invalid arguments: content must be a string', apply_missing_err.message)
        assert.is_nil(apply_invalid_result)
        assert.are.equal(-32602, apply_invalid_err.code)
        assert.are.equal('Invalid arguments: content must be a string', apply_invalid_err.message)

        assert.is_nil(apply_buffer_missing_result)
        assert.are.equal(-32602, apply_buffer_missing_err.code)
        assert.are.equal('Invalid arguments: content must be a string', apply_buffer_missing_err.message)
        assert.is_nil(apply_buffer_invalid_result)
        assert.are.equal(-32602, apply_buffer_invalid_err.code)
        assert.are.equal('Invalid arguments: content must be a string', apply_buffer_invalid_err.message)

        assert.is_nil(apply_file_missing_path_result)
        assert.are.equal(-32602, apply_file_missing_path_err.code)
        assert.are.equal('Invalid arguments: path must be a string', apply_file_missing_path_err.message)
        assert.is_nil(apply_file_invalid_path_result)
        assert.are.equal(-32602, apply_file_invalid_path_err.code)
        assert.are.equal('Invalid arguments: path must be a string', apply_file_invalid_path_err.message)
        assert.is_nil(apply_file_invalid_content_result)
        assert.are.equal(-32602, apply_file_invalid_content_err.code)
        assert.are.equal('Invalid arguments: content must be a string', apply_file_invalid_content_err.message)

        local router_write_missing = plugin.handle_request('tools/call', {
            name = 'neovim/editor/write_current_buffer',
            arguments = {},
        })
        local router_write_invalid = plugin.handle_request('tools/call', {
            name = 'neovim/editor/write_current_buffer',
            arguments = {
                content = false,
            },
        })
        local router_apply_missing = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_current_buffer',
            arguments = {},
        })
        local router_apply_invalid = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_current_buffer',
            arguments = {
                content = false,
            },
        })
        local router_apply_file_missing_path = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_file',
            arguments = {
                content = 'after\n',
            },
        })
        local router_apply_file_invalid_path = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_file',
            arguments = {
                path = false,
                content = 'after\n',
            },
        })
        local router_apply_file_invalid_content = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_file',
            arguments = {
                path = vim.fn.tempname(),
                content = false,
            },
        })

        assert.are.equal(-32602, router_write_missing.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_write_missing.error.message)

        assert.are.equal(-32602, router_write_invalid.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_write_invalid.error.message)

        assert.are.equal(-32602, router_apply_missing.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_apply_missing.error.message)

        assert.are.equal(-32602, router_apply_invalid.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_apply_invalid.error.message)

        assert.are.equal(-32602, router_apply_file_missing_path.error.code)
        assert.are.equal('Invalid arguments: path must be a string', router_apply_file_missing_path.error.message)

        assert.are.equal(-32602, router_apply_file_invalid_path.error.code)
        assert.are.equal('Invalid arguments: path must be a string', router_apply_file_invalid_path.error.message)

        assert.are.equal(-32602, router_apply_file_invalid_content.error.code)
        assert.are.equal('Invalid arguments: content must be a string', router_apply_file_invalid_content.error.message)
    end)

    it('diffs a missing file against empty content', function()
        local plugin = require('mcp')
        plugin.setup()

        local path = vim.fn.tempname()
        local result, err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(err)
        assert.are.equal(vim.fs.normalize(vim.fn.fnamemodify(path, ':p')), result.path)
        assert.is_true(#result.hunks >= 1)
        assert.are.same({ 'after', 'value' }, result.hunks[1].replacement)
    end)

    it('rejects editor/write_file when path or content are invalid', function()
        local plugin = require('mcp')
        plugin.setup()

        local result1, err1 = plugin.call_tool('neovim/editor/write_file', {
            content = 'after\n',
        }, {})
        local result2, err2 = plugin.call_tool('neovim/editor/write_file', {
            path = 17,
            content = 'after\n',
        }, {})
        local result3, err3 = plugin.call_tool('neovim/editor/write_file', {
            path = vim.fn.tempname(),
            content = false,
        }, {})

        assert.is_nil(result1)
        assert.are.equal(-32602, err1.code)
        assert.are.equal('Invalid arguments: path must be a string', err1.message)

        assert.is_nil(result2)
        assert.are.equal(-32602, err2.code)
        assert.are.equal('Invalid arguments: path must be a string', err2.message)

        assert.is_nil(result3)
        assert.are.equal(-32602, err3.code)
        assert.are.equal('Invalid arguments: content must be a string', err3.message)
    end)

    it('rejects editor/write_file when the matching buffer has unsaved changes', function()
        local plugin = require('mcp')
        plugin.setup()

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/write-file-dirty.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'before', 'draft change' })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()

        assert.is_nil(result)
        assert.are.equal(-32000, err.code)
        assert.are.equal('Buffer ' .. vim.api.nvim_get_current_buf() .. ' has unsaved changes', err.message)
        assert.are.same({ 'before', 'draft change' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.is_true(vim.bo[0].modified)
        assert.are.equal('before\n', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('treats exact server-name tool identifiers as already qualified', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'editor',
            tools = {
                editor = {
                    handler = function(arguments)
                        return {
                            echoed = arguments.command,
                        }
                    end,
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'editor',
            tool = 'editor',
            name = 'editor/editor',
            arguments = {
                command = { 'printf', 'hello' },
            },
        }, 7, {})

        assert.is_nil(call.error)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    echoed = { 'printf', 'hello' },
                }),
            },
        }, call.result.content)
    end)

    it('reset clears preserved user neovim server entries', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            title = 'Custom Neovim',
            tools = {
                custom = {
                    ping = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
            },
            resources = {
                {
                    uri = 'custom://resource',
                    handler = function()
                        return {}
                    end,
                },
            },
            resource_templates = {
                {
                    name = 'custom-template',
                    uri_template = 'custom://{id}',
                    handler = function()
                        return {}
                    end,
                },
            },
            prompts = {
                {
                    name = 'custom-prompt',
                    handler = function()
                        return {}
                    end,
                },
            },
        })

        plugin.setup()
        plugin.reset()
        plugin.setup()

        local server = plugin.list_servers()[1]
        local tool_names = vim.tbl_map(function(tool)
            return tool.name
        end, server.tools or {})
        local resource_uris = vim.tbl_map(function(resource)
            return resource.uri
        end, server.resources or {})
        local template_names = vim.tbl_map(function(template)
            return template.name
        end, server.resource_templates or {})
        local prompt_names = vim.tbl_map(function(prompt)
            return prompt.name
        end, server.prompts or {})

        assert.are.equal('neovim', server.name)
        assert.are.equal('Neovim', server.title)
        assert.is_false(vim.tbl_contains(tool_names, 'custom/ping'))
        assert.is_true(vim.tbl_contains(tool_names, 'editor/list_buffers'))
        assert.is_false(vim.tbl_contains(resource_uris, 'custom://resource'))
        assert.is_false(vim.tbl_contains(template_names, 'custom-template'))
        assert.is_false(vim.tbl_contains(prompt_names, 'custom-prompt'))
    end)

    it('drops preserved neovim customizations after explicit unregister', function()
        local plugin = require('mcp')

        plugin.setup()
        plugin.register_server({
            name = 'neovim',
            title = 'Custom Neovim',
            description = 'Custom description',
            tools = {
                custom = {
                    ping = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
            },
            resources = {
                {
                    uri = 'custom://resource',
                    name = 'custom-resource',
                    handler = function()
                        return {}
                    end,
                },
            },
            resource_templates = {
                {
                    uri_template = 'custom://resource/{id}',
                    name = 'custom-template',
                    handler = function()
                        return {}
                    end,
                },
            },
            prompts = {
                {
                    name = 'custom-prompt',
                    description = 'Custom prompt',
                    handler = function()
                        return {}
                    end,
                },
            },
        })

        plugin.unregister_server('neovim')
        plugin.setup()

        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'neovim'
        end)
        local tool_names = vim.tbl_map(function(tool)
            return tool.name
        end, server.tools or {})
        local resource_uris = vim.tbl_map(function(resource)
            return resource.uri
        end, server.resources or {})
        local template_names = vim.tbl_map(function(template)
            return template.name
        end, server.resource_templates or {})
        local prompt_names = vim.tbl_map(function(prompt)
            return prompt.name
        end, server.prompts or {})

        assert.are.equal('Neovim', server.title)
        assert.are.equal('Built-in Neovim-local MCP capability surfaces.', server.description)
        assert.is_false(vim.tbl_contains(tool_names, 'custom/ping'))
        assert.is_true(vim.tbl_contains(tool_names, 'editor/list_buffers'))
        assert.is_false(vim.tbl_contains(resource_uris, 'custom://resource'))
        assert.is_false(vim.tbl_contains(template_names, 'custom-template'))
        assert.is_false(vim.tbl_contains(prompt_names, 'custom-prompt'))
    end)

    it('accepts requests without an accept header', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')
        local ok, err = xpcall(function()
            plugin.setup()
            local start_ok, start_err = http_server.start()
            assert.is_true(start_ok)
            assert.is_nil(start_err)
            local writes = {}
            local read_cb
            local client = {
                read_start = function(_, cb)
                    read_cb = cb
                    return true
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
            }

            http_server._start_client_read(client)
            read_cb(nil, table.concat({
                'POST /mcp HTTP/1.1',
                'Host: localhost',
                'Content-Type: application/json',
                'Content-Length: 51',
                '',
                '{"jsonrpc":"2.0","id":99,"method":"tools/list"}',
            }, '\r\n') .. '\r\n\r\n')

            vim.wait(1000, function()
                return writes[1] ~= nil
            end)
            assert.is_not_nil(writes[1])
            assert.truthy(writes[1]:find('406 Not Acceptable', 1, true) == nil)
            assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
            assert.truthy(writes[1]:find('Content-Type: application/json', 1, true) ~= nil)
        end, function(message)
            return debug.traceback(message, 2)
        end)
        plugin.reset()
        if not ok then
            error(err)
        end
    end)

    it('accepts wildcard application accept headers', function()
        local plugin = require('mcp')
        local http_server = require('mcp.http_server')
        local ok, err = xpcall(function()
            plugin.setup()
            local start_ok, start_err = http_server.start()
            assert.is_true(start_ok)
            assert.is_nil(start_err)
            local writes = {}
            local read_cb
            local client = {
                read_start = function(_, cb)
                    read_cb = cb
                    return true
                end,
                write = function(_, payload, cb)
                    table.insert(writes, payload)
                    if cb ~= nil then
                        cb()
                    end
                end,
                read_stop = function() end,
                close = function() end,
                is_closing = function()
                    return false
                end,
            }

            http_server._start_client_read(client)
            read_cb(nil, table.concat({
                'POST /mcp HTTP/1.1',
                'Host: localhost',
                'Content-Type: application/json',
                'Accept: application/*',
                'Content-Length: 51',
                '',
                '{"jsonrpc":"2.0","id":99,"method":"tools/list"}',
            }, '\r\n') .. '\r\n\r\n')

            vim.wait(1000, function()
                return writes[1] ~= nil
            end)
            assert.is_not_nil(writes[1])
            assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
            assert.truthy(writes[1]:find('Content-Type: application/json', 1, true) ~= nil)
        end, function(message)
            return debug.traceback(message, 2)
        end)
        plugin.reset()
        if not ok then
            error(err)
        end
    end)

    it('keeps HTTP/1.1 connections alive by default', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local closed = false
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function()
                closed = true
            end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        vim.wait(1000, function()
            return #writes == 1
        end)
        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('Connection: keep-alive', 1, true) ~= nil)
        assert.is_false(closed)
    end)

    it('closes HTTP/1.1 connections when requested', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local closed = false
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function()
                closed = true
            end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Connection: close',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        vim.wait(1000, function()
            return #writes == 1
        end)
        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('Connection: close', 1, true) ~= nil)
        assert.is_true(closed)
    end)

    it('responds with the matching HTTP version for HTTP/1.0 requests', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local closed = false
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function()
                closed = true
            end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.0',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        vim.wait(1000, function()
            return #writes == 1
        end)
        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.0 ', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Connection: close', 1, true) ~= nil)
        assert.is_true(closed)
    end)

    it('matches Connection tokens exactly when deciding keep-alive', function()
        local http_server = require('mcp.http_server')
        local writes = {}
        local closed = false
        local callback
        local body = vim.json.encode({
            jsonrpc = '2.0',
            method = 'ping',
        })
        local client = {
            read_start = function(_, cb)
                callback = cb
            end,
            read_stop = function() end,
            close = function()
                closed = true
            end,
            is_closing = function()
                return false
            end,
            write = function(_, payload, cb)
                table.insert(writes, payload)
                if cb ~= nil then
                    cb()
                end
            end,
        }

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.0',
                'Host: 127.0.0.1',
                'Connection: X-keep-alive-hint',
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        vim.wait(1000, function()
            return #writes == 1
        end)
        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('Connection: close', 1, true) ~= nil)
        assert.is_true(closed)
    end)

    it('does not leak synthetic merge servers during setup', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                custom = {
                    ping = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
            },
        })

        plugin.setup()

        local server_names = vim.tbl_map(function(server)
            return server.name
        end, plugin.list_servers())

        assert.is_false(vim.tbl_contains(server_names, '__mcp_builtin_neovim_merge__'))
    end)

    it('validates list-shaped tool handlers during registration', function()
        local plugin = require('mcp')

        assert.has_error(function()
            plugin.register_server({
                name = 'invalid-tools',
                tools = {
                    {
                        name = 'broken',
                        handler = 'nope',
                    },
                },
            })
        end, 'mcp tool handler must be a function')
    end)

    it('keeps user neovim server registrations sticky across repeated setup calls', function()
        local plugin = require('mcp')

        plugin.register_server({
            name = 'neovim',
            tools = {
                custom = {
                    ping = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
            },
        })

        plugin.setup()
        plugin.setup()

        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'neovim'
        end)
        local tool_names = vim.tbl_map(function(tool)
            return tool.name
        end, server.tools or {})

        assert.is_true(vim.tbl_contains(tool_names, 'custom/ping'))
        assert.is_true(vim.tbl_contains(tool_names, 'editor/list_buffers'))
    end)
    it('preserves explicit neovim server replacements across repeated setup calls', function()
        local plugin = require('mcp')

        plugin.setup()
        plugin.register_server({
            name = 'neovim',
            title = 'Custom Neovim',
            tools = {
                custom = {
                    ping = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
            },
        })

        plugin.setup({ enable_terminal_tools = true })
        plugin.setup()

        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'neovim'
        end)
        local tool_names = vim.tbl_map(function(tool)
            return tool.name
        end, server.tools or {})

        assert.are.equal('Custom Neovim', server.title)
        assert.is_true(vim.tbl_contains(tool_names, 'custom/ping'))
        assert.is_false(vim.tbl_contains(tool_names, 'editor/list_buffers'))
        assert.is_false(vim.tbl_contains(tool_names, 'terminal/create'))
    end)

    it('restores built-in neovim refresh after removing custom replacement tools', function()
        local plugin = require('mcp')

        plugin.setup()
        plugin.register_server({
            name = 'neovim',
            title = 'Custom Neovim',
            tools = {
                custom = {
                    ping = {
                        handler = function()
                            return { ok = true }
                        end,
                    },
                },
            },
        })

        plugin.register_tool('neovim', {
            name = 'editor/list_buffers',
            handler = function()
                return { ok = true }
            end,
        })
        plugin.unregister_tool('neovim', 'custom/ping')

        plugin.setup({ enable_terminal_tools = true })

        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'neovim'
        end)
        local tool_names = vim.tbl_map(function(tool)
            return tool.name
        end, server.tools or {})

        assert.are.equal('Neovim', server.title)
        assert.is_true(vim.tbl_contains(tool_names, 'editor/list_buffers'))
        assert.is_true(vim.tbl_contains(tool_names, 'terminal/create'))
    end)

    it('preserves built-in tool overrides across setup refreshes', function()
        local plugin = require('mcp')

        plugin.setup()

        local expected = { ok = 'override' }
        plugin.register_tool('neovim', {
            name = 'editor/list_buffers',
            description = 'Custom override',
            inputSchema = {
                type = 'object',
                properties = {
                    include_hidden = { type = 'boolean' },
                },
            },
            handler = function()
                return expected
            end,
        })

        plugin.setup({ enable_terminal_tools = true })
        plugin.setup()

        local listed = plugin.call_tool('neovim/editor/list_buffers', {}, {})
        assert.are.same(expected, listed)

        local descriptor = vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'neovim/editor/list_buffers'
        end)
        assert.are.equal('Custom override', descriptor.description)
        assert.are.same({
            type = 'object',
            properties = {
                include_hidden = { type = 'boolean' },
            },
        }, descriptor.inputSchema)
    end)

    it('retains built-in tool overrides when only the input schema changes', function()
        local plugin = require('mcp')

        plugin.setup()

        local builtin = vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'neovim/editor/list_buffers'
        end)

        local schema_override = vim.deepcopy(builtin.inputSchema)
        schema_override.properties = schema_override.properties or {}
        schema_override.properties.only_listed = { type = 'boolean' }

        plugin.register_tool('neovim', {
            name = 'editor/list_buffers',
            description = builtin.description,
            inputSchema = schema_override,
            handler = function(args, context)
                return plugin.call_tool('neovim/editor/list_buffers', args, context)
            end,
        })

        plugin.setup({ enable_terminal_tools = true })
        plugin.setup()

        local descriptor = vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'neovim/editor/list_buffers'
        end)
        assert.are.equal(builtin.description, descriptor.description)
        assert.are.same(schema_override.properties, descriptor.inputSchema.properties)
        assert.truthy(descriptor.inputSchema.properties.only_listed ~= nil)
        local result = plugin.call_tool('neovim/editor/list_buffers', {}, {})
        assert.is_table(result)
    end)

    it('does not retain equivalent built-in tool specs as overrides', function()
        local plugin = require('mcp')

        plugin.setup()

        local builtin = vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'neovim/editor/list_buffers'
        end)

        plugin.register_tool('neovim', {
            name = 'editor/list_buffers',
            description = builtin.description,
            inputSchema = vim.deepcopy(builtin.inputSchema),
            handler = builtin.handler,
        })

        plugin.setup({ enable_terminal_tools = true })
        plugin.setup()

        local descriptor = vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'neovim/editor/list_buffers'
        end)
        assert.are.equal(builtin.description, descriptor.description)
        assert.are.same(builtin.inputSchema, descriptor.inputSchema)
    end)

    it('refreshes built-in terminal tools across setup calls while preserving custom neovim tools', function()
        local plugin = require('mcp')

        plugin.register_tool('neovim', {
            name = 'custom/ping',
            handler = function()
                return { ok = true }
            end,
        })

        plugin.setup()

        local initial_tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_false(vim.tbl_contains(initial_tool_names, 'neovim/terminal/create'))

        plugin.setup({ enable_terminal_tools = true })

        local enabled_tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_true(vim.tbl_contains(enabled_tool_names, 'neovim/custom/ping'))
        assert.is_true(vim.tbl_contains(enabled_tool_names, 'neovim/terminal/create'))

        plugin.setup({ enable_terminal_tools = false })

        local disabled_tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_true(vim.tbl_contains(disabled_tool_names, 'neovim/custom/ping'))
        assert.is_false(vim.tbl_contains(disabled_tool_names, 'neovim/terminal/create'))
    end)
end)

it('re-registers built-in neovim server after reset and setup', function()
    local plugin = require('mcp')

    plugin.setup({ enable_terminal_tools = true })
    plugin.register_server({
        name = 'neovim',
        tools = {
            custom = {
                ping = {
                    handler = function()
                        return { ok = true }
                    end,
                },
            },
        },
    })

    plugin.reset()
    plugin.setup({ enable_terminal_tools = true })

    local tool_names = vim.tbl_map(function(tool)
        return tool.namespaced_name
    end, plugin.list_tool_descriptors())

    assert.is_true(vim.tbl_contains(tool_names, 'neovim/editor/list_buffers'))
    assert.is_true(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
    assert.is_false(vim.tbl_contains(tool_names, 'neovim/custom/ping'))
end)




it('does not start HTTP from start_all when HTTP remains on the default ephemeral port', function()
    local plugin = require('mcp')
    local http_server = require('mcp.http_server')

    plugin.setup({
        transport = 'socket',
        http_host = '127.0.0.1',
        http_port = 0,
    })

    local started, start_err = plugin.start_all()
    assert.is_true(started)
    assert.is_nil(start_err)

    local host, port = http_server.bound_address()
    assert.is_nil(host)
    assert.is_nil(port)

    plugin.reset()
end)

it('starts HTTP from start_all when an explicit HTTP port is configured', function()
    local plugin = require('mcp')
    local http_server = require('mcp.http_server')

    plugin.setup({
        transport = 'socket',
        http_host = '127.0.0.1',
        http_port = 8126,
    })

    local started, start_err = plugin.start_all()
    assert.is_true(started)
    assert.is_nil(start_err)

    local host, port = http_server.bound_address()
    assert.are.equal('127.0.0.1', host)
    assert.are.equal(8126, port)

    plugin.reset()
end)

it('starts only HTTP from start when HTTP transport is requested', function()
    local plugin = require('mcp')
    local server = require('mcp.server')
    local start_socket_calls = 0
    local original_socket_supported = vim.uv.new_pipe
    local original_start_socket = server.start_socket
    local original_start_http = server.start_http

    server.start_socket = function()
        start_socket_calls = start_socket_calls + 1
        return true, nil
    end

    server.start_http = function()
        return true, nil
    end

    vim.uv.new_pipe = function()
        return {
            bind2 = function()
                return 0
            end,
            close = function() end,
        }
    end

    local ok, err = xpcall(function()
        local started, start_err = plugin.start('http')
        assert.is_true(started)
        assert.is_nil(start_err)
        assert.are.equal(0, start_socket_calls)
    end, debug.traceback)

    server.start_http = original_start_http
    server.start_socket = original_start_socket
    vim.uv.new_pipe = original_socket_supported

    if not ok then
        error(err)
    end
end)

it('reuses an existing HTTP listener for repeated ephemeral-port starts', function()
    local plugin = require('mcp')
    local http_server = require('mcp.http_server')

    plugin.setup({
        transport = 'http',
        http_host = '127.0.0.1',
        http_port = 0,
    })

    local started, start_err = http_server.start()
    assert.is_true(started)
    assert.is_nil(start_err)

    local first_host, first_port = http_server.bound_address()
    assert.are.equal('127.0.0.1', first_host)
    assert.is_true(type(first_port) == 'number' and first_port > 0)

    started, start_err = http_server.start()
    assert.is_true(started)
    assert.is_nil(start_err)

    local second_host, second_port = http_server.bound_address()
    assert.are.equal(first_host, second_host)
    assert.are.equal(first_port, second_port)

    http_server.stop()
end)

it('restarts the HTTP listener only when the configured endpoint changes', function()
    local plugin = require('mcp')
    local http_server = require('mcp.http_server')

    local function started_endpoint(host, port)
        plugin.setup({
            transport = 'http',
            http_host = host,
            http_port = port,
        })

        local started, start_err = http_server.start()
        assert.is_true(started)
        assert.is_nil(start_err)

        local bound_host, bound_port = http_server.bound_address()
        assert.are.equal(host, bound_host)
        assert.are.equal(port, bound_port)
        return bound_host, bound_port
    end

    local first_host, first_port = started_endpoint('127.0.0.1', 8123)

    plugin.setup({
        transport = 'http',
        http_host = '127.0.0.1',
        http_port = 8123,
    })

    local started, start_err = http_server.start()
    assert.is_true(started)
    assert.is_nil(start_err)
    local same_host, same_port = http_server.bound_address()
    assert.are.equal(first_host, same_host)
    assert.are.equal(first_port, same_port)

    plugin.setup({
        transport = 'http',
        http_host = '127.0.0.1',
        http_port = 8124,
    })

    started, start_err = http_server.start()
    assert.is_true(started)
    assert.is_nil(start_err)
    local changed_host, changed_port = http_server.bound_address()
    assert.are.equal('127.0.0.1', changed_host)
    assert.are.equal(8124, changed_port)
    assert.are_not.equal(first_port, changed_port)

    plugin.reset()

    started_endpoint('127.0.0.1', 8125)

    plugin.setup({
        transport = 'http',
        http_host = '127.0.0.2',
        http_port = 8125,
    })

    started, start_err = http_server.start()
    assert.is_true(started)
    assert.is_nil(start_err)
    changed_host, changed_port = http_server.bound_address()
    assert.are.equal('127.0.0.2', changed_host)
    assert.are.equal(8125, changed_port)

    plugin.reset()
end)

it('closes the accepted startup probe client immediately', function()
    local http_server = require('mcp.http_server')
    local original_new_tcp = vim.uv.new_tcp
    local server_closed = false
    local probe_closed = false
    local accepted_client_closed = false
    local listen_callback
    local created = 0

    vim.uv.new_tcp = function()
        created = created + 1
        if created == 1 then
            return {
                bind = function()
                    return 0
                end,
                getsockname = function()
                    return { ip = '127.0.0.1', port = 9876 }
                end,
                listen = function(_, _, cb)
                    listen_callback = cb
                    return nil
                end,
                accept = function(_, client)
                    return 0
                end,
                is_closing = function()
                    return server_closed
                end,
                close = function()
                    server_closed = true
                end,
            }
        elseif created == 2 then
            return {
                connect = function(_, _, _, cb)
                    listen_callback(nil)
                    cb(nil)
                    return true
                end,
                is_closing = function()
                    return probe_closed
                end,
                close = function()
                    probe_closed = true
                end,
            }
        end

        return {
            is_closing = function()
                return accepted_client_closed
            end,
            close = function()
                accepted_client_closed = true
            end,
        }
    end

    local ok, err = http_server.start()

    vim.uv.new_tcp = original_new_tcp
    http_server.stop()

    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_true(accepted_client_closed)
end)

it('reports pending startup from fast-event contexts', function()
    local http_server = require('mcp.http_server')
    local original_in_fast_event = vim.in_fast_event

    vim.in_fast_event = function()
        return true
    end

    local ok, err = http_server.start()

    vim.in_fast_event = original_in_fast_event
    http_server.stop()

    assert.is_false(ok)
    assert.are.equal('http server startup pending', err)
end)

it('treats repeated start calls as idempotent while startup is pending', function()
    local http_server = require('mcp.http_server')
    local original_new_tcp = vim.uv.new_tcp
    local original_in_fast_event = vim.in_fast_event
    local listener_closed = false
    local probe_closed = false
    local pending_client_closed = false
    local created = 0

    vim.in_fast_event = function()
        return true
    end

    vim.uv.new_tcp = function()
        created = created + 1
        if created == 1 then
            return {
                bind = function()
                    return 0
                end,
                getsockname = function()
                    return { ip = '127.0.0.1', port = 9876 }
                end,
                listen = function()
                    return nil
                end,
                accept = function()
                    return 0
                end,
                is_closing = function()
                    return listener_closed
                end,
                close = function()
                    listener_closed = true
                end,
            }
        elseif created == 2 then
            return {
                connect = function()
                    return true
                end,
                is_closing = function()
                    return probe_closed
                end,
                close = function()
                    probe_closed = true
                end,
            }
        end

        return {
            is_closing = function()
                return pending_client_closed
            end,
            close = function()
                pending_client_closed = true
            end,
        }
    end

    local ok, err = http_server.start()
    assert.is_false(ok)
    assert.are.equal('http server startup pending', err)

    local ok_again, err_again = http_server.start()

    vim.uv.new_tcp = original_new_tcp
    vim.in_fast_event = original_in_fast_event
    http_server.stop()

    assert.is_true(ok_again)
    assert.is_nil(err_again)
    assert.is_false(pending_client_closed)
end)

it('reports asynchronous HTTP listen startup failures to the caller', function()
    local http_server = require('mcp.http_server')
    local original_new_tcp = vim.uv.new_tcp
    local listener_closed = false
    local probe_closed = false
    local listen_callback
    local created = 0

    vim.uv.new_tcp = function()
        created = created + 1
        if created == 1 then
            return {
                bind = function()
                    return 0
                end,
                getsockname = function()
                    return { ip = '127.0.0.1', port = 9876 }
                end,
                listen = function(_, _, cb)
                    listen_callback = cb
                    return nil
                end,
                is_closing = function()
                    return listener_closed
                end,
                close = function()
                    listener_closed = true
                end,
            }
        end

        return {
            connect = function(_, _, _, cb)
                cb('listen failed later')
                return true
            end,
            is_closing = function()
                return probe_closed
            end,
            close = function()
                probe_closed = true
            end,
        }
    end

    local ok, err = http_server.start()

    vim.uv.new_tcp = original_new_tcp
    http_server.stop()

    assert.is_false(ok)
    assert.are.equal('listen failed later', err)
    assert.is_true(listener_closed)
    assert.is_true(probe_closed)
    assert.is_not_nil(listen_callback)
end)


it('drains pending HTTP clients when the startup probe fails', function()
    local http_server = require('mcp.http_server')
    local original_new_tcp = vim.uv.new_tcp
    local listener_closed = false
    local probe_closed = false
    local pending_client_closed = false
    local listen_callback
    local created = 0

    vim.uv.new_tcp = function()
        created = created + 1
        if created == 1 then
            return {
                bind = function()
                    return 0
                end,
                getsockname = function()
                    return { ip = '127.0.0.1', port = 9876 }
                end,
                listen = function(_, _, cb)
                    listen_callback = cb
                    return nil
                end,
                accept = function()
                    return 0
                end,
                is_closing = function()
                    return listener_closed
                end,
                close = function()
                    listener_closed = true
                end,
            }
        elseif created == 2 then
            return {
                connect = function(_, _, _, cb)
                    listen_callback(nil)
                    listen_callback(nil)
                    cb('listen failed later')
                    return true
                end,
                is_closing = function()
                    return probe_closed
                end,
                close = function()
                    probe_closed = true
                end,
            }
        end

        return {
            is_closing = function()
                return pending_client_closed
            end,
            close = function()
                pending_client_closed = true
            end,
        }
    end

    local ok, err = http_server.start()

    vim.uv.new_tcp = original_new_tcp
    http_server.stop()

    assert.is_false(ok)
    assert.are.equal('listen failed later', err)
    assert.is_true(listener_closed)
    assert.is_true(probe_closed)
    assert.is_true(pending_client_closed)
end)

it('rebuilds built-in neovim server from fresh defaults across setup calls', function()
    local plugin = require('mcp')

    plugin.register_server({
        name = 'neovim',
        title = 'Custom Neovim',
        description = 'Custom description',
        tools = {
            custom = {
                ping = {
                    handler = function()
                        return { ok = true }
                    end,
                },
            },
        },
    })

    plugin.setup()

    plugin.register_server({
        name = 'neovim',
        title = 'Changed title',
        tools = {
            custom = {
                pong = {
                    handler = function()
                        return { ok = true }
                    end,
                },
            },
        },
    })

    plugin.setup({ enable_terminal_tools = true })

    local server = vim.iter(plugin.list_servers()):find(function(item)
        return item.name == 'neovim'
    end)
    local tool_names = vim.tbl_map(function(tool)
        return tool.namespaced_name or tool.name
    end, server.tools or {})

    assert.are.equal('Changed title', server.title)
    assert.are.equal('Built-in Neovim-local MCP capability surfaces.', server.description)
    assert.is_true(vim.tbl_contains(tool_names, 'custom/pong'))
    assert.is_false(vim.tbl_contains(tool_names, 'custom/ping'))
    assert.is_true(vim.tbl_contains(tool_names, 'editor/list_buffers'))
    assert.is_true(vim.tbl_contains(tool_names, 'terminal/create'))
end)

it('closes the tcp handle when HTTP bind fails', function()
    local http_server = require('mcp.http_server')
    local original_new_tcp = vim.uv.new_tcp
    local close_calls = 0
    local fake_server = {
        bind = function()
            return 1, 'bind failed'
        end,
        is_closing = function()
            return false
        end,
        close = function()
            close_calls = close_calls + 1
        end,
    }

    vim.uv.new_tcp = function()
        return fake_server
    end

    local ok, err = http_server.start()

    vim.uv.new_tcp = original_new_tcp
    http_server.stop()

    assert.is_false(ok)
    assert.are.equal('bind failed', err)
    assert.are.equal(1, close_calls)
end)

it('reports write success even if buffer reload warns', function()
    local io_mod = require('mcp.builtin.editor.io')
    local tmp = vim.fn.tempname()
    local bufnr = vim.api.nvim_create_buf(true, false)
    local original_reload_buffer = io_mod.reload_buffer

    vim.api.nvim_buf_set_name(bufnr, tmp)

    io_mod.reload_buffer = function(target)
        assert.are.equal(bufnr, target)
        return {
            code = -32000,
            message = 'reload failed',
        }
    end

    local result, err, warning = io_mod.write_file(tmp, 'hello world')
    local disk = table.concat(vim.fn.readfile(tmp), '\n')

    io_mod.reload_buffer = original_reload_buffer
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmp)

    assert.is_nil(err)
    assert.are.same({
        code = -32000,
        message = 'reload failed',
    }, warning)
    assert.are.equal(tmp, result.path)
    assert.is_true(result.reloaded_buffer)
    assert.are.equal('hello world', disk)
end)
