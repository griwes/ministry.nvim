describe('mcp discovery and approvals', function()
    before_each(function()
        require('ministry').reset()
        require('ministry.external.http')._reset_request_impl()
    end)

    local function write_json(path, value)
        vim.fn.mkdir(vim.fs.dirname(path), 'p')
        vim.fn.writefile({ vim.json.encode(value) }, path)
    end

    it('discovers mcphub and vscode server config shapes', function()
        local root = vim.fn.tempname()
        local mcphub_path = vim.fs.joinpath(root, '.mcphub', 'servers.json')
        local vscode_path = vim.fs.joinpath(root, '.vscode', 'mcp.json')

        write_json(mcphub_path, {
            mcpServers = {
                local_tools = {
                    command = 'node',
                    args = { 'server.js' },
                    env = { TOKEN = 'secret' },
                    cwd = root,
                },
            },
        })
        write_json(vscode_path, {
            servers = {
                remote_tools = {
                    url = 'http://127.0.0.1:9999/mcp',
                    headers = { Authorization = 'Bearer token' },
                },
            },
        })

        require('ministry').setup({
            auto_start = false,
            external = {
                enabled = false,
                config = {},
                workspace = {
                    enabled = true,
                    look_for = { '.mcphub/servers.json', '.vscode/mcp.json' },
                    reload_on_dir_changed = false,
                },
            },
        })

        local servers, errors = require('ministry.sources.files').discover({ cwd = root })

        assert.are.equal(0, #errors)
        assert.are.equal(2, #servers)
        assert.are.equal('local_tools', servers[1].name)
        assert.are.equal('stdio', servers[1].transport)
        assert.are.equal('node', servers[1].command)
        assert.are.same({ 'server.js' }, servers[1].args)
        assert.are.equal(mcphub_path, servers[1].source.path)
        assert.are.equal('remote_tools', servers[2].name)
        assert.are.equal('http', servers[2].transport)
        assert.are.equal('http://127.0.0.1:9999/mcp', servers[2].url)
        assert.are.equal(vscode_path, servers[2].source.path)

        vim.fn.delete(root, 'rf')
    end)

    it('prefers nearer workspace config entries over parent entries with the same server name', function()
        local root = vim.fn.tempname()
        local child = vim.fs.joinpath(root, 'child')
        vim.fn.mkdir(child, 'p')
        write_json(vim.fs.joinpath(root, '.mcphub', 'servers.json'), {
            mcpServers = {
                duplicate = {
                    url = 'http://parent.example/mcp',
                },
            },
        })
        write_json(vim.fs.joinpath(child, '.mcphub', 'servers.json'), {
            mcpServers = {
                duplicate = {
                    url = 'http://child.example/mcp',
                },
            },
        })

        require('ministry').setup({
            auto_start = false,
            external = {
                enabled = false,
                config = {},
                workspace = {
                    enabled = true,
                    look_for = { '.mcphub/servers.json' },
                    reload_on_dir_changed = false,
                },
            },
        })

        local servers = require('ministry.sources.files').discover({ cwd = child })

        assert.are.equal(1, #servers)
        assert.are.equal('http://child.example/mcp', servers[1].url)

        vim.fn.delete(root, 'rf')
    end)

    it('registers and proxies HTTP external tools', function()
        local http = require('ministry.external.http')
        local calls = {}

        http._set_request_impl(function(_, payload, _, opts)
            table.insert(calls, payload.method)
            if payload.method == 'initialize' then
                assert.is_nil(opts.session_id)
                return { result = { protocolVersion = '2025-06-18' } }, nil, { session_id = 'session-1' }
            end
            if payload.method == 'notifications/initialized' then
                assert.are.equal('session-1', opts.session_id)
                return {}, nil
            end
            if payload.method == 'tools/list' then
                assert.are.equal('session-1', opts.session_id)
                return {
                    result = {
                        tools = {
                            {
                                name = 'echo',
                                description = 'Echo arguments',
                                inputSchema = { type = 'object' },
                            },
                        },
                    },
                },
                    nil
            end
            if payload.method == 'tools/call' then
                assert.are.equal('session-1', opts.session_id)
                return {
                    result = {
                        content = {
                            {
                                type = 'text',
                                text = payload.params.arguments.message,
                            },
                        },
                    },
                },
                    nil
            end
            return nil, { code = -32601, message = 'unexpected' }
        end)

        local plugin = require('ministry')
        plugin.setup({ auto_start = false })

        local runtimes, errors = require('ministry.external.manager').refresh({
            specs = {
                {
                    name = 'remote',
                    transport = 'http',
                    url = 'http://127.0.0.1:9999/mcp',
                    source = { kind = 'config', name = 'mcpServers', path = '/tmp/servers.json' },
                },
            },
        })

        assert.are.equal(0, #errors)
        assert.are.equal('ready', runtimes[1].state)

        local descriptors = plugin.list_tool_descriptors()
        local descriptor = vim.iter(descriptors):find(function(item)
            return item.namespaced_name == 'remote/echo'
        end)
        assert.is_not_nil(descriptor)

        local result, err = plugin.call_tool('remote/echo', { message = 'hello' }, {})
        assert.is_nil(err)
        assert.are.equal('hello', result.content[1].text)
        assert.are.same({ 'initialize', 'notifications/initialized', 'tools/list', 'tools/call' }, calls)
    end)

    it('parses data-only SSE HTTP responses and HTTP status headers', function()
        local http = require('ministry.external.http')
        local decoded, decode_err = http._decode_output('data: {"jsonrpc":"2.0","id":3,"result":{"ok":true}}\n\n', 3)
        local headers, body, status = http._split_headers(table.concat({
            'HTTP/1.1 404 Not Found',
            'Mcp-Session-Id: expired',
            '',
            '{"jsonrpc":"2.0","id":3,"error":{"code":-32000,"message":"missing"}}',
        }, '\r\n'))

        assert.is_nil(decode_err)
        assert.is_true(decoded.result.ok)
        assert.are.equal(404, status)
        assert.are.equal('expired', headers['mcp-session-id'])
        assert.is_true(body:find('"id":3', 1, true) ~= nil)

        local h2_headers, h2_body, h2_status = http._split_headers(table.concat({
            'HTTP/2 404',
            'Mcp-Session-Id: h2-expired',
            '',
            '{"jsonrpc":"2.0","id":4,"error":{"code":-32000,"message":"missing"}}',
        }, '\r\n'))

        assert.are.equal(404, h2_status)
        assert.are.equal('h2-expired', h2_headers['mcp-session-id'])
        assert.is_true(h2_body:find('"id":4', 1, true) ~= nil)
    end)

    it('surfaces HTTP status response body details through server inspection', function()
        local root = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(vim.uv.os_tmpdir(), 'ministry-http-XXXXXX')))
        local curl_path = vim.fs.joinpath(root, 'curl')
        vim.fn.writefile({
            '#!/bin/sh',
            'cat >/dev/null',
            [[printf '%b' 'HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\n\r\n{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"missing bearer token"}}']],
        }, curl_path)
        vim.fn.setfperm(curl_path, 'rwx------')

        local old_path = vim.env.PATH
        vim.env.PATH = root .. ':' .. old_path

        local ok, err = xpcall(function()
            require('ministry').setup({ auto_start = false })
            local runtimes, errors = require('ministry.external.manager').refresh({
                specs = {
                    {
                        name = 'remote',
                        transport = 'http',
                        url = 'http://127.0.0.1:9999/mcp',
                        source = { kind = 'config', name = 'servers', path = '/tmp/mcp.json' },
                    },
                },
            })

            assert.are.equal(1, #errors)
            assert.are.equal('error', runtimes[1].state)
            assert.is_true(errors[1].message:find('HTTP MCP request failed with status 401', 1, true) ~= nil)
            assert.is_true(errors[1].message:find('JSON-RPC error: missing bearer token', 1, true) ~= nil)

            local rendered = table.concat(
                require('ministry.ui.servers').render_lines(require('ministry').list_server_statuses()),
                '\n'
            )
            assert.is_true(rendered:find('error=', 1, true) ~= nil)
            assert.is_true(rendered:find('missing bearer token', 1, true) ~= nil)
        end, function(message)
            return debug.traceback(message, 2)
        end)

        vim.env.PATH = old_path
        vim.fn.delete(root, 'rf')
        if not ok then
            error(err)
        end
    end)

    it('reinitializes HTTP servers when a session-bound request returns 404', function()
        local http = require('ministry.external.http')
        local calls = {}
        local first_tool_call = true

        http._set_request_impl(function(_, payload, _, opts)
            table.insert(calls, {
                method = payload.method,
                session_id = opts.session_id,
            })
            if payload.method == 'initialize' then
                return { result = { protocolVersion = '2025-06-18' } }, nil, { session_id = 'session-' .. #calls }
            end
            if payload.method == 'notifications/initialized' then
                return {}, nil
            end
            if payload.method == 'tools/list' then
                return {
                    result = {
                        tools = {
                            { name = 'echo', inputSchema = { type = 'object' } },
                        },
                    },
                },
                    nil
            end
            if payload.method == 'tools/call' and first_tool_call then
                first_tool_call = false
                return nil, { code = -32000, message = 'expired', http_status = 404 }
            end
            if payload.method == 'tools/call' then
                return {
                    result = {
                        content = {
                            { type = 'text', text = payload.params.arguments.message },
                        },
                    },
                },
                    nil
            end
            return nil, { code = -32601, message = 'unexpected' }
        end)

        local plugin = require('ministry')
        plugin.setup({ auto_start = false })
        local spec = {
            name = 'remote',
            transport = 'http',
            url = 'http://127.0.0.1:9999/mcp',
            source = { kind = 'config', name = 'mcpServers', path = '/tmp/servers.json' },
        }

        local errors = select(2, require('ministry.external.manager').refresh({ specs = { spec } }))
        assert.are.equal(0, #errors)

        local result, err = plugin.call_tool('remote/echo', { message = 'after-reinit' }, {})
        assert.is_nil(err)
        assert.are.equal('after-reinit', result.content[1].text)
        assert.are.equal('initialize', calls[5].method)
        assert.are.equal('tools/call', calls[7].method)
    end)

    it('removes stale external tools when refreshing the same server fails', function()
        local http = require('ministry.external.http')
        local fail = false

        http._set_request_impl(function(_, payload)
            if fail then
                return nil, { code = -32000, message = 'offline' }
            end
            if payload.method == 'initialize' then
                return { result = { protocolVersion = '2025-06-18' } }, nil
            end
            if payload.method == 'notifications/initialized' then
                return {}, nil
            end
            if payload.method == 'tools/list' then
                return {
                    result = {
                        tools = {
                            { name = 'echo', inputSchema = { type = 'object' } },
                        },
                    },
                },
                    nil
            end
            return { result = {} }, nil
        end)

        local plugin = require('ministry')
        plugin.setup({ auto_start = false })
        local spec = {
            name = 'remote',
            transport = 'http',
            url = 'http://127.0.0.1:9999/mcp',
            source = { kind = 'config', name = 'mcpServers', path = '/tmp/servers.json' },
        }

        local first_errors = select(2, require('ministry.external.manager').refresh({ specs = { spec } }))
        assert.are.equal(0, #first_errors)
        assert.is_not_nil(vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'remote/echo'
        end))

        fail = true
        local runtimes, errors = require('ministry.external.manager').refresh({ specs = { spec } })

        assert.are.equal(1, #errors)
        assert.are.equal('error', runtimes[1].state)
        assert.is_nil(vim.iter(plugin.list_tool_descriptors()):find(function(item)
            return item.namespaced_name == 'remote/echo'
        end))
    end)

    it('registers and proxies stdio external tools', function()
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local server_path = vim.fs.joinpath(root, 'stdio-server.lua')
        vim.fn.writefile({
            'local tools = { { name = "echo", description = "Echo arguments", inputSchema = { type = "object" } } }',
            'for line in io.lines() do',
            '  local request = vim.json.decode(line)',
            '  local response',
            '  if request.method == "initialize" then',
            '    response = { jsonrpc = "2.0", id = request.id, result = { protocolVersion = "2025-06-18" } }',
            '  elseif request.method == "tools/list" then',
            '    response = { jsonrpc = "2.0", id = request.id, result = { tools = tools } }',
            '  elseif request.method == "tools/call" then',
            '    response = { jsonrpc = "2.0", id = request.id, result = { content = { { type = "text", text = request.params.arguments.message } } } }',
            '  else',
            '    response = { jsonrpc = "2.0", id = request.id, error = { code = -32601, message = "unexpected" } }',
            '  end',
            '  io.stdout:write(vim.json.encode(response) .. "\\n")',
            '  io.stdout:flush()',
            'end',
        }, server_path)

        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            external = {
                request_timeout_ms = 5000,
            },
        })
        plugin.set_approval('local', '__activate', 'allow')

        local runtimes, errors = require('ministry.external.manager').refresh({
            specs = {
                {
                    name = 'local',
                    transport = 'stdio',
                    command = vim.v.progpath,
                    args = { '--headless', '-u', 'NONE', '-l', server_path },
                    source = { kind = 'config', name = 'mcpServers', path = server_path },
                },
            },
        })

        assert.are.equal(0, #errors)
        assert.are.equal('ready', runtimes[1].state)

        local result, err = plugin.call_tool('local/echo', { message = 'stdio' }, {})
        assert.is_nil(err)
        assert.are.equal('stdio', result.content[1].text)

        vim.fn.delete(root, 'rf')
    end)

    it('stops a running stdio server when activation is revoked or config disappears', function()
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local server_path = vim.fs.joinpath(root, 'stdio-server.lua')
        vim.fn.writefile({
            'local tools = { { name = "echo", inputSchema = { type = "object" } } }',
            'for line in io.lines() do',
            '  local request = vim.json.decode(line)',
            '  local response',
            '  if request.method == "initialize" then',
            '    response = { jsonrpc = "2.0", id = request.id, result = { protocolVersion = "2025-06-18" } }',
            '  elseif request.method == "tools/list" then',
            '    response = { jsonrpc = "2.0", id = request.id, result = { tools = tools } }',
            '  elseif request.method == "tools/call" then',
            '    response = { jsonrpc = "2.0", id = request.id, result = { content = { { type = "text", text = "ok" } } } }',
            '  else',
            '    response = { jsonrpc = "2.0", id = request.id, result = {} }',
            '  end',
            '  io.stdout:write(vim.json.encode(response) .. "\\n")',
            '  io.stdout:flush()',
            'end',
        }, server_path)

        local spec = {
            name = 'local',
            transport = 'stdio',
            command = vim.v.progpath,
            args = { '--headless', '-u', 'NONE', '-l', server_path },
            source = { kind = 'config', name = 'mcpServers', path = server_path },
        }
        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            external = {
                request_timeout_ms = 5000,
            },
        })
        plugin.set_approval('local', '__activate', 'allow')

        local errors = select(2, require('ministry.external.manager').refresh({ specs = { spec } }))
        assert.are.equal(0, #errors)
        assert.is_true(require('ministry.external.stdio')._running('local'))

        plugin.set_approval('local', '__activate', 'reject')
        local revoked_errors = select(2, require('ministry.external.manager').refresh({ specs = { spec } }))
        assert.are.equal(1, #revoked_errors)
        assert.is_false(require('ministry.external.stdio')._running('local'))

        plugin.set_approval('local', '__activate', 'allow')
        local restarted_errors = select(2, require('ministry.external.manager').refresh({ specs = { spec } }))
        assert.are.equal(0, #restarted_errors)
        assert.is_true(require('ministry.external.stdio')._running('local'))

        require('ministry.external.manager').refresh({ specs = {} })
        assert.is_false(require('ministry.external.stdio')._running('local'))

        vim.fn.delete(root, 'rf')
    end)

    it('surfaces stdio stderr when a server exits during initialization', function()
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local server_path = vim.fs.joinpath(root, 'failing-stdio-server.lua')
        vim.fn.writefile({
            'io.stderr:write("bootstrap failed: missing token\\n")',
            'io.stderr:flush()',
            'os.exit(7)',
        }, server_path)

        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            external = {
                request_timeout_ms = 5000,
            },
        })
        plugin.set_approval('broken', '__activate', 'allow')

        local runtimes, errors = require('ministry.external.manager').refresh({
            specs = {
                {
                    name = 'broken',
                    transport = 'stdio',
                    command = vim.v.progpath,
                    args = { '--headless', '-u', 'NONE', '-l', server_path },
                    source = { kind = 'config', name = 'mcpServers', path = server_path },
                },
            },
        })

        assert.are.equal(1, #errors)
        assert.are.equal('error', runtimes[1].state)
        assert.is_true(runtimes[1].error:find('exited before responding', 1, true) ~= nil)
        assert.is_true(runtimes[1].error:find('with code 7', 1, true) ~= nil)
        assert.is_true(runtimes[1].error:find('bootstrap failed: missing token', 1, true) ~= nil)
        assert.are.equal(runtimes[1].error, errors[1].message)

        local rendered =
            table.concat(require('ministry.ui.servers').render_lines(require('ministry').list_server_statuses()), '\n')
        assert.is_true(rendered:find('error=', 1, true) ~= nil)
        assert.is_true(rendered:find('bootstrap failed: missing token', 1, true) ~= nil)

        vim.fn.delete(root, 'rf')
    end)

    it('discovers external servers during setup without activating stdio commands', function()
        local root = vim.fn.tempname()
        local marker = vim.fs.joinpath(root, 'started')
        local config_path = vim.fs.joinpath(root, '.mcphub', 'servers.json')
        write_json(config_path, {
            mcpServers = {
                local_tools = {
                    command = vim.v.progpath,
                    args = { '--headless', '-u', 'NONE', '-c', 'call writefile(["started"], "' .. marker .. '")' },
                },
            },
        })

        require('ministry').setup({
            auto_start = false,
            external = {
                enabled = true,
                config = config_path,
                workspace = {
                    enabled = false,
                    look_for = {},
                    reload_on_dir_changed = false,
                },
            },
        })

        local statuses = require('ministry').list_server_statuses()
        local local_status = vim.iter(statuses):find(function(status)
            return status.name == 'local_tools'
        end)

        assert.is_not_nil(local_status)
        assert.are.equal('configured', local_status.state)
        assert.are.equal(0, vim.fn.filereadable(marker))

        vim.fn.delete(root, 'rf')
    end)

    it('rejects stdio activation without an activation approval', function()
        local root = vim.fn.tempname()
        local marker = vim.fs.joinpath(root, 'started')
        vim.fn.mkdir(root, 'p')

        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            approval = {
                enabled = false,
                default = 'ask',
                persistence = false,
            },
        })

        local runtimes, errors = require('ministry.external.manager').refresh({
            specs = {
                {
                    name = 'blocked',
                    transport = 'stdio',
                    command = vim.v.progpath,
                    args = { '--headless', '-u', 'NONE', '-c', 'call writefile(["started"], "' .. marker .. '")' },
                    source = { kind = 'config', name = 'mcpServers', path = '/tmp/servers.json' },
                },
            },
        })

        assert.are.equal(1, #errors)
        assert.are.equal('error', runtimes[1].state)
        assert.are.equal(0, vim.fn.filereadable(marker))

        vim.fn.delete(root, 'rf')
    end)

    it('gates native tools through persisted approval policy', function()
        local root = vim.fn.tempname()
        local policy_path = vim.fs.joinpath(root, 'approvals.json')
        local plugin = require('ministry')
        local executed = false

        plugin.setup({
            auto_start = false,
            approval = {
                enabled = true,
                default = 'allow',
                persistence = true,
                path = policy_path,
            },
        })
        plugin.register_server({
            name = 'editor',
            tools = {
                echo = {
                    handler = function()
                        executed = true
                        return { ok = true }
                    end,
                },
            },
        })

        plugin.set_approval('editor', 'echo', 'reject')

        local result, err = plugin.call_tool('editor/echo', {}, {})
        assert.is_nil(result)
        assert.are.equal(-32001, err.code)
        assert.is_false(executed)

        plugin.reset()
        plugin.setup({
            auto_start = false,
            approval = {
                enabled = true,
                default = 'allow',
                persistence = true,
                path = policy_path,
            },
        })

        assert.are.equal('reject', plugin.get_approval('editor', 'echo'))

        vim.fn.delete(root, 'rf')
    end)

    it('summarizes native and external server state for the inspection UI', function()
        local plugin = require('ministry')
        plugin.setup({ auto_start = false })
        plugin.set_approval('neovim', nil, 'ask')
        plugin.set_approval('remote', 'echo', 'allow')
        require('ministry.external.manager').configure({
            {
                name = 'remote',
                transport = 'http',
                url = 'http://127.0.0.1:9999/mcp',
                source = { kind = 'config', name = 'servers', path = '/tmp/mcp.json' },
            },
        })

        local statuses = plugin.list_server_statuses()
        local rendered = require('ministry.ui.servers').render_lines(statuses)
        local text = table.concat(rendered, '\n')

        assert.is_true(text:find('neovim', 1, true) ~= nil)
        assert.is_true(text:find('remote', 1, true) ~= nil)
        assert.is_true(text:find('http://127.0.0.1:9999/mcp', 1, true) ~= nil)
        assert.is_true(text:find('allow=1', 1, true) ~= nil)
    end)

    it('renders server and method approval targets for the inspection UI', function()
        local ui = require('ministry.ui.servers')
        local statuses = {
            {
                name = 'local',
                source = { kind = 'config', path = '/tmp/servers.json' },
                transport = 'stdio',
                command = 'node',
                args = { 'server.js' },
                state = 'configured',
                policy = {
                    default = 'ask',
                    allow = 1,
                    reject = 1,
                    ask = 0,
                    tools = {
                        __activate = 'allow',
                        echo = 'reject',
                        policy_only = 'allow',
                    },
                },
                tools = {
                    { name = 'echo' },
                    { name = 'inspect' },
                },
            },
        }

        local lines = ui.render_lines(statuses)
        local text = table.concat(lines, '\n')

        assert.is_true(text:find('method=__activate  policy=allow', 1, true) ~= nil)
        assert.is_true(text:find('method=echo  policy=reject', 1, true) ~= nil)
        assert.is_true(text:find('method=inspect  policy=ask inherited', 1, true) ~= nil)
        assert.is_true(text:find('method=policy_only  policy=allow', 1, true) ~= nil)
        assert.are.same({ server = 'local' }, ui._target_at_line(statuses, 5))
        assert.are.same({ server = 'local', method = '__activate' }, ui._target_at_line(statuses, 7))
        assert.are.same({ server = 'local', method = 'echo' }, ui._target_at_line(statuses, 8))
        assert.are.same({ server = 'local', method = 'inspect' }, ui._target_at_line(statuses, 9))
        assert.are.same({ server = 'local', method = 'policy_only' }, ui._target_at_line(statuses, 10))
    end)

    it('updates method approvals from the inspection UI keymaps', function()
        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            approval = {
                enabled = true,
                default = 'ask',
                persistence = false,
            },
        })
        require('ministry.external.manager').configure({
            {
                name = 'local',
                source = { kind = 'config', path = '/tmp/servers.json' },
                transport = 'stdio',
                command = 'node',
                args = { 'server.js' },
            },
        })
        plugin.set_approval('local', 'echo', 'reject')

        require('ministry.ui.servers').open(plugin.list_server_statuses())
        vim.api.nvim_win_set_cursor(0, { 8, 0 })
        vim.api.nvim_feedkeys('a', 'x', false)

        assert.are.equal('allow', plugin.get_approval('local', 'echo'))
    end)
end)
