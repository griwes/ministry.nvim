describe('mcp overseer builtin surfaces', function()
    local original_overseer

    before_each(function()
        require('ministry').reset()
        original_overseer = package.loaded['overseer']
    end)

    after_each(function()
        package.loaded['overseer'] = original_overseer
    end)

    it('returns a lightweight Overseer task summary resource', function()
        package.loaded['overseer'] = {
            list_tasks = function()
                return {
                    {
                        id = 2,
                        name = 'cargo test',
                        status = 'RUNNING',
                        result = nil,
                        cmd = { 'cargo', 'test' },
                        cwd = '/repo',
                        strategy = 'terminal',
                        metadata = {
                            terminalia = {
                                context_id = 'ctx:1',
                                context_kind = 'host',
                            },
                        },
                        is_running = function()
                            return true
                        end,
                        is_complete = function()
                            return false
                        end,
                    },
                    {
                        id = 1,
                        name = 'cmake build',
                        status = 'SUCCESS',
                        result = 'SUCCESS',
                        cmd = { 'cmake', '--build', 'build' },
                        cwd = '/repo',
                        strategy = 'jobstart',
                        is_running = function()
                            return false
                        end,
                        is_complete = function()
                            return true
                        end,
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/tasks://summary',
        }, 1, {})

        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal(2, #payload.tasks)
        assert.are.equal(1, payload.active_task_count)
        assert.is_true(payload.has_active_tasks)
        assert.are.equal(1, payload.status_counts.RUNNING)
        assert.are.equal(1, payload.status_counts.SUCCESS)
        assert.are.equal(1, #payload.active_tasks)
        assert.are.equal('cargo test', payload.tasks[1].name)
        assert.are.equal('cmake build', payload.tasks[2].name)
        assert.are.equal('cargo test', payload.active_tasks[1].name)
        assert.is_true(payload.active_tasks[1].is_running)
        assert.is_false(payload.active_tasks[1].is_complete)
        assert.are.equal('/repo', payload.tasks[1].cwd)
        assert.are.same({ 'cargo', 'test' }, payload.tasks[1].cmd)
        assert.are.equal('ctx:1', payload.tasks[1].metadata.terminalia.context_id)
    end)

    it('reports unavailable Overseer state cleanly when overseer.nvim is absent', function()
        package.loaded['overseer'] = nil

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/tasks://summary',
        }, 2, {})

        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_false(payload.available)
        assert.are.equal(0, payload.active_task_count)
        assert.is_false(payload.has_active_tasks)
        assert.are.same({}, payload.active_tasks)
        assert.are.same({}, payload.status_counts)
        assert.are.same({}, payload.tasks)
    end)
end)
