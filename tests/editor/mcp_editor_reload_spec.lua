describe('mcp', function()
    before_each(function()
        require('ministry').reset()
    end)
    it('terminates a running terminal on release', function()
        local plugin = require('ministry')
        plugin.setup({ enable_terminal_tools = true })

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
        local plugin = require('ministry')
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
        local result, err, warning = plugin.call_tool('neovim/editor/apply_diff_file', {
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
        local editor_io = require('ministry.builtin.editor.io')

        assert.are.same({}, editor_io.decode_content(''))
    end)

    it('writes empty file content without introducing a trailing newline', function()
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
        local editor_io = require('ministry.builtin.editor.io')
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

        local response = plugin.handle_request('tools/call', {
            name = 'neovim/editor/apply_diff_file',
            arguments = {
                path = path,
                content = 'after\nvalue\n',
            },
        }, 1, {})

        editor_io.reload_buffer = original_reload_buffer

        local read_handle = assert(io.open(path, 'rb'))
        local disk = assert(read_handle:read('*a'))
        read_handle:close()

        assert.is_nil(response.error)
        local result = response.result
        assert.is_not_nil(result)
        assert.are.same({
            {
                type = 'text',
                text = vim.json.encode({
                    path = path,
                    reloaded_buffer = false,
                }),
            },
        }, result.content)
        assert.are.same(reload_warning, result.warning)
        assert.are.equal('after\nvalue\n', disk)

        vim.fn.delete(root, 'rf')
    end)

    it('does not return a warning when apply_diff_file reload succeeds', function()
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
                        content = 'nested\n',
                    }, {})
                    assert.is_nil(nested_err)
                    assert.is_false(nested_result.reloaded_buffer)
                end
            end,
        })

        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local io_mod = require('ministry.builtin.editor.io')
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
        local io_mod = require('ministry.builtin.editor.io')
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
        local io_mod = require('ministry.builtin.editor.io')
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

    it('parses zero-length request bodies without consuming pipelined data', function()
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
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                'Content-Length: 0',
                '',
                'POST /mcp HTTP/1.1',
                'Host: 127.0.0.1',
                'Content-Type: application/json',
                'Content-Length: 33',
                '',
                '{"jsonrpc":"2.0","method":"ping"}',
            }, '\r\n')
        )

        vim.wait(1000, function()
            return #writes == 2
        end)

        assert.are.equal(2, #writes)
        assert.truthy(writes[1]:find('"code":-32700', 1, true) ~= nil)
        assert.truthy(writes[2]:find('204 No Content', 1, true) ~= nil)
    end)

    it('reloads a hidden file-backed buffer without window APIs', function()
        local io_mod = require('ministry.builtin.editor.io')
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
        local open_calls = 0
        vim.api.nvim_open_win = function(...)
            open_calls = open_calls + 1
            error('window APIs unavailable')
        end

        local reload_err = io_mod.reload_buffer(target_buf)

        vim.api.nvim_open_win = original_open_win

        assert.are.equal(0, open_calls)
        assert.is_nil(reload_err)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))

        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('prefers permission bits over fs_access when reloading a hidden buffer', function()
        local io_mod = require('ministry.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-readonly.txt'
        vim.fn.writefile({ 'before' }, path)

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        vim.cmd('enew')

        vim.fn.writefile({ 'after' }, path)

        local original_open_win = vim.api.nvim_open_win
        local original_getfperm = vim.fn.getfperm
        local original_uv = vim.uv and vim.deepcopy(vim.uv) or nil
        local original_loop = vim.loop and vim.deepcopy(vim.loop) or nil

        vim.api.nvim_open_win = function(...)
            error('window APIs unavailable')
        end
        vim.fn.getfperm = function(name)
            if name == path then
                return 'r--r--r--'
            end
            return original_getfperm(name)
        end
        if vim.uv and vim.uv.fs_access then
            vim.uv.fs_access = function(name, mode)
                if name == path and mode == 'W' then
                    return true
                end
                return original_uv.fs_access(name, mode)
            end
        elseif vim.loop and vim.loop.fs_access then
            vim.loop.fs_access = function(name, mode)
                if name == path and mode == 'W' then
                    return true
                end
                return original_loop.fs_access(name, mode)
            end
        end

        local reload_err = io_mod.reload_buffer(target_buf)

        vim.api.nvim_open_win = original_open_win
        vim.fn.getfperm = original_getfperm
        if original_uv then
            vim.uv = original_uv
        end
        if original_loop then
            vim.loop = original_loop
        end

        assert.is_nil(reload_err)
        assert.are.same({ 'after' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
        assert.is_true(vim.bo[target_buf].readonly)

        vim.bo[target_buf].readonly = false
        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('falls back to fs_access when filewritable reports not writable for a hidden buffer', function()
        local io_mod = require('ministry.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-filewritable-fallback.txt'
        vim.fn.writefile({ 'before' }, path)

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        vim.cmd('enew')

        vim.fn.writefile({ 'after' }, path)

        local original_open_win = vim.api.nvim_open_win
        local original_filewritable = vim.fn.filewritable
        local original_getfperm = vim.fn.getfperm
        local original_uv = vim.uv and vim.deepcopy(vim.uv) or nil
        local original_loop = vim.loop and vim.deepcopy(vim.loop) or nil

        vim.api.nvim_open_win = function(...)
            error('window APIs unavailable')
        end
        vim.fn.filewritable = function(name)
            if name == path then
                return 0
            end
            return original_filewritable(name)
        end
        vim.fn.getfperm = function(name)
            if name == path then
                return 'r--r--r--'
            end
            return original_getfperm(name)
        end
        if vim.uv and vim.uv.fs_access then
            vim.uv.fs_access = function(name, mode)
                if name == path and mode == 'W' then
                    return true
                end
                return original_uv.fs_access(name, mode)
            end
        elseif vim.loop and vim.loop.fs_access then
            vim.loop.fs_access = function(name, mode)
                if name == path and mode == 'W' then
                    return true
                end
                return original_loop.fs_access(name, mode)
            end
        end

        local reload_err = io_mod.reload_buffer(target_buf)

        vim.api.nvim_open_win = original_open_win
        vim.fn.filewritable = original_filewritable
        vim.fn.getfperm = original_getfperm
        if original_uv then
            vim.uv = original_uv
        end
        if original_loop then
            vim.loop = original_loop
        end

        assert.is_nil(reload_err)
        assert.are.same({ 'after' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
        assert.is_false(vim.bo[target_buf].readonly)

        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('refreshes file-backed buffer metadata when reloading a hidden buffer without window APIs', function()
        local io_mod = require('ministry.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local path = root .. '/hidden-reload-metadata.txt'
        local handle = assert(io.open(path, 'wb'))
        assert(handle:write('before\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local target_buf = vim.api.nvim_get_current_buf()
        vim.bo[target_buf].fileformat = 'dos'
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
        assert.are.equal('unix', vim.bo[target_buf].fileformat)

        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('reloads the hidden target buffer when reusing an existing fallback window', function()
        local io_mod = require('ministry.builtin.editor.io')
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')
        local target_path = root .. '/hidden-reload-target.txt'
        local visible_path = root .. '/hidden-reload-visible.txt'

        vim.fn.writefile({ 'target-before' }, target_path)
        vim.fn.writefile({ 'visible-before' }, visible_path)

        vim.cmd('edit ' .. vim.fn.fnameescape(target_path))
        local target_buf = vim.api.nvim_get_current_buf()
        vim.cmd('edit ' .. vim.fn.fnameescape(visible_path))
        local visible_buf = vim.api.nvim_get_current_buf()

        vim.fn.writefile({ 'target-after' }, target_path)
        vim.fn.writefile({ 'visible-after' }, visible_path)

        local original_open_win = vim.api.nvim_open_win
        vim.api.nvim_open_win = function(...)
            error('window APIs unavailable')
        end

        local reload_err = io_mod.reload_buffer(target_buf)

        vim.api.nvim_open_win = original_open_win

        assert.is_nil(reload_err)
        assert.are.same(visible_buf, vim.api.nvim_get_current_buf())
        assert.are.same({ 'target-after' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
        assert.are.same({ 'visible-before' }, vim.api.nvim_buf_get_lines(visible_buf, 0, -1, false))

        vim.api.nvim_buf_delete(target_buf, { force = true })
        vim.api.nvim_buf_delete(visible_buf, { force = true })
        vim.fn.delete(root, 'rf')
    end)

    it('does not clobber the current modified buffer when reloading a hidden buffer without window APIs', function()
        local io_mod = require('ministry.builtin.editor.io')
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
        local io_mod = require('ministry.builtin.editor.io')
        local bufnr = vim.api.nvim_create_buf(false, false)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'before' })

        local original_is_loaded = vim.api.nvim_buf_is_loaded
        local original_buf_call = vim.api.nvim_buf_call
        local original_win_findbuf = vim.fn.win_findbuf
        local original_tabpage_list_wins = vim.api.nvim_tabpage_list_wins
        local original_create_buf = vim.api.nvim_create_buf
        local original_open_win = vim.api.nvim_open_win
        local original_win_set_buf = vim.api.nvim_win_set_buf
        local original_win_call = vim.api.nvim_win_call
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
        vim.api.nvim_win_call = function(win, callback)
            if win == temp_win then
                return callback()
            end
            return original_win_call(win, callback)
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
        vim.api.nvim_win_call = original_win_call
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
        local io_mod = require('ministry.builtin.editor.io')
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

    it('preserves binary content when reloading a hidden buffer without a window', function()
        local io_mod = require('ministry.builtin.editor.io')
        local path = vim.fn.tempname()
        local handle = assert(io.open(path, 'wb'))
        assert.truthy(handle:write('before\0after\n'))
        handle:close()

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local bufnr = vim.api.nvim_get_current_buf()
        vim.cmd('enew')

        local original_is_loaded = vim.api.nvim_buf_is_loaded
        local original_buf_call = vim.api.nvim_buf_call
        local original_win_findbuf = vim.fn.win_findbuf
        local original_tabpage_list_wins = vim.api.nvim_tabpage_list_wins

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

        local reload_err = io_mod.reload_buffer(bufnr)

        vim.api.nvim_buf_is_loaded = original_is_loaded
        vim.api.nvim_buf_call = original_buf_call
        vim.fn.win_findbuf = original_win_findbuf
        vim.api.nvim_tabpage_list_wins = original_tabpage_list_wins

        assert.is_nil(reload_err)
        assert.are.same({ 'before\0after' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        vim.api.nvim_buf_delete(bufnr, { force = true })
        os.remove(path)
    end)

    it('keeps write and apply-diff current-buffer tools distinct', function()
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
        local plugin = require('ministry')
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
end)
