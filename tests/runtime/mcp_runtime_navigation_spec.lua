describe('mcp navigation builtin surfaces', function()
    local temp_path
    local original_cwd

    before_each(function()
        require('ministry').reset()
        original_cwd = vim.fn.getcwd()
        temp_path = vim.fs.normalize(vim.fn.tempname() .. '.lua')
        vim.fn.writefile({ 'first', 'second', 'third' }, temp_path)
        vim.cmd('edit ' .. vim.fn.fnameescape(temp_path))
    end)

    after_each(function()
        pcall(vim.cmd, 'delmarks aA')
        pcall(vim.cmd, 'bdelete!')
        pcall(vim.fn.delete, temp_path)
        if original_cwd ~= nil then
            vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
        end
    end)

    it('returns structured local and global marks', function()
        vim.api.nvim_win_set_cursor(0, { 2, 1 })
        vim.cmd("normal! ma")
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        vim.cmd("normal! mA")

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/navigation://marks',
        }, 1, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.are.equal(temp_path, payload.current_buffer)
        assert.is_true(#payload.local_marks >= 1)
        assert.is_true(#payload.global_marks >= 1)

        local local_mark = nil
        for _, mark in ipairs(payload.local_marks) do
            if mark.mark == 'a' then
                local_mark = mark
                break
            end
        end

        local global_mark = nil
        for _, mark in ipairs(payload.global_marks) do
            if mark.mark == 'A' then
                global_mark = mark
                break
            end
        end

        assert.are.equal(temp_path, local_mark.path)
        assert.are.equal(2, local_mark.line)
        assert.are.equal(temp_path, global_mark.path)
        assert.are.equal(3, global_mark.line)
    end)

    it('returns a stable empty payload when no marks are set', function()
        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/navigation://marks',
        }, 2, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.are.equal(temp_path, payload.current_buffer)
        assert.are.same({}, payload.local_marks)
        assert.are.same({}, payload.global_marks)
    end)
end)
