describe('mcp transport security', function()
    before_each(function()
        require('ministry').reset()
    end)

    after_each(function()
        require('ministry').reset()
    end)

    local function setup_approval(reservation_ttl_ms)
        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            approval = {
                enabled = true,
                default = 'ask',
                persistence = false,
                providers = {},
                reservation_ttl_ms = reservation_ttl_ms or 30000,
            },
        })
        plugin.register_server({
            name = 'fixture',
            tools = {
                echo = {
                    handler = function(arguments)
                        return { value = arguments.value }
                    end,
                },
            },
        })
        return plugin
    end

    it('enables ask-by-default approval policy', function()
        local plugin = require('ministry')
        plugin.setup({ auto_start = false })

        local approval = require('ministry.core.config').get().approval

        assert.is_true(approval.enabled)
        assert.are.equal('ask', approval.default)
    end)

    it('uses a private runtime directory for filesystem socket endpoints', function()
        local endpoint = require('ministry').endpoint()
        local runtime_dir = vim.fs.dirname(endpoint.socket_name)
        local stat = assert(vim.uv.fs_stat(runtime_dir))

        assert.are.equal('filesystem', endpoint.socket_kind)
        assert.are.equal('directory', stat.type)
        assert.are.equal(448, bit.band(stat.mode, 511))
        assert.are.equal(runtime_dir, vim.fs.dirname(endpoint.socket_name))
    end)

    it('rejects unauthenticated non-loopback HTTP startup and rolls back its socket', function()
        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            transport = 'http',
            http_host = '0.0.0.0',
            http_token = nil,
            approval = {
                enabled = false,
                persistence = false,
            },
        })

        local ok, err = plugin.start('http')

        assert.is_false(ok)
        assert.matches('require http_token authentication', err, 1, true)
        assert.is_false(plugin.running())
    end)

    it('does not let a contextless request consume an id-bound approval', function()
        local plugin = setup_approval()
        plugin.approve_once('fixture', 'echo', { value = 'approved' }, { tool_call_id = 'call-1' })

        local contextless_result, contextless_err = plugin.call_tool('fixture/echo', { value = 'approved' }, {})
        local approved_result, approved_err = plugin.call_tool(
            'fixture/echo',
            { value = 'approved' },
            { tool_call_id = 'call-1' }
        )

        assert.is_nil(contextless_result)
        assert.are.equal(-32001, contextless_err.code)
        assert.is_nil(approved_err)
        assert.are.same({ value = 'approved' }, approved_result)
    end)

    it('binds one-shot approvals to the endpoint session that reserved them', function()
        local plugin = setup_approval()
        local sessions = require('ministry.protocol.session')
        local first_session = sessions.open('socket')

        plugin.approve_once('fixture', 'echo', { value = 'approved' }, { tool_call_id = 'call-1' })
        local second_session = sessions.open('socket')

        local other_result, other_err = plugin.call_tool('fixture/echo', { value = 'approved' }, {
            transport_session_id = second_session,
        })
        local approved_result, approved_err = plugin.call_tool('fixture/echo', { value = 'approved' }, {
            transport_session_id = first_session,
        })

        assert.is_nil(other_result)
        assert.are.equal(-32001, other_err.code)
        assert.is_nil(approved_err)
        assert.are.same({ value = 'approved' }, approved_result)

        sessions.close(first_session)
        sessions.close(second_session)
    end)

    it('expires and disconnect-cleans endpoint-bound one-shot approvals', function()
        local plugin = setup_approval(5)
        local sessions = require('ministry.protocol.session')
        local session_id = sessions.open('socket')

        plugin.approve_once('fixture', 'echo', { value = 'expired' }, { tool_call_id = 'call-1' })
        assert.are.equal(1, #require('ministry.approval.policy')._debug_pending_approvals())
        vim.wait(20, function()
            return false
        end, 1)
        assert.are.equal(0, #require('ministry.approval.policy')._debug_pending_approvals())

        plugin.approve_once('fixture', 'echo', { value = 'disconnect' }, { tool_call_id = 'call-2' })
        assert.are.equal(1, #require('ministry.approval.policy')._debug_pending_approvals())
        sessions.close(session_id)
        assert.are.equal(0, #require('ministry.approval.policy')._debug_pending_approvals())
    end)

    it('cancels tracked work on request deadlines and disconnects', function()
        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            limits = { request_timeout_ms = 10 },
            approval = { enabled = false, persistence = false },
        })
        local sessions = require('ministry.protocol.session')
        local session_id = sessions.open('http')
        local context = sessions.begin_request(session_id, 7)
        local reasons = {}
        context.register_cancellation(function(reason)
            table.insert(reasons, reason)
        end)

        assert.is_true(vim.wait(100, function()
            return #reasons == 1
        end, 1))
        assert.are.equal('request deadline exceeded', reasons[1])
        sessions.finish_request(session_id, 7)

        local disconnect_context = sessions.begin_request(session_id, 8)
        disconnect_context.register_cancellation(function(reason)
            table.insert(reasons, reason)
        end)
        sessions.close(session_id)
        assert.are.equal('transport disconnected', reasons[2])
    end)

    it('rejects duplicate active request ids without replacing the original request', function()
        local sessions = require('ministry.protocol.session')
        local session_id = sessions.open('socket')
        local original = sessions.begin_request(session_id, 7)
        local cancelled = false

        original.register_cancellation(function()
            cancelled = true
        end)

        local response = require('ministry.transport.http.jsonrpc').dispatch_jsonrpc_message({
            jsonrpc = '2.0',
            id = 7,
            method = 'tools/list',
        }, session_id)

        assert.are.same({
            code = -32600,
            message = 'Duplicate active request id',
        }, response.error)
        assert.is_false(cancelled)
        assert.are.same(1, vim.tbl_count(sessions._debug_sessions()[session_id].requests))

        sessions.finish_request(session_id, 7)
        sessions.close(session_id)
    end)

    it('kills an in-flight downstream HTTP request when its context is cancelled', function()
        local external_http = require('ministry.external.http')
        local original_system = vim.system
        local killed_with = nil
        local unregistered = false

        vim.system = function()
            return {
                kill = function(_, signal)
                    killed_with = signal
                end,
                wait = function()
                    return { code = 143, stdout = '', stderr = '' }
                end,
            }
        end

        local ok, err = xpcall(function()
            external_http._reset_request_impl()
            local result, request_err = external_http.request(
                {
                    name = 'fixture',
                    transport = 'http',
                    url = 'http://127.0.0.1:9/mcp',
                },
                {
                    method = 'tools/call',
                },
                1000,
                {
                    context = {
                        register_cancellation = function(callback)
                            callback('client disconnected')
                            return function()
                                unregistered = true
                            end
                        end,
                    },
                }
            )

            assert.is_nil(result)
            assert.are.equal(-32800, request_err.code)
            assert.are.equal('client disconnected', request_err.message)
            assert.are.equal(15, killed_with)
            assert.is_true(unregistered)
        end, debug.traceback)

        vim.system = original_system
        external_http._reset_request_impl()
        if not ok then
            error(err)
        end
    end)

    it('rejects oversized HTTP headers and bodies before buffering them', function()
        local config = require('ministry.core.config')
        local request = require('ministry.transport.http.request')

        config.set({
            limits = { http_header_bytes = 16, http_body_bytes = 1024 },
            approval = { enabled = false, persistence = false },
        })
        local _, _, header_err = request.parse_request('POST /mcp HTTP/1.1\r\nX-Long: 1234567890\r\n\r\n')
        assert.are.equal('http headers exceed configured limit', header_err)

        config.set({
            limits = { http_header_bytes = 1024, http_body_bytes = 4 },
            approval = { enabled = false, persistence = false },
        })
        local _, _, body_err = request.parse_request('POST /mcp HTTP/1.1\r\nContent-Length: 5\r\n\r\n')
        assert.are.equal('http body exceeds configured limit', body_err)
    end)

    it('closes socket clients that exceed framing limits or partial-request deadlines', function()
        local plugin = require('ministry')
        plugin.setup({
            auto_start = false,
            limits = {
                request_timeout_ms = 10,
                socket_line_bytes = 8,
            },
            approval = { enabled = false, persistence = false },
        })

        local original_new_pipe = vim.uv.new_pipe
        local accept_callback = nil
        local current_client = nil
        local writes = {}
        local listener = {
            bind2 = function()
                return 0
            end,
            listen = function(_, _, callback)
                accept_callback = callback
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

        local function new_client()
            local closed = false
            local client = {
                read_start = function(self, callback)
                    self.read_callback = callback
                    return true
                end,
                read_stop = function() end,
                write = function(_, message)
                    table.insert(writes, vim.json.decode(message))
                end,
                is_closing = function()
                    return closed
                end,
                close = function()
                    closed = true
                end,
                closed = function()
                    return closed
                end,
            }
            return client
        end

        vim.uv.new_pipe = function()
            if accept_callback == nil then
                return listener
            end
            current_client = new_client()
            return current_client
        end

        local ok, err = xpcall(function()
            assert.is_true(plugin.start('socket'))

            accept_callback(nil)
            current_client.read_callback(nil, '123456789')
            assert.is_true(current_client.closed())
            assert.matches('line limit', writes[#writes].error.message, 1, true)

            accept_callback(nil)
            current_client.read_callback(nil, '{')
            assert.is_true(vim.wait(100, function()
                return current_client.closed()
            end, 1))
            assert.matches('deadline exceeded', writes[#writes].error.message, 1, true)
        end, debug.traceback)

        plugin.stop()
        vim.uv.new_pipe = original_new_pipe
        if not ok then
            error(err)
        end
    end)
end)
