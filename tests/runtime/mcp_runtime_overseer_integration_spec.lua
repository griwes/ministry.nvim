local function read_json_resource(plugin, uri, request_id)
    local response = plugin.handle_request('resources/read', {
        uri = uri,
    }, request_id, {})
    assert(
        response and response.result and response.result.contents and response.result.contents[1],
        'missing resource response'
    )
    return vim.json.decode(response.result.contents[1].text)
end

local function wait_until(predicate, timeout_ms, message)
    local deadline = vim.uv.now() + timeout_ms
    while vim.uv.now() < deadline do
        if predicate() then
            return
        end
        vim.wait(50)
    end
    error(message)
end

describe('mcp overseer real-plugin integration', function()
    it('observes a real overseer.nvim task through the summary resource', function()
        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local lazy_dir = vim.fn.stdpath('data') .. '/lazy/overseer.nvim'
        if vim.fn.isdirectory(lazy_dir) == 0 then
            pending('overseer.nvim is not installed in the isolated lazy test root')
            return
        end
        vim.opt.runtimepath:prepend(lazy_dir)

        local overseer = require('overseer')
        overseer.setup({})

        local task = overseer.new_task({
            cmd = { 'sh', '-c', 'printf overseer-real-plugin' },
            name = 'Ministry Overseer Integration',
            cwd = vim.fn.getcwd(),
        })

        task:start()

        wait_until(function()
            local payload = read_json_resource(plugin, 'neovim/tasks://summary', 1)
            for _, entry in ipairs(payload.tasks or {}) do
                if entry.name == 'Ministry Overseer Integration' then
                    return true
                end
            end
            return false
        end, 10000, 'real overseer task did not appear in Ministry summary')

        local payload = read_json_resource(plugin, 'neovim/tasks://summary', 2)
        local found = nil
        for _, entry in ipairs(payload.tasks or {}) do
            if entry.name == 'Ministry Overseer Integration' then
                found = entry
                break
            end
        end

        assert(found ~= nil, 'expected real overseer task in summary payload')
        assert.are.same({ 'sh', '-c', 'printf overseer-real-plugin' }, found.cmd)
        assert.are.equal(vim.fs.normalize(vim.fn.getcwd()), found.cwd)

        vim.wait(200)
    end)
end)
