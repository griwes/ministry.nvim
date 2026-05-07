describe('mcp', function()
    before_each(function()
        require('ministry').reset()
    end)
    it('updates the matching modified buffer for editor/write_file without forcing a save', function()
        local plugin = require('ministry')
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

        assert.is_nil(err)
        assert.are.equal(vim.api.nvim_get_current_buf(), result.updated_buffer)
        assert.is_false(result.reloaded_buffer)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.is_true(vim.bo[0].modified)
        assert.are.equal('before\n', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('treats exact server-name tool identifiers as already qualified', function()
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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

    it('rejects HTTP requests without the configured bearer token', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
                http_token = 'secret-token',
            })
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
            assert.truthy(writes[1]:find('401 Unauthorized', 1, true) ~= nil)
            assert.truthy(writes[1]:find('WWW-Authenticate: Bearer', 1, true) ~= nil)
            assert.truthy(writes[1]:find('Access-Control-Allow-Origin:', 1, true) == nil)
            assert.truthy(
                writes[1]:find('Access-Control-Allow-Headers: Authorization, Content-Type, Accept', 1, true) ~= nil
            )
        end, function(message)
            return debug.traceback(message, 2)
        end)
        plugin.reset()
        if not ok then
            error(err)
        end
    end)

    it('accepts authenticated HTTP requests and enables CORS for matching origins', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
                http_token = 'secret-token',
            })
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
                'Origin: http://127.0.0.1:3000',
                'Authorization: Bearer secret-token',
                'Content-Type: application/json',
                'Content-Length: 51',
                '',
                '{"jsonrpc":"2.0","id":99,"method":"tools/list"}',
            }, '\r\n') .. '\r\n\r\n')

            vim.wait(1000, function()
                return writes[1] ~= nil
            end)
            assert.is_not_nil(writes[1])
            assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
            assert.truthy(writes[1]:find('Access-Control-Allow-Origin: http://127.0.0.1:3000', 1, true) ~= nil)
        end, function(message)
            return debug.traceback(message, 2)
        end)
        plugin.reset()
        if not ok then
            error(err)
        end
    end)

    it('accepts unauthenticated HTTP requests when no non-empty bearer token is configured', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
                http_token = '',
            })
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
            assert.truthy(writes[1]:find('HTTP/1.1 200 OK', 1, true) ~= nil)
        end, function(message)
            return debug.traceback(message, 2)
        end)
        plugin.reset()
        if not ok then
            error(err)
        end
    end)

    it('allows authenticated CORS preflight requests without requiring the bearer token', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
        local ok, err = xpcall(function()
            plugin.setup({
                transport = 'http',
                http_host = '127.0.0.1',
                http_port = 0,
                http_token = 'secret-token',
            })
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
            read_cb(
                nil,
                table.concat({
                    'OPTIONS /mcp HTTP/1.1',
                    'Host: localhost',
                    'Origin: http://127.0.0.1:3000',
                    'Access-Control-Request-Method: POST',
                    'Access-Control-Request-Headers: Authorization, Content-Type',
                    'Content-Length: 0',
                    '',
                    '',
                }, '\r\n')
            )

            vim.wait(1000, function()
                return writes[1] ~= nil
            end)
            assert.is_not_nil(writes[1])
            assert.truthy(writes[1]:find('204 No Content', 1, true) ~= nil)
            assert.truthy(writes[1]:find('Access-Control-Allow-Origin: http://127.0.0.1:3000', 1, true) ~= nil)
            assert.truthy(
                writes[1]:find('Access-Control-Allow-Headers: Authorization, Content-Type, Accept', 1, true) ~= nil
            )
        end, function(message)
            return debug.traceback(message, 2)
        end)
        plugin.reset()
        if not ok then
            error(err)
        end
    end)

    it(
        'accepts CORS preflight requests with an invalid Authorization header when an HTTP token is configured and authorization is declared',
        function()
            local plugin = require('ministry')
            local http_server = require('ministry.transport.http.server')
            local ok, err = xpcall(function()
                plugin.setup({
                    transport = 'http',
                    http_host = '127.0.0.1',
                    http_port = 0,
                    http_token = 'secret-token',
                })
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
                read_cb(
                    nil,
                    table.concat({
                        'OPTIONS /mcp HTTP/1.1',
                        'Host: localhost',
                        'Origin: http://127.0.0.1:3000',
                        'Access-Control-Request-Method: POST',
                        'Access-Control-Request-Headers: Authorization, Content-Type',
                        'Authorization: Bearer wrong-token',
                        'Content-Length: 0',
                        '',
                        '',
                    }, '\r\n')
                )

                vim.wait(1000, function()
                    return writes[1] ~= nil
                end)
                assert.is_not_nil(writes[1])
                assert.truthy(writes[1]:find('204 No Content', 1, true) ~= nil)
                assert.truthy(writes[1]:find('Access-Control-Allow-Origin: http://127.0.0.1:3000', 1, true) ~= nil)
            end, function(message)
                return debug.traceback(message, 2)
            end)
            plugin.reset()
            if not ok then
                error(err)
            end
        end
    )

    it('accepts requests without an accept header', function()
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
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
        local plugin = require('ministry')
        local http_server = require('ministry.transport.http.server')
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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

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
        local plugin = require('ministry')

        plugin.setup()

        local builtin = vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'neovim/editor/list_buffers'
        end)
        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'neovim'
        end)
        local builtin_tool = vim.iter(server.tools):find(function(item)
            return item.name == 'editor/list_buffers'
        end)

        local schema_override = vim.deepcopy(builtin.inputSchema)
        schema_override.properties = schema_override.properties or {}
        schema_override.properties.only_listed = { type = 'boolean' }

        plugin.register_tool('neovim', {
            name = 'editor/list_buffers',
            description = builtin.description,
            inputSchema = schema_override,
            handler = builtin_tool.handler,
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
        local plugin = require('ministry')

        plugin.setup()

        local builtin = vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'neovim/editor/list_buffers'
        end)
        local server = vim.iter(plugin.list_servers()):find(function(item)
            return item.name == 'neovim'
        end)
        local builtin_tool = vim.iter(server.tools):find(function(item)
            return item.name == 'editor/list_buffers'
        end)

        plugin.register_tool('neovim', {
            name = 'editor/list_buffers',
            description = builtin.description,
            inputSchema = vim.deepcopy(builtin.inputSchema),
            handler = builtin_tool.handler,
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
        local plugin = require('ministry')

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
    local plugin = require('ministry')

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
    local plugin = require('ministry')
    local http_server = require('ministry.transport.http.server')

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
    local plugin = require('ministry')
    local http_server = require('ministry.transport.http.server')

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

it('starts socket and HTTP from start when HTTP transport is requested and sockets are supported', function()
    local plugin = require('ministry')
    local server = require('ministry.transport.server')
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
        assert.are.equal(1, start_socket_calls)
    end, debug.traceback)

    server.start_http = original_start_http
    server.start_socket = original_start_socket
    vim.uv.new_pipe = original_socket_supported

    if not ok then
        error(err)
    end
end)

it('reuses an existing HTTP listener for repeated ephemeral-port starts', function()
    local plugin = require('ministry')
    local http_server = require('ministry.transport.http.server')

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
    local plugin = require('ministry')
    local http_server = require('ministry.transport.http.server')

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
    local http_server = require('ministry.transport.http.server')
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

it('restarts a pending ephemeral HTTP listener when the configured host changes', function()
    local plugin = require('ministry')
    local http_server = require('ministry.transport.http.server')
    local original_new_tcp = vim.uv.new_tcp
    local original_in_fast_event = vim.in_fast_event
    local bind_calls = {}
    local created = 0
    local first_server

    vim.in_fast_event = function()
        return true
    end

    vim.uv.new_tcp = function()
        created = created + 1

        if created == 1 or created == 3 then
            local closed = false
            local tcp = {
                bind = function(_, host, port)
                    table.insert(bind_calls, { host = host, port = port })
                    return 0
                end,
                getsockname = function()
                    local last = bind_calls[#bind_calls]
                    return { ip = last.host, port = 0 }
                end,
                listen = function()
                    return nil
                end,
                is_closing = function()
                    return closed
                end,
                close = function()
                    closed = true
                end,
            }

            if created == 1 then
                first_server = tcp
            end

            return tcp
        end

        local closed = false
        return {
            connect = function()
                return true
            end,
            is_closing = function()
                return closed
            end,
            close = function()
                closed = true
            end,
        }
    end

    local ok, err = xpcall(function()
        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.1',
            http_port = 0,
        })

        local started, start_err = http_server.start()
        assert.is_true(started)
        assert.is_nil(start_err)

        plugin.setup({
            transport = 'http',
            http_host = '127.0.0.2',
            http_port = 0,
        })

        started, start_err = http_server.start()
        assert.is_true(started)
        assert.is_nil(start_err)

        assert.are.equal(2, #bind_calls)
        assert.are.same({ host = '127.0.0.1', port = 0 }, bind_calls[1])
        assert.are.same({ host = '127.0.0.2', port = 0 }, bind_calls[2])
        assert.is_not_nil(first_server)
        assert.is_true(first_server:is_closing())
    end, debug.traceback)

    vim.uv.new_tcp = original_new_tcp
    vim.in_fast_event = original_in_fast_event
    plugin.reset()

    if not ok then
        error(err)
    end
end)

it('reports pending startup from fast-event contexts', function()
    local http_server = require('ministry.transport.http.server')
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
    local http_server = require('ministry.transport.http.server')
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

it('restarts a pending HTTP listener when the endpoint changes', function()
    local plugin = require('ministry')
    local http_server = require('ministry.transport.http.server')
    local original_new_tcp = vim.uv.new_tcp
    local original_in_fast_event = vim.in_fast_event
    local closed_listeners = 0
    local created = 0

    vim.in_fast_event = function()
        return true
    end

    vim.uv.new_tcp = function()
        created = created + 1
        if created == 1 or created == 3 then
            local closed = false
            return {
                bind = function()
                    return 0
                end,
                getsockname = function()
                    return { ip = '127.0.0.1', port = created == 1 and 9876 or 9877 }
                end,
                listen = function()
                    return nil
                end,
                accept = function()
                    return 0
                end,
                is_closing = function()
                    return closed
                end,
                close = function()
                    if not closed then
                        closed = true
                        closed_listeners = closed_listeners + 1
                    end
                end,
            }
        end

        local closed = false
        return {
            connect = function()
                return true
            end,
            is_closing = function()
                return closed
            end,
            close = function()
                closed = true
            end,
        }
    end

    plugin.setup({
        transport = 'http',
        http_host = '127.0.0.1',
        http_port = 9876,
    })

    local ok, err = http_server.start()
    assert.is_true(ok)
    assert.is_nil(err)

    plugin.setup({
        transport = 'http',
        http_host = '127.0.0.1',
        http_port = 9877,
    })

    local restarted, restart_err = http_server.start()

    vim.uv.new_tcp = original_new_tcp
    vim.in_fast_event = original_in_fast_event
    http_server.stop()

    assert.is_true(restarted)
    assert.is_nil(restart_err)
    assert.are.equal(2, closed_listeners)
end)

it('reports asynchronous HTTP listen startup failures to the caller', function()
    local http_server = require('ministry.transport.http.server')
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

it('probes IPv4 wildcard listeners through loopback', function()
    local http_server = require('ministry.transport.http.server')
    local original_new_tcp = vim.uv.new_tcp
    local listener_closed = false
    local probe_closed = false
    local created = 0
    local connected_host
    local connected_port

    vim.uv.new_tcp = function()
        created = created + 1
        if created == 1 then
            return {
                bind = function()
                    return 0
                end,
                getsockname = function()
                    return { ip = '0.0.0.0', port = 9876 }
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
        end

        return {
            connect = function(_, host, port, cb)
                connected_host = host
                connected_port = port
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

    local ok, err = xpcall(function()
        local started, start_err = http_server.start()

        assert.is_true(started)
        assert.is_nil(start_err)
        assert.are.equal('127.0.0.1', connected_host)
        assert.are.equal(9876, connected_port)
        assert.is_true(probe_closed)
    end, debug.traceback)

    vim.uv.new_tcp = original_new_tcp
    http_server.stop()

    if not ok then
        error(err)
    end
end)

it('probes IPv6 wildcard listeners through loopback', function()
    local http_server = require('ministry.transport.http.server')
    local original_new_tcp = vim.uv.new_tcp
    local listener_closed = false
    local probe_closed = false
    local created = 0
    local connected_host
    local connected_port

    vim.uv.new_tcp = function()
        created = created + 1
        if created == 1 then
            return {
                bind = function()
                    return 0
                end,
                getsockname = function()
                    return { ip = '0:0:0:0:0:0:0:0', port = 9876 }
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
        end

        return {
            connect = function(_, host, port, cb)
                connected_host = host
                connected_port = port
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

    local ok, err = xpcall(function()
        local started, start_err = http_server.start()

        assert.is_true(started)
        assert.is_nil(start_err)
        assert.are.equal('::1', connected_host)
        assert.are.equal(9876, connected_port)
        assert.is_true(probe_closed)
    end, debug.traceback)

    vim.uv.new_tcp = original_new_tcp
    http_server.stop()

    if not ok then
        error(err)
    end
end)

it('drains pending HTTP clients when the startup probe fails', function()
    local http_server = require('ministry.transport.http.server')
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
    local plugin = require('ministry')

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
    local http_server = require('ministry.transport.http.server')
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
