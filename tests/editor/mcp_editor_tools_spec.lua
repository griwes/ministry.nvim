local function temp_dir()
    local base = vim.fs.joinpath(vim.uv.os_tmpdir(), 'ministry-editor-XXXXXX')
    return assert(vim.uv.fs_mkdtemp(base))
end

local function write_file(path, content)
    local handle = assert(io.open(path, 'wb'))
    assert(handle:write(content))
    handle:close()
end

local function read_file(path)
    local handle = assert(io.open(path, 'rb'))
    local content = assert(handle:read('*a'))
    handle:close()
    return content
end

local function delete_tree(path)
    vim.fn.delete(path, 'rf')
end

local function edit(path)
    vim.cmd.edit({ args = { path } })
end

describe('mcp editor tools', function()
    before_each(function()
        require('ministry').reset()
    end)

    it('computes and applies path-addressed edits as direct buffer modifications', function()
        local plugin = require('ministry')
        plugin.setup()

        local root = temp_dir()
        local path = vim.fs.joinpath(root, 'write-file.txt')
        write_file(path, 'before\n')

        edit(path)
        local bufnr = vim.api.nvim_get_current_buf()

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})
        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            hunks = diff_result and diff_result.hunks or {},
        }, {})

        assert.is_nil(diff_err)
        assert.is_nil(apply_err)
        assert.are.equal(bufnr, diff_result.bufnr)
        assert.are.equal(bufnr, apply_result.updated_buffer)
        assert.is_false(apply_result.reloaded_buffer)
        assert.is_true(apply_result.modified)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.is_true(vim.bo[bufnr].modified)
        assert.are.equal('before\n', read_file(path))

        vim.api.nvim_buf_delete(bufnr, { force = true })
        delete_tree(root)
    end)

    it('uses modified loaded buffers as the source of truth for path-addressed file tools', function()
        local plugin = require('ministry')
        plugin.setup()

        local root = temp_dir()
        local path = vim.fs.joinpath(root, 'write-file-unsaved-buffer.txt')
        write_file(path, 'disk\n')

        edit(path)
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'buffer draft', 'keep' })
        assert.is_true(vim.bo[bufnr].modified)

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'buffer draft\nkeep\nmore\n',
        }, {})
        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            hunks = diff_result and diff_result.hunks or {},
        }, {})
        local write_result, write_err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'exact\nreplacement\n',
        }, {})

        assert.is_nil(diff_err)
        assert.are.equal(bufnr, diff_result.bufnr)
        assert.are.same({
            {
                current_start = 3,
                current_count = 0,
                replacement = { 'more' },
            },
        }, diff_result.hunks)
        assert.is_nil(apply_err)
        assert.are.equal(bufnr, apply_result.updated_buffer)
        assert.is_false(apply_result.reloaded_buffer)
        assert.is_nil(write_err)
        assert.are.equal(bufnr, write_result.updated_buffer)
        assert.is_false(write_result.reloaded_buffer)
        assert.are.same({ 'exact', 'replacement' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.is_true(vim.bo[bufnr].modified)
        assert.are.equal('disk\n', read_file(path))

        vim.api.nvim_buf_delete(bufnr, { force = true })
        delete_tree(root)
    end)

    it('loads unloaded paths into hidden buffers for path-addressed edits', function()
        local plugin = require('ministry')
        plugin.setup()

        local root = temp_dir()
        local path = vim.fs.joinpath(root, 'write-file-unloaded.txt')
        write_file(path, 'before\n')

        local current_win = vim.api.nvim_get_current_win()
        local current_buf = vim.api.nvim_get_current_buf()
        local result, err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(err)
        assert.are.equal(current_win, vim.api.nvim_get_current_win())
        assert.are.equal(current_buf, vim.api.nvim_get_current_buf())
        assert.is_false(result.reloaded_buffer)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(result.updated_buffer, 0, -1, false))
        assert.is_true(vim.bo[result.updated_buffer].modified)
        assert.are.equal('before\n', read_file(path))

        vim.api.nvim_buf_delete(result.updated_buffer, { force = true })
        delete_tree(root)
    end)

    it('writes empty file content to the buffer without introducing a trailing newline', function()
        local plugin = require('ministry')
        plugin.setup()

        local root = temp_dir()
        local path = vim.fs.joinpath(root, 'empty-file.txt')
        write_file(path, 'before\n')

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = '',
        }, {})
        local result, err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            hunks = diff_result and diff_result.hunks or {},
        }, {})

        assert.is_nil(diff_err)
        assert.is_nil(err)
        assert.are.same({ '' }, vim.api.nvim_buf_get_lines(result.updated_buffer, 0, -1, false))
        assert.are.equal('before\n', read_file(path))

        vim.api.nvim_buf_delete(result.updated_buffer, { force = true })
        delete_tree(root)
    end)

    it('keeps write and apply-diff buffer tools distinct', function()
        local plugin = require('ministry')
        plugin.setup()

        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'before' })

        local write_result, write_err = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = bufnr,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(write_err)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.is_true(write_result.modified)
        assert.are.equal(bufnr, write_result.bufnr)
        assert.is_nil(write_result.applied_hunk_count)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'before' })
        vim.bo[bufnr].modified = false

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_buffer', {
            bufnr = bufnr,
            content = 'after\nvalue\n',
        }, {})
        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_buffer', {
            bufnr = bufnr,
            hunks = diff_result and diff_result.hunks or {},
        }, {})

        assert.is_nil(diff_err)
        assert.is_nil(apply_err)
        assert.is_true(apply_result.applied_hunk_count >= 1)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.is_true(apply_result.modified)
    end)

    it('applies zero-width insertions before the addressed line', function()
        local plugin = require('ministry')
        plugin.setup()

        local bufnr = vim.api.nvim_get_current_buf()

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'three' })

        local result, err = plugin.call_tool('neovim/editor/apply_diff_buffer', {
            bufnr = bufnr,
            hunks = {
                {
                    current_start = 2,
                    current_count = 0,
                    replacement = { 'two' },
                },
            },
        }, {})

        assert.is_nil(err)
        assert.is_true(result.modified)
        assert.are.same({ 'one', 'two', 'three' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('emits zero-width insertions before the following line', function()
        local plugin = require('ministry')
        plugin.setup()

        local bufnr = vim.api.nvim_get_current_buf()
        local current_lines = {
            'function M.product(items)',
            '    return total',
            'end',
            'function M.divide(a, b)',
            '    return a / b',
            'end',
        }
        local target_lines = {
            'function M.product(items)',
            '    return total',
            'end',
            '',
            'function M.divide(a, b)',
            '    return a / b',
            'end',
        }
        local target_content = table.concat(target_lines, '\n') .. '\n'

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_lines)

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_buffer', {
            bufnr = bufnr,
            content = target_content,
        }, {})
        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_buffer', {
            bufnr = bufnr,
            hunks = diff_result and diff_result.hunks or {},
        }, {})

        assert.is_nil(diff_err)
        assert.are.same({
            {
                current_start = 4,
                current_count = 0,
                replacement = { '' },
            },
        }, diff_result.hunks)
        assert.is_nil(apply_err)
        assert.is_true(apply_result.modified)
        assert.are.same(target_lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, current_lines)

        local write_result, write_err = plugin.call_tool('neovim/editor/write_buffer', {
            bufnr = bufnr,
            content = target_content,
        }, {})

        assert.is_nil(write_err)
        assert.is_true(write_result.modified)
        assert.are.same(target_lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('keeps write/apply file tools distinct', function()
        local plugin = require('ministry')
        plugin.setup()

        local root = temp_dir()
        local path = vim.fs.joinpath(root, 'write-apply-alias.txt')

        local write_result, write_err = plugin.call_tool('neovim/editor/write_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(write_err)
        assert.is_false(write_result.reloaded_buffer)
        assert.are.same({ 'after', 'value' }, vim.api.nvim_buf_get_lines(write_result.updated_buffer, 0, -1, false))
        assert.is_nil(io.open(path, 'rb'))

        local diff_result, diff_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\nmore\n',
        }, {})
        local apply_result, apply_err = plugin.call_tool('neovim/editor/apply_diff_file', {
            path = path,
            hunks = diff_result and diff_result.hunks or {},
        }, {})

        assert.is_nil(diff_err)
        assert.is_true(#diff_result.hunks >= 1)
        assert.is_nil(apply_err)
        assert.are.equal(vim.fs.normalize(path), apply_result.path)
        assert.is_false(apply_result.reloaded_buffer)
        assert.is_true(apply_result.applied_hunk_count >= 1)
        assert.is_nil(write_result.applied_hunk_count)
        assert.are.equal(write_result.updated_buffer, apply_result.updated_buffer)
        assert.are.same(
            { 'after', 'value', 'more' },
            vim.api.nvim_buf_get_lines(apply_result.updated_buffer, 0, -1, false)
        )

        local post_apply_diff, post_apply_err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\nmore\n',
        }, {})

        assert.is_nil(post_apply_err)
        assert.are.equal(0, #post_apply_diff.hunks)
        assert.is_nil(io.open(path, 'rb'))

        vim.api.nvim_buf_delete(apply_result.updated_buffer, { force = true })
        delete_tree(root)
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
                path = vim.fs.joinpath(temp_dir(), 'invalid-content.txt'),
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
    end)

    it('rejects removed current-buffer tools and apply-diff invalid arguments', function()
        local plugin = require('ministry')
        plugin.setup()

        local write_current_result, write_current_err = plugin.call_tool('neovim/editor/write_current_buffer', {
            content = 'after\n',
        }, {})
        local apply_current_result, apply_current_err = plugin.call_tool('neovim/editor/apply_diff_current_buffer', {
            content = 'after\n',
        }, {})
        local diff_current_result, diff_current_err = plugin.call_tool('neovim/editor/diff_current_buffer', {
            content = 'after\n',
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
                hunks = false,
            },
            {}
        )
        local apply_file_missing_path_result, apply_file_missing_path_err = plugin.call_tool(
            'neovim/editor/apply_diff_file',
            {
                hunks = {},
            },
            {}
        )
        local apply_file_invalid_path_result, apply_file_invalid_path_err = plugin.call_tool(
            'neovim/editor/apply_diff_file',
            {
                path = false,
                hunks = {},
            },
            {}
        )
        local apply_file_invalid_hunks_result, apply_file_invalid_hunks_err = plugin.call_tool(
            'neovim/editor/apply_diff_file',
            {
                path = vim.fs.joinpath(temp_dir(), 'invalid-hunks.txt'),
                hunks = false,
            },
            {}
        )

        assert.is_nil(write_current_result)
        assert.are.equal(-32601, write_current_err.code)
        assert.is_true(write_current_err.message:find('write_current_buffer', 1, true) ~= nil)
        assert.is_nil(apply_current_result)
        assert.are.equal(-32601, apply_current_err.code)
        assert.is_true(apply_current_err.message:find('apply_diff_current_buffer', 1, true) ~= nil)
        assert.is_nil(diff_current_result)
        assert.are.equal(-32601, diff_current_err.code)
        assert.is_true(diff_current_err.message:find('diff_current_buffer', 1, true) ~= nil)

        assert.is_nil(apply_buffer_missing_result)
        assert.are.equal(-32602, apply_buffer_missing_err.code)
        assert.are.equal('Invalid arguments: hunks must be a list', apply_buffer_missing_err.message)
        assert.is_nil(apply_buffer_invalid_result)
        assert.are.equal(-32602, apply_buffer_invalid_err.code)
        assert.are.equal('Invalid arguments: hunks must be a list', apply_buffer_invalid_err.message)

        assert.is_nil(apply_file_missing_path_result)
        assert.are.equal(-32602, apply_file_missing_path_err.code)
        assert.are.equal('Invalid arguments: path must be a string', apply_file_missing_path_err.message)
        assert.is_nil(apply_file_invalid_path_result)
        assert.are.equal(-32602, apply_file_invalid_path_err.code)
        assert.are.equal('Invalid arguments: path must be a string', apply_file_invalid_path_err.message)
        assert.is_nil(apply_file_invalid_hunks_result)
        assert.are.equal(-32602, apply_file_invalid_hunks_err.code)
        assert.are.equal('Invalid arguments: hunks must be a list', apply_file_invalid_hunks_err.message)
    end)

    it('diffs a missing file against empty buffer content', function()
        local plugin = require('ministry')
        plugin.setup()

        local path = vim.fs.joinpath(temp_dir(), 'missing-read.txt')
        local result, err = plugin.call_tool('neovim/editor/diff_file', {
            path = path,
            content = 'after\nvalue\n',
        }, {})

        assert.is_nil(err)
        assert.are.equal(vim.fs.normalize(path), result.path)
        assert.is_true(#result.hunks >= 1)
        assert.are.same({ 'after', 'value' }, result.hunks[1].replacement)

        vim.api.nvim_buf_delete(result.bufnr, { force = true })
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
            path = vim.fs.joinpath(temp_dir(), 'invalid-content.txt'),
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
