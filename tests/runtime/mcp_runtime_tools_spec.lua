describe('mcp', function()
    before_each(function()
        require('ministry').reset()
    end)
    it('implements identifier-based editor tools and real terminal tools', function()
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
        plugin.setup({ enable_terminal_tools = true })

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
        local runtime = require('ministry.builtin.terminal_runtime')
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
        local runtime = require('ministry.builtin.terminal_runtime')
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
        local runtime = require('ministry.builtin.terminal_runtime')
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
        local runtime = require('ministry.builtin.terminal_runtime')
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
        local runtime = require('ministry.builtin.terminal_runtime')
        local _, get_terminal = debug.getupvalue(runtime.output, 1)
        local _, terminals = debug.getupvalue(get_terminal, 1)
        local apply_completion = nil

        for index = 1, 10 do
            local name, value = debug.getupvalue(runtime.create, index)
            if name == 'apply_completion' then
                apply_completion = value
                break
            end
        end

        assert.is_function(apply_completion)

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

            apply_completion(terminals[case.terminal_id], case.completed)

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
        local runtime = require('ministry.builtin.terminal_runtime')
        local editor_io = require('ministry.builtin.editor.io')
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

    it('returns a structured error when terminal startup fails asynchronously', function()
        local runtime = require('ministry.builtin.terminal_runtime')
        local original_system = vim.system

        vim.system = function(command, opts, on_exit)
            if on_exit ~= nil then
                on_exit({
                    code = 127,
                    signal = 0,
                    stdout = '',
                    stderr = 'sh: missing-command: not found',
                })
            end
            return {
                wait = function()
                    return {
                        code = 127,
                        signal = 0,
                        stdout = '',
                        stderr = 'sh: missing-command: not found',
                    }
                end,
                kill = function() end,
            }
        end

        local result, err = runtime.create({ 'missing-command' })

        vim.system = original_system

        assert.is_nil(result)
        assert.are.same({
            code = -32000,
            message = 'sh: missing-command: not found',
        }, err)
    end)

    it('returns structured errors for terminal invalid arguments and released terminal lookups', function()
        local plugin = require('ministry')
        plugin.setup({ enable_terminal_tools = true })

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
end)
