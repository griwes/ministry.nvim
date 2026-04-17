describe('mcp lsp builtin surfaces', function()
    local original_get_clients
    local original_get_client_by_id
    local original_buf_request_sync
    local original_make_text_document_params
    local original_diagnostic_get

    before_each(function()
        require('ministry').reset()
        original_get_clients = vim.lsp.get_clients
        original_get_client_by_id = vim.lsp.get_client_by_id
        original_buf_request_sync = vim.lsp.buf_request_sync
        original_make_text_document_params = vim.lsp.util.make_text_document_params
        original_diagnostic_get = vim.diagnostic.get
    end)

    after_each(function()
        vim.lsp.get_clients = original_get_clients
        vim.lsp.get_client_by_id = original_get_client_by_id
        vim.lsp.buf_request_sync = original_buf_request_sync
        vim.lsp.util.make_text_document_params = original_make_text_document_params
        vim.diagnostic.get = original_diagnostic_get
    end)

    it('returns a lightweight lsp summary resource', function()
        local plugin = require('ministry')
        plugin.setup()

        local bufnr = vim.api.nvim_get_current_buf()
        local path = vim.fn.tempname() .. '.lua'
        vim.api.nvim_buf_set_name(bufnr, path)

        local clients = {
            {
                id = 7,
                name = 'lua_ls',
                config = {
                    root_dir = '/repo',
                    workspace_folders = {
                        { name = 'repo', uri = 'file:///repo' },
                    },
                },
                attached_buffers = {
                    [bufnr] = true,
                },
            },
        }

        vim.lsp.get_clients = function(opts)
            if opts and opts.bufnr == bufnr then
                return clients
            end

            return clients
        end

        local by_id = {}
        for _, client in ipairs(clients) do
            by_id[client.id] = client
        end
        vim.lsp.get_client_by_id = function(id)
            return by_id[id]
        end

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/lsp://summary',
        }, 11, {})

        local payload = vim.json.decode(response.result.contents[1].text)

        assert.are.equal(path, payload.current_buffer.path)
        assert.are.equal(1, #payload.clients)
        assert.are.equal('lua_ls', payload.clients[1].name)
        assert.are.equal('/repo', payload.clients[1].root_dir)
        assert.are.equal('/repo', payload.clients[1].workspace_folders[1].path)
        assert.are.equal(bufnr, payload.current_buffer_clients[1].attached_buffers[1])
    end)

    it(
        'returns diagnostics, actions, symbols, rename edits, workspace symbols, and locations through lsp tools',
        function()
            local plugin = require('ministry')
            plugin.setup()

            local bufnr = vim.api.nvim_get_current_buf()
            local path = vim.fn.tempname() .. '.lua'
            vim.api.nvim_buf_set_name(bufnr, path)

            local clients = {
                {
                    id = 7,
                    name = 'lua_ls',
                    config = {
                        root_dir = '/repo',
                        workspace_folders = {
                            { name = 'repo', uri = 'file:///repo' },
                        },
                    },
                    attached_buffers = {
                        [bufnr] = true,
                    },
                    request_sync = function(_, method, params)
                        assert.are.equal('workspace/symbol', method)
                        assert.are.equal('needle', params.query)
                        return {
                            result = {
                                {
                                    name = 'WorkspaceThing',
                                    kind = 12,
                                    location = {
                                        uri = 'file:///repo/workspace.lua',
                                        range = {
                                            start = { line = 3, character = 1 },
                                            ['end'] = { line = 3, character = 9 },
                                        },
                                    },
                                },
                            },
                        }
                    end,
                },
            }

            vim.lsp.get_clients = function(opts)
                if opts and opts.bufnr == bufnr then
                    return clients
                end

                return clients
            end

            local by_id = {}
            for _, client in ipairs(clients) do
                by_id[client.id] = client
            end
            vim.lsp.get_client_by_id = function(id)
                return by_id[id]
            end

            vim.lsp.util.make_text_document_params = function(target_bufnr)
                return {
                    textDocument = {
                        uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(target_bufnr)),
                    },
                }
            end

            vim.diagnostic.get = function(target_bufnr)
                if target_bufnr == nil then
                    return {
                        {
                            bufnr = bufnr,
                            lnum = 1,
                            end_lnum = 1,
                            col = 2,
                            end_col = 7,
                            severity = vim.diagnostic.severity.WARN,
                            source = 'lua_ls',
                            code = 'unused-local',
                            message = 'unused local value',
                        },
                    }
                end

                return {
                    {
                        bufnr = target_bufnr,
                        lnum = 1,
                        end_lnum = 1,
                        col = 2,
                        end_col = 7,
                        severity = vim.diagnostic.severity.WARN,
                        source = 'lua_ls',
                        code = 'unused-local',
                        message = 'unused local value',
                    },
                }
            end

            vim.lsp.buf_request_sync = function(target_bufnr, method, params)
                assert.are.equal(bufnr, target_bufnr)

                if method == 'textDocument/documentSymbol' then
                    return {
                        [7] = {
                            result = {
                                {
                                    name = 'Thing',
                                    kind = 5,
                                    range = {
                                        start = { line = 0, character = 0 },
                                        ['end'] = { line = 4, character = 0 },
                                    },
                                    selectionRange = {
                                        start = { line = 0, character = 9 },
                                        ['end'] = { line = 0, character = 14 },
                                    },
                                    children = {},
                                },
                            },
                        },
                    }
                end

                if method == 'textDocument/codeAction' then
                    return {
                        [7] = {
                            result = {
                                {
                                    title = 'Fix thing',
                                    kind = 'quickfix',
                                    isPreferred = true,
                                    edit = {
                                        changes = {
                                            ['file:///repo/thing.lua'] = {
                                                {
                                                    range = {
                                                        start = { line = 1, character = 2 },
                                                        ['end'] = { line = 1, character = 7 },
                                                    },
                                                    newText = 'fixed',
                                                },
                                            },
                                        },
                                        changeAnnotations = {
                                            fix = {
                                                label = 'Fix issue',
                                            },
                                        },
                                    },
                                },
                            },
                        },
                        [8] = {
                            error = {
                                code = -32801,
                                message = 'code action timeout',
                            },
                        },
                    }
                end

                if method == 'textDocument/rename' then
                    assert.are.equal('RenamedThing', params.newName)
                    return {
                        [7] = {
                            result = {
                                documentChanges = {
                                    {
                                        textDocument = {
                                            uri = 'file:///repo/thing.lua',
                                            version = 12,
                                        },
                                        edits = {
                                            {
                                                range = {
                                                    start = { line = 10, character = 1 },
                                                    ['end'] = { line = 10, character = 8 },
                                                },
                                                newText = 'RenamedThing',
                                                annotationId = 'rename-main',
                                            },
                                        },
                                    },
                                    {
                                        kind = 'rename',
                                        oldUri = 'file:///repo/old.lua',
                                        newUri = 'file:///repo/new.lua',
                                        options = {
                                            overwrite = true,
                                            ignoreIfExists = false,
                                        },
                                        annotationId = 'rename-file',
                                    },
                                },
                                changeAnnotations = {
                                    ['rename-main'] = {
                                        label = 'Rename main symbol',
                                    },
                                },
                            },
                        },
                        [8] = {
                            error = {
                                code = -32802,
                                message = 'rename failed elsewhere',
                            },
                        },
                    }
                end

                assert.are.equal(4, params.position.line)
                assert.are.equal(2, params.position.character)

                local method_to_result = {
                    ['textDocument/definition'] = {
                        uri = 'file:///repo/thing.lua',
                        range = {
                            start = { line = 10, character = 1 },
                            ['end'] = { line = 10, character = 8 },
                        },
                    },
                    ['textDocument/declaration'] = {
                        targetUri = 'file:///repo/decl.lua',
                        targetRange = {
                            start = { line = 2, character = 0 },
                            ['end'] = { line = 2, character = 6 },
                        },
                        targetSelectionRange = {
                            start = { line = 2, character = 0 },
                            ['end'] = { line = 2, character = 6 },
                        },
                    },
                    ['textDocument/typeDefinition'] = {
                        uri = 'file:///repo/types.lua',
                        range = {
                            start = { line = 5, character = 1 },
                            ['end'] = { line = 5, character = 9 },
                        },
                    },
                    ['textDocument/implementation'] = {
                        uri = 'file:///repo/impl.lua',
                        range = {
                            start = { line = 7, character = 1 },
                            ['end'] = { line = 7, character = 9 },
                        },
                    },
                    ['textDocument/references'] = {
                        {
                            uri = 'file:///repo/ref.lua',
                            range = {
                                start = { line = 8, character = 3 },
                                ['end'] = { line = 8, character = 10 },
                            },
                        },
                    },
                }

                if method == 'textDocument/references' then
                    assert.is_true(params.context.includeDeclaration)
                end

                return {
                    [7] = {
                        result = method_to_result[method],
                    },
                    [8] = {
                        error = {
                            code = -32800,
                            message = 'secondary client failed',
                        },
                    },
                }
            end

            local diagnostics = plugin.call_tool('neovim/lsp/list_diagnostics', {
                bufnr = bufnr,
            }, {})
            local document_symbols = plugin.call_tool('neovim/lsp/document_symbols', {
                bufnr = bufnr,
            }, {})
            local code_actions = plugin.call_tool('neovim/lsp/code_actions', {
                bufnr = bufnr,
                line = 4,
                character = 2,
            }, {})
            local workspace_symbols = plugin.call_tool('neovim/lsp/workspace_symbols', {
                query = 'needle',
            }, {})
            local rename = plugin.call_tool('neovim/lsp/rename', {
                bufnr = bufnr,
                line = 4,
                character = 2,
                new_name = 'RenamedThing',
            }, {})
            local definitions = plugin.call_tool('neovim/lsp/definitions', {
                bufnr = bufnr,
                line = 4,
                character = 2,
            }, {})
            local declarations = plugin.call_tool('neovim/lsp/declarations', {
                bufnr = bufnr,
                line = 4,
                character = 2,
            }, {})
            local type_definitions = plugin.call_tool('neovim/lsp/type_definitions', {
                bufnr = bufnr,
                line = 4,
                character = 2,
            }, {})
            local implementations = plugin.call_tool('neovim/lsp/implementations', {
                bufnr = bufnr,
                line = 4,
                character = 2,
            }, {})
            local references = plugin.call_tool('neovim/lsp/references', {
                bufnr = bufnr,
                line = 4,
                character = 2,
                include_declaration = true,
            }, {})

            assert.are.equal(path, diagnostics.path)
            assert.are.equal('warn', diagnostics.diagnostics[1].severity_name)
            assert.are.equal('unused local value', diagnostics.diagnostics[1].message)

            assert.are.equal('lua_ls', document_symbols.clients[1].client_name)
            assert.are.equal('Thing', document_symbols.clients[1].symbols[1].name)

            assert.are.equal('Fix thing', code_actions.actions[1].title)
            assert.is_true(code_actions.actions[1].has_edit)
            assert.are.equal('/repo/thing.lua', code_actions.actions[1].edit.changes[1].path)
            assert.are.equal('Fix issue', code_actions.actions[1].edit.change_annotations.fix.label)
            assert.are.equal('code action timeout', code_actions.errors[1].message)

            assert.are.equal('needle', workspace_symbols.query)
            assert.are.equal('WorkspaceThing', workspace_symbols.clients[1].symbols[1].name)
            assert.are.equal('/repo/workspace.lua', workspace_symbols.clients[1].symbols[1].location.path)
            assert.are.equal(0, #workspace_symbols.errors)

            assert.are.equal('RenamedThing', rename.new_name)
            assert.are.equal('/repo/thing.lua', rename.edits[1].workspace_edit.document_changes[1].path)
            assert.are.equal('rename', rename.edits[1].workspace_edit.document_changes[2].kind)
            assert.is_true(rename.edits[1].workspace_edit.document_changes[2].options.overwrite)
            assert.are.equal('rename failed elsewhere', rename.errors[1].message)

            assert.are.equal('/repo/thing.lua', definitions.locations[1].path)
            assert.are.equal('secondary client failed', definitions.errors[1].message)
            assert.are.equal('/repo/decl.lua', declarations.locations[1].path)
            assert.are.equal('/repo/types.lua', type_definitions.locations[1].path)
            assert.are.equal('/repo/impl.lua', implementations.locations[1].path)
            assert.are.equal('/repo/ref.lua', references.locations[1].path)
            assert.are.equal('lua_ls', references.locations[1].client_name)
        end
    )

    it('rejects lsp tool buffer arguments when the buffer id is invalid', function()
        local plugin = require('ministry')
        plugin.setup()

        local result, err = plugin.call_tool('neovim/lsp/document_symbols', {
            bufnr = 999999,
        }, {})

        assert.is_nil(result)
        assert.are.equal(-32000, err.code)
        assert.is_true(err.message:find('Invalid buffer id', 1, true) ~= nil)
    end)

    it('rejects negative lsp positions before forwarding requests', function()
        local plugin = require('ministry')
        plugin.setup()

        local bufnr = vim.api.nvim_get_current_buf()
        local path = vim.fn.tempname() .. '.lua'
        vim.api.nvim_buf_set_name(bufnr, path)

        vim.lsp.buf_request_sync = function()
            error('buf_request_sync should not be called for invalid positions')
        end

        local result, err = plugin.call_tool('neovim/lsp/definitions', {
            bufnr = bufnr,
            line = -1,
            character = -2,
        }, {})

        assert.is_nil(result)
        assert.are.equal(-32602, err.code)
        assert.is_true(err.message:find('non%-negative integer') ~= nil)
    end)

    it('rejects negative lsp range end positions before forwarding code-action requests', function()
        local plugin = require('ministry')
        plugin.setup()

        local bufnr = vim.api.nvim_get_current_buf()
        local path = vim.fn.tempname() .. '.lua'
        vim.api.nvim_buf_set_name(bufnr, path)

        vim.lsp.buf_request_sync = function()
            error('buf_request_sync should not be called for invalid range end positions')
        end

        local result, err = plugin.call_tool('neovim/lsp/code_actions', {
            bufnr = bufnr,
            line = 1,
            character = 0,
            end_line = -1,
        }, {})

        assert.is_nil(result)
        assert.are.equal(-32602, err.code)
        assert.is_true(err.message:find('non%-negative integer') ~= nil)

        local result_end_char, err_end_char = plugin.call_tool('neovim/lsp/code_actions', {
            bufnr = bufnr,
            line = 1,
            character = 0,
            end_character = -1,
        }, {})

        assert.is_nil(result_end_char)
        assert.are.equal(-32602, err_end_char.code)
        assert.is_true(err_end_char.message:find('non%-negative integer') ~= nil)
    end)

    it('surfaces top-level request timeout errors on lsp tools', function()
        local plugin = require('ministry')
        plugin.setup()

        local bufnr = vim.api.nvim_get_current_buf()
        local path = vim.fn.tempname() .. '.lua'
        vim.api.nvim_buf_set_name(bufnr, path)

        local clients = {
            {
                id = 7,
                name = 'lua_ls',
                config = { root_dir = '/repo' },
                attached_buffers = {
                    [bufnr] = true,
                },
                request_sync = function()
                    return nil, 'workspace symbol timeout'
                end,
            },
        }

        vim.lsp.get_clients = function(opts)
            if opts and opts.bufnr == bufnr then
                return clients
            end

            return clients
        end

        local by_id = {}
        for _, client in ipairs(clients) do
            by_id[client.id] = client
        end
        vim.lsp.get_client_by_id = function(id)
            return by_id[id]
        end

        vim.lsp.util.make_text_document_params = function(target_bufnr)
            return {
                textDocument = {
                    uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(target_bufnr)),
                },
            }
        end

        vim.diagnostic.get = function()
            return {}
        end

        vim.lsp.buf_request_sync = function()
            return nil, 'request timed out'
        end

        local definitions = plugin.call_tool('neovim/lsp/definitions', {
            bufnr = bufnr,
            line = 0,
            character = 0,
        }, {})
        local code_actions = plugin.call_tool('neovim/lsp/code_actions', {
            bufnr = bufnr,
            line = 0,
            character = 0,
        }, {})
        local rename = plugin.call_tool('neovim/lsp/rename', {
            bufnr = bufnr,
            line = 0,
            character = 0,
            new_name = 'OtherName',
        }, {})
        local document_symbols = plugin.call_tool('neovim/lsp/document_symbols', {
            bufnr = bufnr,
        }, {})
        local workspace_symbols = plugin.call_tool('neovim/lsp/workspace_symbols', {
            query = 'needle',
        }, {})

        assert.are.equal('request timed out', definitions.errors[1].message)
        assert.are.equal('request timed out', code_actions.errors[1].message)
        assert.are.equal('request timed out', rename.errors[1].message)
        assert.are.equal('request timed out', document_symbols.errors[1].message)
        assert.are.equal('workspace symbol timeout', workspace_symbols.errors[1].message)
    end)
end)
