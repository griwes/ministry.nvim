describe('mcp', function()
    before_each(function()
        require('tests.helpers.ministry').reset()
    end)
    it('starts and stops the live server lifecycle', function()
        local plugin = require('ministry')

        local ok, err = plugin.start()

        assert.is_true(ok)
        assert.is_nil(err)
        assert.is_true(plugin.running())

        plugin.stop()

        assert.is_false(plugin.running())
    end)

    it('clears listener state when socket startup fails', function()
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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

    it('schedules socket JSON-RPC dispatch out of fast-event read callbacks', function()
        local plugin = require('ministry')
        local original_new_pipe = vim.uv.new_pipe
        local original_in_fast_event = vim.in_fast_event
        local original_schedule = vim.schedule
        local listener_read_cb
        local writes = {}
        local scheduled = {}
        local in_fast_event = true
        local listener_pipe = {
            bind2 = function()
                return 0
            end,
            listen = function(_, _, cb)
                listener_read_cb = cb
                return true
            end,
            accept = function()
                return true
            end,
            is_closing = function()
                return false
            end,
            close = function() end,
        }
        local client_closed = false
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

        vim.in_fast_event = function()
            return in_fast_event
        end
        vim.schedule = function(cb)
            table.insert(scheduled, cb)
        end
        vim.uv.new_pipe = function()
            pipe_count = pipe_count + 1
            if pipe_count == 1 then
                return listener_pipe
            end

            return client_pipe
        end

        local ok, err = pcall(function()
            require('tests.helpers.ministry').setup(plugin, { auto_start = false })

            assert.is_true(plugin.start())
            listener_read_cb(nil)

            client_pipe._read_cb(nil, vim.json.encode({
                jsonrpc = '2.0',
                id = 1,
                method = 'resources/read',
                params = {
                    uri = 'neovim/buffers://list',
                },
            }) .. '\n')

            assert.are.equal(0, #writes)
            assert.are.equal(1, #scheduled)

            in_fast_event = false
            scheduled[1]()

            assert.are.equal(1, #writes)
            assert.is_nil(writes[1].error)
            assert.are.equal(1, writes[1].id)
            assert.is_true(writes[1].result.contents[1].text:find('"buffers"', 1, true) ~= nil)
        end)

        plugin.stop()
        vim.uv.new_pipe = original_new_pipe
        vim.in_fast_event = original_in_fast_event
        vim.schedule = original_schedule

        if not ok then
            error(err)
        end
    end)

    it('clears buffered malformed HTTP payloads before closing the client', function()
        local http_server = require('ministry.transport.http.server')
        local sent_response
        local client_closed = false
        local client
        client = {
            _mcp_http_buffer = nil,
            read_start = function(_, cb)
                client._read_cb = cb
                return true
            end,
            read_stop = function() end,
            is_closing = function()
                return client_closed
            end,
            write = function(_, payload, cb)
                local body = payload:match('\r\n\r\n(.*)$')
                sent_response = vim.json.decode(body)
                if cb ~= nil then
                    cb()
                end
            end,
            close = function()
                client_closed = true
            end,
        }

        http_server._start_client_read(client, nil)
        client._read_cb(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                'Content-Length: 10',
                '',
                '{bad json}',
            }, '\r\n')
        )

        assert.is_not_nil(sent_response)
        assert.are.equal(-32700, sent_response.error.code)
        assert.are.equal('', client._mcp_http_buffer)
        assert.is_false(client_closed)
    end)

    it('registers the built-in editor server during setup', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = true })

        local servers = plugin.list_servers()
        local tools = plugin.list_tool_descriptors()
        local resources = plugin.list_resource_descriptors()
        local resource_templates = plugin.list_resource_template_descriptors()
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
        local resource_template_names = vim.tbl_map(function(resource_template)
            return resource_template.namespaced_uri_template
        end, resource_templates)
        local prompt_names = vim.tbl_map(function(prompt)
            return prompt.namespaced_name
        end, prompts)

        local listed, listed_err = plugin.call_tool('neovim/editor/list_buffers', {}, {})

        assert.is_nil(listed_err)
        assert.is_true(vim.tbl_contains(server_names, 'neovim'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
        assert.is_false(vim.tbl_contains(tool_names, 'neovim/editor/read_current_buffer'))
        assert.is_false(vim.tbl_contains(tool_names, 'neovim/editor/diff_current_buffer'))
        assert.is_false(vim.tbl_contains(tool_names, 'neovim/editor/write_current_buffer'))
        assert.is_false(vim.tbl_contains(tool_names, 'neovim/editor/apply_diff_current_buffer'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/editor/list_buffers'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/editor/open_buffer'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/list_diagnostics'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/code_actions'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/document_symbols'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/workspace_symbols'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/definitions'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/rename'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/dap/continue'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/dap/pause'))
        assert.is_false(vim.tbl_contains(resource_names, 'neovim/buffer://current'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/buffers://list'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/workspace://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/tasks://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/lsp://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/dap://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/dap://breakpoints'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/dap://threads'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/coverage://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/formatting://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/lint://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/mason://inventory'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/navigation://marks'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/quickfix://summary'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/location-list://current'))
        assert.is_true(vim.tbl_contains(resource_template_names, 'neovim/dap://stack/{thread_id}'))
        assert.is_true(vim.tbl_contains(resource_template_names, 'neovim/dap://scopes/{frame_id}'))
        assert.is_true(vim.tbl_contains(resource_template_names, 'neovim/dap://variables/{variables_reference}'))
        assert.is_true(vim.tbl_contains(resource_names, 'neovim/terminals://list'))
        assert.are.same({}, prompt_names)
        assert.are.equal(1, #listed.buffers)
        assert.are.equal(1, listed.buffers[1].bufnr)
        assert.is_table(listed.buffers[1].lines)
    end)

    it('advertises terminal tools when explicitly enabled', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = true })

        local tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_true(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
    end)

    it('does not advertise terminal tools by default', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin)

        local tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())
        local resource_names = vim.tbl_map(function(resource)
            return resource.namespaced_uri
        end, plugin.list_resource_descriptors())

        assert.is_false(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
        assert.is_false(vim.tbl_contains(resource_names, 'neovim/terminals://list'))
    end)

    it('registers and unregisters server guidance without surfacing it as an MCP prompt', function()
        local plugin = require('ministry')

        plugin.register_server({
            name = 'custom',
            tools = {},
        })

        plugin.register_server_guidance('custom', {
            'CUSTOM GUIDANCE',
            'SECOND BLOCK',
        })

        assert.are.same({
            {
                server = 'custom',
                guidance = 'CUSTOM GUIDANCE\n\nSECOND BLOCK',
            },
        }, plugin.list_server_guidance())
        assert.are.equal('CUSTOM GUIDANCE\n\nSECOND BLOCK', plugin.server_guidance('custom'))
        assert.are.same({}, plugin.list_prompt_descriptors())

        plugin.unregister_server_guidance('custom')

        assert.are.same({}, plugin.list_server_guidance())
        assert.is_nil(plugin.server_guidance('custom'))
    end)

    it('owns built-in Neovim MCP routing guidance', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = true })

        local guidance = plugin.server_guidance('neovim', {
            agent_capabilities = {
                mcpCapabilities = {
                    tools = {
                        listChanged = true,
                    },
                    resources = {
                        listChanged = true,
                    },
                },
            },
        })

        assert.is_true(guidance:find('MCP server `neovim` before shell', 1, true) ~= nil)
        assert.is_true(guidance:find('Mandatory Neovim MCP routing contract', 1, true) ~= nil)
        assert.is_true(guidance:find('Do not start editor tasks with `pwd`, `rg`', 1, true) ~= nil)
        assert.is_true(guidance:find('generic patch/edit mechanisms are fallback paths', 1, true) ~= nil)
        assert.is_true(guidance:find('neovim/buffers://list', 1, true) ~= nil)
        assert.is_true(guidance:find('neovim/workspace://summary', 1, true) ~= nil)
        assert.is_true(guidance:find('neovim/editor/list_buffers', 1, true) ~= nil)
        assert.is_true(guidance:find('neovim/editor/open_buffer', 1, true) ~= nil)
        assert.is_true(guidance:find('without taking over a user window', 1, true) ~= nil)
        assert.is_true(guidance:find('open in a split', 1, true) ~= nil)
        assert.is_true(
            guidance:find('the first editor-targeting MCP action should be `neovim/editor/list_buffers`', 1, true)
                ~= nil
        )
        assert.is_true(guidance:find('the focused buffer may be the ACP/Legate chat surface', 1, true) ~= nil)
        assert.is_true(guidance:find('neovim/editor/diff_file', 1, true) ~= nil)
        assert.is_true(guidance:find('neovim/terminal/wait', 1, true) ~= nil)
        assert.is_true(guidance:find('tool path `editor/...`, `terminal/...`, `git/...`, or `dap/...`', 1, true) ~= nil)
        assert.is_false(guidance:find('editor__list_buffers', 1, true) ~= nil)
        assert.is_false(guidance:find('terminal__wait', 1, true) ~= nil)
        assert.are.same({}, plugin.list_prompt_descriptors())
    end)

    it('filters built-in Neovim guidance by advertised MCP capability family', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = true })

        local resources_guidance = plugin.server_guidance('neovim', {
            agent_capabilities = {
                mcpCapabilities = {
                    resources = {
                        listChanged = true,
                    },
                },
            },
        })
        local tools_guidance = plugin.server_guidance('neovim', {
            agent_capabilities = {
                mcpCapabilities = {
                    tools = {
                        listChanged = true,
                    },
                },
            },
        })

        assert.is_true(resources_guidance:find('neovim/workspace://summary', 1, true) ~= nil)
        assert.is_true(resources_guidance:find('neovim/git://overview', 1, true) ~= nil)
        assert.is_false(resources_guidance:find('neovim/editor/diff_file', 1, true) ~= nil)
        assert.is_false(resources_guidance:find('tool path `editor/...`', 1, true) ~= nil)

        assert.is_true(tools_guidance:find('neovim/editor/list_buffers', 1, true) ~= nil)
        assert.is_true(tools_guidance:find('neovim/git/overview', 1, true) ~= nil)
        assert.is_false(tools_guidance:find('neovim/workspace://summary', 1, true) ~= nil)
        assert.is_false(tools_guidance:find('neovim/git://overview', 1, true) ~= nil)
    end)

    it('emits built-in Neovim guidance when MCP capabilities are unknown', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin)

        local guidance = plugin.server_guidance('neovim', {
            agent_capabilities = {
                promptCapabilities = {
                    image = true,
                },
            },
        })

        assert.is_true(guidance:find('neovim/editor/list_buffers', 1, true) ~= nil)
        assert.is_true(guidance:find('neovim/editor/diff_file', 1, true) ~= nil)
        assert.is_true(guidance:find('apply_diff_file` with explicit generated `hunks`', 1, true) ~= nil)
        assert.is_true(guidance:find('only when you need Ministry to compute hunks', 1, true) ~= nil)
        assert.is_true(guidance:find('do not pass whole-file content to apply_diff tools', 1, true) ~= nil)
    end)

    it('suppresses built-in Neovim guidance for explicit empty MCP capabilities', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin)

        assert.is_nil(plugin.server_guidance('neovim', {
            agent_capabilities = {
                mcpCapabilities = {},
            },
        }))
        assert.are.same(
            {},
            plugin.list_server_guidance({
                agent_capabilities = {
                    mcpCapabilities = {},
                },
            })
        )
    end)

    it('drops built-in terminal tools when setup disables them after enabling', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = true })
        require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = false })

        local tool_names = vim.tbl_map(function(tool)
            return tool.namespaced_name
        end, plugin.list_tool_descriptors())

        assert.is_false(vim.tbl_contains(tool_names, 'neovim/terminal/create'))
        assert.is_true(vim.tbl_contains(tool_names, 'neovim/editor/list_buffers'))
    end)

    it('merges built-ins into an existing neovim server during setup', function()
        local plugin = require('ministry')
        local builtin_editor = require('ministry.builtin.editor.init')
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
                guidance = 'CUSTOM NEOVIM GUIDANCE',
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

            require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = true })
            require('tests.helpers.ministry').setup(plugin, { enable_terminal_tools = true })

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
            assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/list_diagnostics'))
            assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/code_actions'))
            assert.is_true(vim.tbl_contains(tool_names, 'neovim/lsp/rename'))
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
                    return name == 'neovim/lsp/list_diagnostics'
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
            assert.is_true(vim.tbl_contains(resource_names, 'neovim/lsp://summary'))
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/custom://status'
                end, resource_names))
            )
            assert.are.equal(
                1,
                vim.tbl_count(vim.tbl_filter(function(name)
                    return name == 'neovim/lsp://summary'
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
            assert.are.equal('CUSTOM NEOVIM GUIDANCE', plugin.server_guidance('neovim'))
            assert.are.same({
                {
                    server = 'neovim',
                    guidance = 'CUSTOM NEOVIM GUIDANCE',
                },
            }, plugin.list_server_guidance())
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
        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin, {
            socket_prefix = 'invoke_mcp',
            bridge_command = 'socat',
        })

        local invocation = plugin.endpoint_invocation()
        local endpoint = plugin.endpoint()

        assert.are.equal('socat', invocation.command)
        assert.are.same({ '-', 'UNIX-CONNECT:' .. endpoint.socket_name }, invocation.args)
    end)

    it('describes an HTTP endpoint when configured', function()
        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin, {
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 8877,
        })

        local endpoint = plugin.endpoint()

        assert.are.equal('http', endpoint.transport)
        assert.are.equal('http://127.0.0.1:8877/mcp', endpoint.url)
        assert.are.equal(8877, endpoint.http_port)
    end)

    it('advertises HTTP bearer auth in the invocation descriptor', function()
        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin, {
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 8877,
            http_token = 'secret-token',
        })

        local invocation = plugin.endpoint_invocation()
        local endpoint = plugin.endpoint()

        assert.are.equal('secret-token', endpoint.http_token)
        assert.are.same({
            url = 'http://127.0.0.1:8877/mcp',
            headers = {
                Authorization = 'Bearer secret-token',
            },
        }, invocation)
    end)

    it('brackets IPv6 hosts in advertised HTTP endpoints', function()
        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin, {
            transport = 'http',
            http_host = '::1',
            http_port = 8877,
        })

        local endpoint = plugin.endpoint()

        assert.are.equal('http://[::1]:8877/mcp', endpoint.url)
    end)

    it('does not advertise a concrete HTTP port before startup binds an ephemeral port', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')

        local endpoint = nil
        local invocation = nil
        local ok, err = xpcall(function()
            require('tests.helpers.ministry').setup(plugin, {
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
            })

            http_server.stop()
            endpoint = plugin.endpoint()
            invocation = plugin.endpoint_invocation()
        end, debug.traceback)

        require('tests.helpers.ministry').reset(plugin)

        if not ok then
            error(err)
        end

        assert.are.equal('http', endpoint.transport)
        assert.is_nil(endpoint.url)
        assert.are.equal(0, endpoint.http_port)
        assert.are.same({}, invocation)
    end)

    it('restores defaults for omitted config on repeated setup calls', function()
        local plugin = require('ministry')

        require('tests.helpers.ministry').setup(plugin, {
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 8877,
            enable_terminal_tools = true,
        })

        require('tests.helpers.ministry').setup(plugin, {
            http_host = '127.0.0.2',
        })

        local endpoint = plugin.endpoint()
        local config = require('ministry.core.config').get()

        assert.are.equal('socket', config.transport)
        assert.are.equal('127.0.0.2', config.http_host)
        assert.are.equal(0, config.http_port)
        assert.is_false(config.enable_terminal_tools)
        assert.are.equal('socket', endpoint.transport)
    end)

    it('starts the configured HTTP transport during setup by default', function()
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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
            require('tests.helpers.ministry').setup(plugin, {
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
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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
            require('tests.helpers.ministry').setup(plugin, {
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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
            require('tests.helpers.ministry').setup(plugin, { transport = 'socket' })

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
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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
            require('tests.helpers.ministry').setup(plugin, { transport = 'socket' })

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
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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
            require('tests.helpers.ministry').setup(plugin, { transport = 'socket' })

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
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
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
            require('tests.helpers.ministry').setup(plugin, {
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

    it('stops only the listener owned by setup when auto-start is disabled later', function()
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
        local original_new_pipe = vim.uv.new_pipe
        local original_start = server.start
        local original_stop_transport = server.stop_transport
        local original_transport_running = server.transport_running
        local running = {
            http = false,
            socket = false,
        }
        local stopped = {}

        vim.uv.new_pipe = function()
            return {
                bind2 = function() end,
                close = function() end,
            }
        end
        server.start = function(transport)
            running[transport] = true
            return true, nil
        end
        server.stop_transport = function(transport)
            running[transport] = false
            table.insert(stopped, transport)
        end
        server.transport_running = function(transport)
            return running[transport]
        end

        local ok, err = xpcall(function()
            require('tests.helpers.ministry').setup(plugin, {
                auto_start = true,
                transport = 'socket',
            })
            local started, start_err = plugin.start('http')
            require('tests.helpers.ministry').setup(plugin, {
                auto_start = false,
                transport = 'socket',
            })

            assert.is_true(started)
            assert.is_nil(start_err)
            assert.are.same({ 'socket' }, stopped)
            assert.is_false(running.socket)
            assert.is_true(running.http)
        end, debug.traceback)

        server.transport_running = original_transport_running
        server.stop_transport = original_stop_transport
        server.start = original_start
        vim.uv.new_pipe = original_new_pipe

        if not ok then
            error(err)
        end
    end)

    it('uses the configured transport for default start and endpoint invocation', function()
        local plugin = require('ministry')
        local server = require('ministry.transport.server')
        local start_calls = {}
        local original_start = server.start

        require('tests.helpers.ministry').setup(plugin, {
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
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')

        require('tests.helpers.ministry').setup(plugin, {
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

        require('tests.helpers.ministry').reset(plugin)

        if not ok then
            error(err)
        end
    end)

    it('exposes the active HTTP endpoint after start', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')

        require('tests.helpers.ministry').setup(plugin, {
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

        require('tests.helpers.ministry').reset(plugin)

        if not ok then
            error(err)
        end
    end)

    it('stops the HTTP server during reset', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')

        require('tests.helpers.ministry').setup(plugin, {
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 0,
        })

        local started, start_err = plugin.start('http')
        assert.is_true(started)
        assert.is_nil(start_err)
        assert.is_not_nil(plugin.http_endpoint())

        require('tests.helpers.ministry').reset(plugin)

        assert.is_nil(plugin.http_endpoint())
        local host, port = http_server.bound_address()
        assert.is_nil(host)
        assert.is_nil(port)
    end)

    it('validates resources during server registration', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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

    it('schedules JSON-RPC dispatch out of fast-event HTTP read callbacks', function()
        local http_server = require('ministry.transport.http.server')
        local original_in_fast_event = vim.in_fast_event
        local original_schedule = vim.schedule
        local in_fast_event = true
        local scheduled = {}
        local writes = {}
        local callback
        local body = '{"jsonrpc":"2.0","id":1,"method":"ping"}'
        local request = table.concat({
            'POST /mcp HTTP/1.1',
            'Host: 127.0.0.1',
            'Content-Type: application/json',
            string.format('Content-Length: %d', #body),
            '',
            body,
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

        vim.in_fast_event = function()
            return in_fast_event
        end
        vim.schedule = function(cb)
            table.insert(scheduled, cb)
        end

        local ok, err = pcall(function()
            http_server._start_client_read(client)
            callback(nil, request)

            assert.are.equal(0, #writes)
            assert.are.equal(1, #scheduled)

            in_fast_event = false
            scheduled[1]()

            assert.are.equal(1, #writes)
            assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
            assert.truthy(writes[1]:find('"id":1', 1, true) ~= nil)
        end)

        vim.in_fast_event = original_in_fast_event
        vim.schedule = original_schedule

        if not ok then
            error(err)
        end
    end)

    it('preserves additional pipelined requests buffered before scheduled dispatch resumes', function()
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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
                'Content-Type: application/json',
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
        local http_server = require('ministry.transport.http.server')
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
                'Content-Type: application/json',
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
        local http_server = require('ministry.transport.http.server')
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
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content-Length: 0', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Connection: keep-alive', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Methods: POST, OPTIONS', 1, true) ~= nil)
    end)

    it('includes Content-Length: 0 for direct 204 responses on keep-alive connections', function()
        local send_response = require('ministry.transport.http.server')._send_response
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
        assert.truthy(writes[1]:find('Content-Length: 0', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Connection: keep-alive', 1, true) ~= nil)
        assert.are.equal('HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n', writes[1])
    end)

    it('drops response bodies for direct 204 responses', function()
        local send_response = require('ministry.transport.http.server')._send_response
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
        assert.are.equal('HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n', writes[1])
    end)

    it('returns 204 No Content for notification-only JSON-RPC batches over HTTP', function()
        local http_server = require('ministry.transport.http.server')
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
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Content-Length: 0', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Connection: keep-alive', 1, true) ~= nil)
        assert.falsy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Access-Control-Allow-Methods: POST, OPTIONS', 1, true) ~= nil)
    end)

    it('responds to OPTIONS /mcp even when the Accept header is unsupported', function()
        local http_server = require('ministry.transport.http.server')
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
                'Origin: http://localhost:3000',
                'Access-Control-Request-Method: POST',
                'Content-Length: 0',
                '',
                '',
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
        assert.falsy(writes[1]:find('unsupported accept header', 1, true) ~= nil)
    end)

    it('responds to OPTIONS /mcp preflight requests with CORS headers', function()
        local http_server = require('ministry.transport.http.server')
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
        assert.truthy(
            writes[1]:find('Access-Control-Allow-Headers: Authorization, Content-Type, Accept', 1, true) ~= nil
        )
    end)

    it('accepts unauthenticated OPTIONS /mcp browser preflight requests when an HTTP token is configured', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local writes = {}
        local callback
        local original_config = vim.deepcopy(plugin.config)

        require('tests.helpers.ministry').setup(plugin, {
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 0,
            http_token = 'secret-token',
        })

        local ok, err = xpcall(function()
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
                    'Origin: http://127.0.0.1:3000',
                    'Access-Control-Request-Method: POST',
                    'Access-Control-Request-Headers: Authorization, Content-Type',
                    'Content-Length: 0',
                    '',
                    '',
                }, '\r\n')
            )

            assert.are.equal(1, #writes)
            assert.truthy(writes[1]:find('HTTP/1.1 204 No Content', 1, true) ~= nil)
            assert.falsy(writes[1]:find('WWW-Authenticate: Bearer', 1, true) ~= nil)
            assert.truthy(writes[1]:find('Access-Control-Allow-Origin: http://127.0.0.1:3000', 1, true) ~= nil)
            assert.truthy(
                writes[1]:find('Access-Control-Allow-Headers: Authorization, Content-Type, Accept', 1, true) ~= nil
            )
        end, function(message)
            return debug.traceback(message, 2)
        end)

        require('tests.helpers.ministry').setup(plugin, original_config)
        if not ok then
            error(err)
        end
    end)

    it('rejects unauthenticated non-preflight OPTIONS /mcp requests when an HTTP token is configured', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local writes = {}
        local callback
        local original_config = vim.deepcopy(plugin.config)

        require('tests.helpers.ministry').setup(plugin, {
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 0,
            http_token = 'secret-token',
        })

        local ok, err = xpcall(function()
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
                    'Content-Length: 0',
                    '',
                    '',
                }, '\r\n')
            )

            assert.are.equal(1, #writes)
            assert.truthy(writes[1]:find('HTTP/1.1 401 Unauthorized', 1, true) ~= nil)
            assert.truthy(writes[1]:find('WWW-Authenticate: Bearer', 1, true) ~= nil)
        end, function(message)
            return debug.traceback(message, 2)
        end)

        require('tests.helpers.ministry').setup(plugin, original_config)
        if not ok then
            error(err)
        end
    end)

    it(
        'rejects unauthenticated OPTIONS /mcp requests with non-POST access-control-request-method when an HTTP token is configured',
        function()
            local plugin = require('ministry')
            local http_server = require('ministry.transport.http.server')
            local writes = {}
            local callback
            local original_config = vim.deepcopy(plugin.config)

            require('tests.helpers.ministry').setup(plugin, {
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
                http_token = 'secret-token',
            })

            local ok, err = xpcall(function()
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
                        'Origin: http://127.0.0.1:3000',
                        'Access-Control-Request-Method: GET',
                        'Content-Length: 0',
                        '',
                        '',
                    }, '\r\n')
                )

                assert.are.equal(1, #writes)
                assert.truthy(writes[1]:find('HTTP/1.1 401 Unauthorized', 1, true) ~= nil)
                assert.truthy(writes[1]:find('WWW-Authenticate: Bearer', 1, true) ~= nil)
            end, function(message)
                return debug.traceback(message, 2)
            end)

            require('tests.helpers.ministry').setup(plugin, original_config)
            if not ok then
                error(err)
            end
        end
    )

    it(
        'rejects forged unauthenticated OPTIONS /mcp preflight headers when an Authorization header is present',
        function()
            local plugin = require('ministry')
            local http_server = require('ministry.transport.http.server')
            local writes = {}
            local callback
            local original_config = vim.deepcopy(plugin.config)

            require('tests.helpers.ministry').setup(plugin, {
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
                http_token = 'secret-token',
            })

            local ok, err = xpcall(function()
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
                        'Origin: http://127.0.0.1:3000',
                        'Access-Control-Request-Method: POST',
                        'Authorization: Bearer forged-token',
                        'Content-Length: 0',
                        '',
                        '',
                    }, '\r\n')
                )

                assert.are.equal(1, #writes)
                assert.truthy(writes[1]:find('HTTP/1.1 401 Unauthorized', 1, true) ~= nil)
                assert.truthy(writes[1]:find('WWW-Authenticate: Bearer', 1, true) ~= nil)
            end, function(message)
                return debug.traceback(message, 2)
            end)

            require('tests.helpers.ministry').setup(plugin, original_config)
            if not ok then
                error(err)
            end
        end
    )

    it('does not reflect non-local origins on successful MCP responses', function()
        local http_server = require('ministry.transport.http.server')
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
        assert.falsy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) ~= nil)
        assert.truthy(writes[1]:find('Vary: Origin', 1, true) ~= nil)
    end)

    it('allows localhost origins only for loopback hosts', function()
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
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

        require('tests.helpers.ministry').setup(plugin, {
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
        local http_server = require('ministry.transport.http.server')
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

    it('allows arbitrary loopback origins only for wildcard or localhost listeners', function()
        local http_server = require('ministry.transport.http.server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 12,
            method = 'ping',
        })
        local cases = {
            {
                host = '127.0.0.2',
                origin = 'https://localhost:3000',
                allowed = false,
            },
            {
                host = '127.0.0.2',
                origin = 'https://127.0.0.2:3000',
                allowed = true,
            },
            {
                host = '[::1]',
                origin = 'http://[::ffff:127.0.0.2]:3000',
                allowed = false,
            },
            {
                host = '[::1]',
                origin = 'http://[::ffff:7f00:2]:3000',
                allowed = false,
            },
            {
                host = '127.0.0.2',
                origin = 'http://[::ffff:127.0.0.2]:3000',
                allowed = false,
            },
            {
                host = '127.0.0.2',
                origin = 'http://[::ffff:7f00:2]:3000',
                allowed = false,
            },
            {
                host = '0.0.0.0',
                origin = 'https://localhost:3000',
                allowed = true,
            },
            {
                host = '[::]',
                origin = 'http://[::ffff:127.0.0.2]:3000',
                allowed = true,
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
            if case.allowed then
                assert.truthy(writes[1]:find('Access-Control-Allow-Origin: ' .. case.origin, 1, true) ~= nil)
            else
                assert.falsy(writes[1]:find('Access-Control-Allow-Origin: ' .. case.origin, 1, true) ~= nil)
            end
        end
    end)

    it('reflects origins that match the configured non-loopback host', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
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

        require('tests.helpers.ministry').setup(plugin, {
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
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
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

        require('tests.helpers.ministry').setup(plugin, {
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

    it('does not reflect scoped IPv6 origins with RFC 6874 zone identifiers for unscoped bound hosts', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 15,
            method = 'ping',
        })
        local writes = {}
        local callback
        local origin = 'http://[fe80::1%25lo0]:3000'
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

        require('tests.helpers.ministry').setup(plugin, {
            transport = {
                type = 'http',
                http = {
                    host = 'fe80::1',
                    port = 0,
                },
            },
        })

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: [fe80::1]',
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
    end)

    it('does not reflect different scoped IPv6 origins for specifically bound hosts', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local body = vim.json.encode({
            jsonrpc = '2.0',
            id = 16,
            method = 'ping',
        })
        local writes = {}
        local callback
        local origin = 'http://[fe80::2%25lo0]:3000'
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

        require('tests.helpers.ministry').setup(plugin, {
            transport = {
                type = 'http',
                http = {
                    host = 'fe80::1',
                    port = 0,
                },
            },
        })

        http_server._start_client_read(client)
        callback(
            nil,
            table.concat({
                'POST /mcp HTTP/1.1',
                'Host: [fe80::1]',
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
    end)
    it('does not emit allow-origin for invalid Origin header values', function()
        local http_server = require('ministry.transport.http.server')
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
            'https://[fe80::1%lo0]:443',
            'https://[fe80::1%25]:443',
            'https://[fe80::1%25lo/0]:443',
            'https://[::ffff:999.1.1.1]:443',
            'https://[2001:db8:192.168.0.1]:443',
            'https://[127.0.0.1]',
            'https://example.com:',
            'https://[::1]:',
            'http://foo:bar:80',
            'https://foo:bar:443',
        }) do
            request_with_origin(origin)
        end
    end)

    it('rejects empty JSON-RPC batches as invalid requests', function()
        local http_server = require('ministry.transport.http.server')
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
                'Content-Type: application/json',
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
        local http_server = require('ministry.transport.http.server')
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
                'Content-Type: application/json',
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
    end)

    it('rejects text/event-stream when json is not accepted', function()
        local http_server = require('ministry.transport.http.server')
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
        assert.truthy(writes[1]:find('HTTP/1.1 406 Not Acceptable', 1, true) ~= nil)
    end)

    it('ignores optional text/event-stream when json is also accepted', function()
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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

    it('prefers the highest ranked supported response content type', function()
        local http_server = require('ministry.transport.http.server')
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

    it('prefers q over specificity when choosing between response content types', function()
        local http_server = require('ministry.transport.http.server')
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

    it('prefers a more specific accept match over a higher-q wildcard for the same candidate', function()
        local http_server = require('ministry.transport.http.server')
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

    it('prefers the most specific accept match before header order', function()
        local http_server = require('ministry.transport.http.server')
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

    it('accepts wildcard fallback when a specific accept entry has q=0', function()
        local http_server = require('ministry.transport.http.server')
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
        assert.truthy(writes[1]:find('Content-Type: application/json', 1, true) ~= nil)
    end)

    it('prefers more specific accept entries over higher q wildcards', function()
        local http_server = require('ministry.transport.http.server')
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
        assert.truthy(writes[1]:find('Content-Type: application/json', 1, true) ~= nil)
    end)

    it('preserves accept header order for equally ranked content types', function()
        local http_server = require('ministry.transport.http.server')
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

    it('accepts structured +json media ranges for JSON responses', function()
        local http_server = require('ministry.transport.http.server')
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

    it('rejects folded headers as malformed requests', function()
        local http_server = require('ministry.transport.http.server')
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
                'Content-Length: 47',
                ' 47',
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"code":-32700', 1, true) ~= nil)
        assert.truthy(writes[1]:find('invalid folded header', 1, true) ~= nil)
    end)

    it('rejects non-decimal content-length values', function()
        local http_server = require('ministry.transport.http.server')
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
                'Content-Length: 1e3',
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"code":-32700', 1, true) ~= nil)
    end)

    it('accepts identical duplicate content-length headers', function()
        local http_server = require('ministry.transport.http.server')
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
                string.format('Content-Length: %d', #body),
                '',
                body,
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
    end)

    it('rejects conflicting duplicate content-length headers', function()
        local http_server = require('ministry.transport.http.server')
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
        assert.are.equal(1, #writes)
        local response = table.concat(writes)
        assert.truthy(response:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(response:find('"code":-32700', 1, true) ~= nil)
        assert.truthy(response:find('ambiguous content%-length', 1) ~= nil)
    end)

    it('accepts requests that use bare LF header framing', function()
        local http_server = require('ministry.transport.http.server')
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

    it('rejects requests that mix CRLF and LF framing', function()
        local http_server = require('ministry.transport.http.server')
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
                'Host: 127.0.0.1\r',
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
        assert.truthy(writes[1]:find('"code":-32700', 1, true) ~= nil)
        assert.truthy(writes[1]:find('invalid http framing', 1, true) ~= nil)
    end)

    it('rejects duplicate content-type headers', function()
        local http_server = require('ministry.transport.http.server')
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
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('"code":-32700', 1, true) ~= nil)
        assert.truthy(writes[1]:find('duplicate content%-type', 1) ~= nil)
    end)

    it('combines repeated accept headers before content negotiation', function()
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')
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
        assert.truthy(writes[1]:find('HTTP/1.0 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('invalid content%-length') ~= nil)
    end)

    it('uses the standard reason phrase for HTTP 505 responses', function()
        local http_server = require('ministry.transport.http.server')

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
        local http_server = require('ministry.transport.http.server')

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

        assert.truthy(transfer_encoding_only:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(transfer_encoding_only:find('"code":-32700', 1, true) ~= nil)
        assert.truthy(transfer_encoding_only:find('unsupported transfer-encoding', 1, true) ~= nil)
        assert.truthy(both_headers:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(both_headers:find('"code":-32700', 1, true) ~= nil)
        assert.truthy(both_headers:find('unsupported transfer-encoding', 1, true) ~= nil)
    end)

    it('accepts any media type with */* accept headers', function()
        local http_server = require('ministry.transport.http.server')
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

    it('returns correct HTTP errors for invalid method and route', function()
        local http_server = require('ministry.transport.http.server')

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
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')

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
        assert.truthy(structured_json:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(structured_json:find('"jsonrpc":"2.0"', 1, true) ~= nil)
        assert.truthy(non_json:find('HTTP/1.1 415 Unsupported Media Type', 1, true) ~= nil)
        assert.truthy(non_json:find('"error":"unsupported content type"', 1, true) ~= nil)
    end)

    it('rejects JSON POST requests without a Content-Type header', function()
        local http_server = require('ministry.transport.http.server')
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
        local http_server = require('ministry.transport.http.server')

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

        local invalid_null = run(vim.NIL)
        local invalid_number = run(42)
        local invalid_string = run('bad')
        local invalid_boolean = run(true)

        assert.truthy(invalid_null:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(invalid_null:find('"code":-32600', 1, true) ~= nil)
        assert.truthy(invalid_number:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(invalid_number:find('"code":-32600', 1, true) ~= nil)
        assert.truthy(invalid_string:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(invalid_string:find('"code":-32600', 1, true) ~= nil)
        assert.truthy(invalid_boolean:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(invalid_boolean:find('"code":-32600', 1, true) ~= nil)
    end)

    it('returns HTTP 200 with JSON-RPC error bodies for JSON-RPC failures', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')

        require('tests.helpers.ministry').setup(plugin)

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
                name = 'neovim/editor/read_buffer',
                arguments = {
                    bufnr = 'bad',
                },
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
        local http_server = require('ministry.transport.http.server')
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
        assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        assert.truthy(writes[1]:find('missing content%-length') ~= nil)
        assert.is_true(stopped)
        assert.is_true(closed)
    end)

    it('accepts LF-only HTTP requests', function()
        local http_server = require('ministry.transport.http.server')
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
        local send_response = require('ministry.transport.http.server')._send_response
        local client = {
            write = function() end,
        }

        assert.has_error(function()
            send_response(client, 200, {}, nil, false, 'HTTP/1.1')
        end, 'http response body must be a string')
    end)

    it('accepts bodyless HTTP requests without Content-Length', function()
        local http_server = require('ministry.transport.http.server')
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
                'GET /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                '',
                '',
            }, '\r\n')
        )

        assert.are.equal(1, #writes)
        assert.truthy(writes[1]:find('HTTP/1.1 405 Method Not Allowed', 1, true) ~= nil)
        assert.truthy(writes[1]:find('method not allowed', 1, true) ~= nil)
        assert.falsy(writes[1]:find('missing content%-length') ~= nil)
        assert.is_true(stopped)
        assert.is_false(closed)
    end)

    it('notifies on HTTP accept failure', function()
        local http_server = require('ministry.transport.http.server')
        local endpoint = require('ministry.transport.endpoint')
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
                    getsockname = function()
                        return { ip = '127.0.0.1', port = 8123 }
                    end,
                    listen = function(_, _, cb)
                        listener_cb = cb
                        return nil
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
                connect = function(_, _, _, cb)
                    cb(nil)
                    return true
                end,
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
end)
