describe('mcp dap builtin surfaces', function()
    local original_dap

    before_each(function()
        require('tests.helpers.ministry').reset()
        original_dap = package.loaded['dap']
    end)

    after_each(function()
        package.loaded['dap'] = original_dap
    end)

    it('returns debugger state through resources, templates, and tools with a dap runtime', function()
        local actions = {}

        package.loaded['dap'] = {
            breakpoints = {
                ['/repo/main.py'] = {
                    { line = 7, condition = 'x > 0' },
                },
            },
            session = function()
                return {
                    capabilities = {
                        supportsTerminateRequest = true,
                    },
                    current_thread = {
                        id = 4,
                    },
                    current_frame = {
                        id = 99,
                        name = 'main',
                        line = 7,
                        column = 1,
                        source = {
                            name = 'main.py',
                            path = '/repo/main.py',
                        },
                    },
                    request = function(_, command, arguments, callback)
                        if command == 'threads' then
                            callback(nil, {
                                threads = {
                                    {
                                        id = 4,
                                        name = 'Main Thread',
                                        stopped = true,
                                        reason = 'breakpoint',
                                        frame = {
                                            id = 99,
                                            name = 'main',
                                            line = 7,
                                            column = 1,
                                            source = {
                                                name = 'main.py',
                                                path = '/repo/main.py',
                                            },
                                        },
                                    },
                                },
                            })
                            return
                        end

                        if command == 'stackTrace' then
                            callback(nil, {
                                totalFrames = 1,
                                stackFrames = {
                                    {
                                        id = 99,
                                        name = 'main',
                                        line = 7,
                                        column = 1,
                                        source = {
                                            name = 'main.py',
                                            path = '/repo/main.py',
                                        },
                                    },
                                },
                            })
                            return
                        end

                        if command == 'scopes' then
                            assert.are.equal(99, arguments.frameId)
                            callback(nil, {
                                scopes = {
                                    {
                                        name = 'Locals',
                                        variablesReference = 33,
                                        expensive = false,
                                    },
                                },
                            })
                            return
                        end

                        if command == 'variables' then
                            assert.are.equal(33, arguments.variablesReference)
                            callback(nil, {
                                variables = {
                                    {
                                        name = 'answer',
                                        value = '42',
                                        type = 'int',
                                        variablesReference = 0,
                                    },
                                },
                            })
                            return
                        end

                        callback('unexpected command: ' .. command)
                    end,
                }
            end,
            continue = function()
                table.insert(actions, 'continue')
            end,
            pause = function()
                table.insert(actions, 'pause')
            end,
            step_over = function()
                table.insert(actions, 'step_over')
            end,
            step_into = function()
                table.insert(actions, 'step_into')
            end,
            step_out = function()
                table.insert(actions, 'step_out')
            end,
            terminate = function()
                table.insert(actions, 'terminate')
            end,
            disconnect = function()
                table.insert(actions, 'disconnect')
            end,
        }

        local plugin = require('ministry')
        require('tests.helpers.ministry').setup(plugin)

        local summary = plugin.handle_request('resources/read', {
            uri = 'neovim/dap://summary',
        }, 1, {})
        local summary_payload = vim.json.decode(summary.result.contents[1].text)
        assert.is_true(summary_payload.active)
        assert.are.equal(4, summary_payload.session.stopped_thread_id)
        assert.are.equal(99, summary_payload.session.current_frame.id)

        local breakpoints = plugin.handle_request('resources/read', {
            uri = 'neovim/dap://breakpoints',
        }, 2, {})
        local breakpoint_payload = vim.json.decode(breakpoints.result.contents[1].text)
        assert.are.equal('/repo/main.py', breakpoint_payload.breakpoints[1].path)
        assert.are.equal(7, breakpoint_payload.breakpoints[1].line)

        local threads = plugin.handle_request('resources/read', {
            uri = 'neovim/dap://threads',
        }, 3, {})
        local threads_payload = vim.json.decode(threads.result.contents[1].text)
        assert.are.equal(4, threads_payload.threads[1].id)

        local stack = plugin.handle_request('resources/templates/read', {
            uri = 'neovim/dap://stack/4',
        }, 4, {})
        local stack_payload = vim.json.decode(stack.result.contents[1].text)
        assert.are.equal(99, stack_payload.stack_frames[1].id)

        local scopes = plugin.handle_request('resources/templates/read', {
            uri = 'neovim/dap://scopes/99',
        }, 5, {})
        local scopes_payload = vim.json.decode(scopes.result.contents[1].text)
        assert.are.equal(33, scopes_payload.scopes[1].variables_reference)

        local variables = plugin.handle_request('resources/templates/read', {
            uri = 'neovim/dap://variables/33',
        }, 6, {})
        local variables_payload = vim.json.decode(variables.result.contents[1].text)
        assert.are.equal('answer', variables_payload.variables[1].name)

        local tool_names = {
            'neovim/dap/continue',
            'neovim/dap/pause',
            'neovim/dap/step_over',
            'neovim/dap/step_into',
            'neovim/dap/step_out',
            'neovim/dap/terminate',
            'neovim/dap/disconnect',
        }

        for index, name in ipairs(tool_names) do
            local result, err = plugin.call_tool(name, {}, {})
            assert.is_nil(err)
            assert.is_true(result.ok)
        end

        assert.are.same({
            'continue',
            'pause',
            'step_over',
            'step_into',
            'step_out',
            'terminate',
            'disconnect',
        }, actions)
    end)
end)
