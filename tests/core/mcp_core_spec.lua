describe('mcp', function()
    before_each(function()
        require('ministry').reset()
    end)

    it('loads and exposes setup', function()
        local plugin = require('ministry')

        assert.are.equal('function', type(plugin.setup))
    end)

    it('registers namespaced logical servers and tools', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

        plugin.register_server({
            name = 'editor',
            tools = require('ministry.builtin.editor.tools').specs(),
        })

        local tools = plugin.list_tool_descriptors()
        local names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, tools)

        assert.is_true(vim.tbl_contains(names, 'editor/list_buffers'))
        assert.is_true(vim.tbl_contains(names, 'editor/read_buffer'))
    end)

    it('treats data-driven tool specs as leaf tools when flattening', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')
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
        local plugin = require('ministry')

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
        local plugin = require('ministry')
        plugin.register_server({
            name = 'editor',
        })

        local result, err = plugin.call_tool('editor/missing', {}, {})

        assert.is_nil(result)
        assert.is_not_nil(err)
        assert.are.equal(-32601, err.code)
    end)

    it('registers resources and prompts under the same logical server', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

        local response = plugin.handle_request('initialize', {
            protocolVersion = '2099-01-01',
        }, 11, {})

        assert.is_not_nil(response.error)
        assert.are.equal(-32602, response.error.code)
        assert.are.equal('Unsupported protocol version: 2099-01-01', response.error.message)
    end)

    it('passes through structured MCP tool results', function()
        local plugin = require('ministry')

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

    it('preserves warnings from direct tool dispatch', function()
        local plugin = require('ministry')
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
                        return { ok = true }, nil, warning
                    end,
                },
            },
        })

        local result, err, returned_warning = plugin.call_tool('editor/echo', {}, {})

        assert.is_nil(err)
        assert.are.same({ ok = true }, result)
        assert.are.same(warning, returned_warning)
    end)

    it('includes warnings for structured tools/call results without deep-copying nested values', function()
        local plugin = require('ministry')
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
                        },
                            nil,
                            warning
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
        local plugin = require('ministry')
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
                        },
                            nil,
                            warning
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
        local plugin = require('ministry')
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
        assert.are.equal('editor/buffer://{bufnr}', template_list.result.resourceTemplates[1].uriTemplate)
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

    it('reads the built-in workspace summary resource as structured json', function()
        local plugin = require('ministry')

        plugin.setup({})
        vim.cmd('enew')
        vim.bo.filetype = 'lua'
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'print("hi")' })

        local listed = plugin.handle_request('resources/list', {}, 70, {})
        local read = plugin.handle_request('resources/read', {
            uri = 'neovim/workspace://summary',
        }, 71, {})

        assert.is_nil(listed.error)
        assert.is_true(vim.iter(listed.result.resources):any(function(item)
            return item.namespaced_uri == 'neovim/workspace://summary'
        end))
        assert.is_nil(read.error)

        local payload = vim.json.decode(read.result.contents[1].text)

        assert.are.equal(vim.fn.getcwd(), payload.cwd)
        assert.are.equal(vim.api.nvim_get_current_buf(), payload.current_buffer.bufnr)
        assert.are.equal('lua', payload.current_buffer.filetype)
        assert.are.equal(1, payload.tabpages)
        assert.is_true(payload.windows >= 1)
        assert.is_true(payload.buffer_counts.valid >= 1)
        assert.is_true(payload.buffer_counts.listed >= 1)
        assert.is_nil(payload.current_buffer.lines)
    end)

    it('reads the built-in terminal summary resource without embedding output', function()
        local plugin = require('ministry')
        local cwd = vim.fn.tempname()

        vim.fn.mkdir(cwd, 'p')

        plugin.setup({ enable_terminal_tools = true })

        local created, created_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'printf', 'hello' },
            cwd = cwd,
        }, {})

        assert.is_nil(created_err)
        assert.is_not_nil(created)

        local read = plugin.handle_request('resources/read', {
            uri = 'neovim/terminals://list',
        }, 73, {})

        assert.is_nil(read.error)

        local payload = vim.json.decode(read.result.contents[1].text)
        local terminal = assert(payload.terminals[1])

        assert.are.equal(created.terminal_id, terminal.terminal_id)
        assert.are.same({ 'printf', 'hello' }, terminal.command)
        assert.are.equal(vim.fs.normalize(cwd), vim.fs.normalize(terminal.cwd))
        assert.is_true(type(terminal.completed) == 'boolean')
        assert.is_nil(terminal.stdout)
        assert.is_nil(terminal.stderr)
    end)

    it('lets a listed Ministry-owned terminal be released by its listed id', function()
        local plugin = require('ministry')

        plugin.setup({ enable_terminal_tools = true })

        local created, created_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'sleep', '5' },
        }, {})

        assert.is_nil(created_err)
        assert.is_not_nil(created)

        local read = plugin.handle_request('resources/read', {
            uri = 'neovim/terminals://list',
        }, 74, {})

        assert.is_nil(read.error)

        local payload = vim.json.decode(read.result.contents[1].text)
        local terminal = assert(payload.terminals[1])
        local released, released_err = plugin.call_tool('neovim/terminal/release', {
            terminal_id = terminal.terminal_id,
        }, {})

        assert.is_nil(released_err)
        assert.are.equal(created.terminal_id, terminal.terminal_id)
        assert.are.equal(created.terminal_id, released.terminal_id)
        assert.is_true(released.released)
    end)

    it('captures fresh freeform terminal-list data through list-provider callbacks', function()
        local plugin = require('ministry')

        plugin.setup({ enable_terminal_tools = true })

        local created, created_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'printf', 'hello' },
        }, {})

        assert.is_nil(created_err)
        assert.are.same(
            {
                list_name = 'terminals',
                owner = 'terminalia',
                registered = true,
            },
            plugin.register_list_item_data_provider('terminals', 'terminalia', function(item, item_id)
                if item_id ~= created.terminal_id then
                    return nil
                end

                return {
                    terminalia_context_stack = {
                        { id = 'context:host', kind = 'host', label = 'Host' },
                        { id = 'context:remote', kind = 'remote_workspace', label = 'Devbox' },
                        { id = item.terminal_id, kind = 'ministry_terminal', label = 'Tracked Terminal' },
                    },
                }
            end)
        )

        local read = plugin.handle_request('resources/read', {
            uri = 'neovim/terminals://list',
        }, 75, {})

        assert.is_nil(read.error)

        local payload = vim.json.decode(read.result.contents[1].text)
        local terminal = assert(payload.terminals[1])

        assert.are.equal(created.terminal_id, terminal.terminal_id)
        assert.are.same({
            { id = 'context:host', kind = 'host', label = 'Host' },
            { id = 'context:remote', kind = 'remote_workspace', label = 'Devbox' },
            { id = created.terminal_id, kind = 'ministry_terminal', label = 'Tracked Terminal' },
        }, terminal.terminalia_context_stack)
    end)

    it('captures fresh freeform buffer-list data through list-provider callbacks', function()
        local plugin = require('ministry')

        plugin.setup({})
        vim.cmd('enew')
        vim.bo.filetype = 'lua'

        local bufnr = vim.api.nvim_get_current_buf()
        local registered, register_err = plugin.register_list_item_data_provider('buffers', 'fixture', function(item)
            if item.bufnr ~= bufnr then
                return nil
            end

            return {
                fixture_metadata = {
                    owner = 'fixture',
                    scope = 'buffer-list',
                    filetype = item.filetype,
                },
            }
        end)

        assert.is_nil(register_err)
        assert.are.same({
            list_name = 'buffers',
            owner = 'fixture',
            registered = true,
        }, registered)

        local read = plugin.handle_request('resources/read', {
            uri = 'neovim/buffers://list',
        }, 76, {})

        assert.is_nil(read.error)

        local payload = vim.json.decode(read.result.contents[1].text)
        local matched = nil

        for _, buffer in ipairs(payload.buffers) do
            if buffer.bufnr == bufnr then
                matched = buffer
                break
            end
        end

        assert.are.same({
            owner = 'fixture',
            scope = 'buffer-list',
            filetype = 'lua',
        }, assert(matched).fixture_metadata)
    end)

    it('does not attach Terminalia context metadata unless it is explicitly provided', function()
        local plugin = require('ministry')

        plugin.setup({ enable_terminal_tools = true })

        local created, created_err = plugin.call_tool('neovim/terminal/create', {
            command = { 'printf', 'hello' },
        }, {})

        assert.is_nil(created_err)
        assert.is_not_nil(created)

        local read = plugin.handle_request('resources/read', {
            uri = 'neovim/terminals://list',
        }, 77, {})

        assert.is_nil(read.error)

        local payload = vim.json.decode(read.result.contents[1].text)
        local terminal = assert(payload.terminals[1])

        assert.are.equal(created.terminal_id, terminal.terminal_id)
        assert.is_nil(terminal.terminalia_context_stack)
    end)

    it('keeps the workspace summary resource lightweight and session-global', function()
        local plugin = require('ministry')
        local original_get_lines = vim.api.nvim_buf_get_lines
        local root = vim.fn.getcwd()
        local global_dir = vim.fn.tempname()
        local local_dir = vim.fn.tempname()

        vim.fn.mkdir(global_dir, 'p')
        vim.fn.mkdir(local_dir, 'p')
        plugin.setup({})
        vim.cmd('cd ' .. vim.fn.fnameescape(global_dir))
        vim.cmd('lcd ' .. vim.fn.fnameescape(local_dir))

        vim.api.nvim_buf_get_lines = function()
            error('workspace summary should not read full buffer contents')
        end

        local read = plugin.handle_request('resources/read', {
            uri = 'neovim/workspace://summary',
        }, 72, {})

        vim.api.nvim_buf_get_lines = original_get_lines
        vim.cmd('cd ' .. vim.fn.fnameescape(root))

        assert.is_nil(read.error)

        local payload = vim.json.decode(read.result.contents[1].text)

        assert.are.equal(vim.fs.normalize(global_dir), vim.fs.normalize(payload.cwd))
    end)

    it('normalizes scalar resource and prompt handler results', function()
        local plugin = require('ministry')

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
        assert.are.equal('scalar_prompt', prompt_get.result.name)
        assert.are.equal('9', prompt_get.result.messages[1].content.text)
    end)

    it('adds prompt metadata to normalized prompt results', function()
        local plugin = require('ministry')

        plugin.register_server({
            name = 'editor',
        })

        plugin.register_prompt('editor', {
            name = 'describe',
            description = 'Describe the current buffer.',
            handler = function()
                return {
                    messages = {
                        {
                            role = 'user',
                            content = {
                                type = 'text',
                                text = 'hello',
                            },
                        },
                    },
                }
            end,
        })

        local prompt_get = plugin.handle_request('prompts/get', {
            name = 'editor/describe',
        }, 29, {})

        assert.is_nil(prompt_get.error)
        assert.are.equal('describe', prompt_get.result.name)
        assert.are.equal('Describe the current buffer.', prompt_get.result.description)
        assert.are.equal('hello', prompt_get.result.messages[1].content.text)
    end)

    it('normalizes single resource content objects into a list', function()
        local plugin = require('ministry')

        plugin.register_server({
            name = 'editor',
        })

        plugin.register_resource('editor', {
            uri = 'buffer://single',
            handler = function()
                return {
                    contents = {
                        text = 'single',
                    },
                }
            end,
        })

        local resource_read = plugin.handle_request('resources/read', {
            uri = 'editor/buffer://single',
        }, 30, {})

        assert.is_nil(resource_read.error)
        assert.are.equal(1, #resource_read.result.contents)
        assert.are.equal('editor/buffer://single', resource_read.result.contents[1].uri)
        assert.are.equal('single', resource_read.result.contents[1].text)
    end)

    it('does not mutate handler-owned resource result tables when normalizing contents', function()
        local plugin = require('ministry')

        plugin.register_server({
            name = 'editor',
        })

        local cached_result = {
            contents = {
                text = 'single',
            },
        }

        plugin.register_resource('editor', {
            uri = 'buffer://cached',
            handler = function()
                return cached_result
            end,
        })

        local resource_read = plugin.handle_request('resources/read', {
            uri = 'editor/buffer://cached',
        }, 31, {})

        assert.is_nil(resource_read.error)
        assert.are.equal(1, #resource_read.result.contents)
        assert.is_false(vim.islist(cached_result.contents))
        assert.are.equal('single', cached_result.contents.text)
    end)

    it('prefers the longest matching server prefix for resources and prompts', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

        local response = plugin.handle_request('wat', {}, 13, {})

        assert.is_not_nil(response.error)
        assert.are.equal(-32601, response.error.code)
        assert.are.equal('Method not found: wat', response.error.message)
    end)

    it('returns tool dispatch failures from tools/call', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local registry = require('ministry.core.registry')
        local ambiguous_tool, ambiguous_err = registry.find_tool('workspace__sync')

        assert.is_true(vim.tbl_contains(names, 'alpha/workspace/sync'))
        assert.is_true(vim.tbl_contains(names, 'beta/workspace/sync'))
        assert.is_nil(ambiguous_tool)
        assert.matches('Ambiguous flattened tool name workspace__sync', ambiguous_err, 1, true)
        assert.matches('alpha/workspace/sync', ambiguous_err, 1, true)
        assert.matches('beta/workspace/sync', ambiguous_err, 1, true)
    end)

    it('accepts unique flattened tools/call names', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')
        local calls = 0

        plugin.register_server({
            name = 'neovim',
            tools = {
                editor = {
                    list_buffers = {
                        handler = function()
                            calls = calls + 1
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
        assert.are.equal(1, calls)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    ok = true,
                }),
            },
        }, call.result.content)
    end)

    it('prefers exact split tool names before flattened fallback', function()
        local plugin = require('ministry')
        local flat_calls = 0
        local nested_calls = 0

        plugin.register_server({
            name = 'neovim',
            tools = {
                ['foo__bar'] = {
                    handler = function()
                        flat_calls = flat_calls + 1
                        return {
                            tool = 'flat',
                        }
                    end,
                },
                foo = {
                    bar = {
                        handler = function()
                            nested_calls = nested_calls + 1
                            return {
                                tool = 'nested',
                            }
                        end,
                    },
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            server = 'neovim',
            tool = 'foo__bar',
        }, 7, {})

        assert.is_nil(call.error)
        assert.are.equal(1, flat_calls)
        assert.are.equal(0, nested_calls)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    tool = 'flat',
                }),
            },
        }, call.result.content)
    end)

    it('does not double-prefix split tools/call payloads whose tool is already qualified', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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

    it('rejects conflicting qualified and split tool identifiers', function()
        local plugin = require('ministry')

        plugin.register_server({
            name = 'alpha',
            tools = {
                x = {
                    handler = function()
                        return { ok = true }
                    end,
                },
            },
        })

        local call = plugin.handle_request('tools/call', {
            name = 'alpha/x',
            server = 'beta',
            tool = 'y',
            arguments = {},
        }, 7, {})

        assert.are.same({
            code = -32602,
            message = 'Conflicting tool identifiers',
        }, call.error)
    end)

    it('does not infer routing from tools/call arguments.server and arguments.tool', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
end)
