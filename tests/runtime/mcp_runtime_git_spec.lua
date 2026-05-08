describe('mcp git builtin surfaces', function()
    local original_stratum
    local temp_path

    before_each(function()
        require('ministry').reset()
        original_stratum = package.loaded['stratum']
        temp_path = vim.fs.normalize(vim.fn.tempname() .. '.lua')
        vim.fn.writefile({ 'return true' }, temp_path)
        vim.cmd('edit ' .. vim.fn.fnameescape(temp_path))
    end)

    after_each(function()
        package.loaded['stratum'] = original_stratum
        pcall(vim.cmd, 'bdelete!')
        pcall(vim.fn.delete, temp_path)
    end)

    it('returns stable unavailable payloads when Stratum is absent', function()
        package.loaded['stratum'] = nil

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://repository',
        }, 1, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_false(payload.available)
        assert.are.equal('stratum', payload.provider)
        assert.are.equal(temp_path, payload.path)
        assert.are.equal('stratum.nvim is not available', payload.reason)

        local path_response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://path',
        }, 8, {})
        local path_payload = vim.json.decode(path_response.result.contents[1].text)

        assert.is_false(path_payload.available)
        assert.are.equal('stratum', path_payload.provider)
        assert.are.equal(temp_path, path_payload.path)
        assert.are.equal('stratum.nvim is not available', path_payload.reason)

        local overview_response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://overview',
        }, 17, {})
        local overview_payload = vim.json.decode(overview_response.result.contents[1].text)

        assert.is_false(overview_payload.available)
        assert.are.equal('stratum', overview_payload.provider)
        assert.are.equal(temp_path, overview_payload.path)
        assert.are.equal('stratum.nvim is not available', overview_payload.reason)
    end)

    it('returns Stratum repository state for the current buffer', function()
        local state_calls = {}
        package.loaded['stratum'] = {
            state = function(path)
                table.insert(state_calls, path)
                return {
                    status = 'connected',
                    stale = false,
                    repo = {
                        id = '/repos/project',
                        root = '/repos/project',
                    },
                    snapshot_version = 4,
                    snapshot = {
                        head = {
                            branch = 'main',
                        },
                        paths = {
                            staged = { 'staged.lua' },
                            unstaged = { 'changed.lua' },
                            untracked = { 'new.lua' },
                            conflicted = {},
                        },
                        upstream = {
                            ahead = 2,
                            behind = 1,
                        },
                    },
                }
            end,
            snapshot_summary = function(snapshot)
                return {
                    head_label = snapshot.head.branch,
                    branch = snapshot.head.branch,
                    staged = #snapshot.paths.staged,
                    unstaged = #snapshot.paths.unstaged,
                    untracked = #snapshot.paths.untracked,
                    conflicted = #snapshot.paths.conflicted,
                    ahead = snapshot.upstream.ahead,
                    behind = snapshot.upstream.behind,
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://repository',
        }, 2, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.are.same({ temp_path }, state_calls)
        assert.is_true(payload.available)
        assert.are.equal('connected', payload.status)
        assert.is_false(payload.stale)
        assert.are.equal(4, payload.snapshot_version)
        assert.are.equal('/repos/project', payload.repo.root)
        assert.are.equal('main', payload.summary.head_label)
        assert.are.equal(1, payload.summary.staged)
        assert.are.equal(1, payload.summary.unstaged)
        assert.are.equal(1, payload.summary.untracked)
        assert.are.equal(2, payload.summary.ahead)
        assert.are.equal(1, payload.summary.behind)
    end)

    it('returns a compact Stratum repository overview for the current buffer', function()
        local root = vim.fs.dirname(temp_path)
        local relative = vim.fs.basename(temp_path)
        package.loaded['stratum'] = {
            state = function()
                return {
                    status = 'connected',
                    stale = false,
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot_version = 16,
                    snapshot = {
                        head = {
                            kind = 'attached',
                            branch = 'main',
                            oid = 'local-oid',
                        },
                        headCommit = {
                            oid = 'local-oid',
                            summary = 'overview commit',
                            parentOids = { 'parent-oid' },
                        },
                        upstream = {
                            name = 'origin/main',
                            ahead = 3,
                            behind = 1,
                        },
                        operation = {
                            kind = 'merge',
                        },
                        branches = {
                            {
                                name = 'main',
                                kind = 'local',
                                isHead = true,
                                upstreamAhead = 3,
                                upstreamBehind = 1,
                            },
                            {
                                name = 'origin/main',
                                kind = 'remote',
                                isHead = false,
                            },
                        },
                        remotes = {
                            {
                                name = 'origin',
                            },
                        },
                        tags = {
                            {
                                name = 'v1',
                            },
                        },
                        stashes = {},
                        worktrees = {},
                        submodules = {},
                        paths = {
                            staged = { relative },
                            unstaged = { 'changed.lua' },
                            untracked = { 'new.lua' },
                            ignored = {},
                            conflicted = {},
                            conflicts = {},
                            entries = {
                                {
                                    path = relative,
                                    status = {
                                        indexModified = true,
                                    },
                                    diff = {
                                        added = 4,
                                        changed = 2,
                                        removed = 1,
                                    },
                                },
                            },
                        },
                    },
                }
            end,
            snapshot_summary = function(snapshot)
                return {
                    branch = snapshot.head.branch,
                    staged = #snapshot.paths.staged,
                    unstaged = #snapshot.paths.unstaged,
                    untracked = #snapshot.paths.untracked,
                    ahead = snapshot.upstream.ahead,
                    behind = snapshot.upstream.behind,
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://overview',
        }, 18, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal(temp_path, payload.path)
        assert.are.equal(relative, payload.relative_path)
        assert.are.equal(root, payload.repo.root)
        assert.are.equal(16, payload.snapshot_version)
        assert.are.equal('main', payload.summary.branch)
        assert.are.equal('main', payload.head.branch)
        assert.are.equal('overview commit', payload.headCommit.summary)
        assert.are.equal('origin/main', payload.upstream.name)
        assert.are.equal('merge', payload.operation.kind)
        assert.are.equal('main', payload.current_branch.name)
        assert.are.equal(2, payload.counts.refs.branches)
        assert.are.equal(1, payload.counts.refs.local_branches)
        assert.are.equal(1, payload.counts.refs.remote_branches)
        assert.are.equal(1, payload.counts.refs.remotes)
        assert.are.equal(1, payload.counts.refs.tags)
        assert.are.equal(1, payload.counts.paths.staged)
        assert.are.equal(1, payload.counts.paths.unstaged)
        assert.are.equal(1, payload.counts.paths.untracked)
        assert.is_true(payload.path_state.staged)
        assert.is_true(payload.path_state.dirty)
        assert.are.same({ 'staged' }, payload.path_state.categories)
        assert.are.equal(4, payload.diff.added)
        assert.are.equal(2, payload.diff.changed)
        assert.are.equal(1, payload.diff.removed)
        assert.are.equal(relative, payload.entry.path)
        assert.is_nil(payload.conflict)
        assert.is_nil(payload.branches)
        assert.is_nil(payload.paths)
    end)

    it('returns a compact Stratum repository overview through a read-only Git tool', function()
        local root = vim.fs.dirname(temp_path)
        local target = vim.fs.joinpath(root, 'subdir', 'file.lua')
        local state_calls = {}
        package.loaded['stratum'] = {
            state = function(path)
                table.insert(state_calls, path)
                return {
                    status = 'connected',
                    stale = true,
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot_version = 17,
                    last_error = 'refresh queued',
                    snapshot = {
                        head = {
                            kind = 'detached',
                            oid = 'detached-oid',
                        },
                        headCommit = {
                            oid = 'detached-oid',
                            summary = 'detached overview',
                            parentOids = {},
                        },
                        upstream = nil,
                        operation = {
                            kind = 'clean',
                        },
                        branches = {},
                        remotes = {},
                        tags = {},
                        stashes = {},
                        worktrees = {},
                        submodules = {},
                        paths = {
                            staged = {},
                            unstaged = { 'subdir/file.lua' },
                            untracked = {},
                            ignored = {},
                            conflicted = {},
                            conflicts = {},
                            entries = {
                                {
                                    path = 'subdir/file.lua',
                                    status = {
                                        workdirModified = true,
                                    },
                                },
                            },
                        },
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('tools/call', {
            name = 'neovim/git/overview',
            arguments = {
                path = target,
            },
        }, 19, {})
        local payload = vim.json.decode(response.result.content[1].text)

        assert.are.same({ target }, state_calls)
        assert.is_true(payload.available)
        assert.is_true(payload.stale)
        assert.are.equal('refresh queued', payload.last_error)
        assert.are.equal('subdir/file.lua', payload.relative_path)
        assert.are.equal('detached', payload.head.kind)
        assert.are.equal('detached overview', payload.headCommit.summary)
        assert.are.equal(1, payload.counts.paths.unstaged)
        assert.is_true(payload.path_state.unstaged)
        assert.is_true(payload.path_state.dirty)
        assert.are.equal('subdir/file.lua', payload.entry.path)
    end)

    it('rejects invalid Git overview tool arguments', function()
        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('tools/call', {
            name = 'neovim/git/overview',
            arguments = {
                path = false,
            },
        }, 20, {})

        assert.are.equal(-32602, response.error.code)
        assert.is_true(response.error.message:find('path must be a string', 1, true) ~= nil)
    end)

    it('returns Stratum ref state for the current buffer repository', function()
        local root = vim.fs.dirname(temp_path)
        package.loaded['stratum'] = {
            state = function()
                return {
                    status = 'connected',
                    stale = false,
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot_version = 14,
                    snapshot = {
                        head = {
                            kind = 'attached',
                            name = 'refs/heads/main',
                            branch = 'main',
                            oid = 'local-oid',
                        },
                        headCommit = {
                            oid = 'local-oid',
                            parentOids = { 'parent-oid' },
                            summary = 'current commit',
                            authorName = 'Ada',
                            authorEmail = 'ada@example.test',
                            timeSeconds = 123,
                        },
                        upstream = {
                            name = 'origin/main',
                            oid = 'remote-oid',
                            ahead = 2,
                            behind = 1,
                        },
                        operation = {
                            kind = 'clean',
                            heads = {},
                        },
                        remotes = {
                            {
                                name = 'origin',
                                url = 'https://example.test/repo.git',
                                pushUrl = 'ssh://example.test/repo.git',
                                defaultBranch = 'origin/main',
                                fetchRefspecs = { '+refs/heads/*:refs/remotes/origin/*' },
                                pushRefspecs = {},
                            },
                        },
                        branches = {
                            {
                                name = 'main',
                                kind = 'local',
                                isHead = true,
                                oid = 'local-oid',
                                upstream = 'origin/main',
                                upstreamAhead = 2,
                                upstreamBehind = 1,
                            },
                            {
                                name = 'origin/main',
                                kind = 'remote',
                                isHead = false,
                                oid = 'remote-oid',
                            },
                        },
                        tags = {
                            {
                                name = 'v1',
                            },
                        },
                        stashes = {
                            {
                                index = 0,
                                message = 'WIP on main',
                            },
                        },
                        worktrees = {
                            {
                                path = root,
                            },
                        },
                        submodules = {
                            {
                                name = 'vendor/lib',
                            },
                        },
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://refs',
        }, 13, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal(temp_path, payload.path)
        assert.are.equal(root, payload.repo.root)
        assert.are.equal(14, payload.snapshot_version)
        assert.are.equal('main', payload.head.branch)
        assert.are.equal('current commit', payload.headCommit.summary)
        assert.are.same({ 'parent-oid' }, payload.headCommit.parentOids)
        assert.are.equal('origin/main', payload.upstream.name)
        assert.are.equal(2, payload.upstream.ahead)
        assert.are.equal(1, payload.upstream.behind)
        assert.are.equal('main', payload.current_branch.name)
        assert.are.equal('origin/main', payload.current_branch.upstream)
        assert.is_true(payload.current_branch.isHead)
        assert.are.equal(2, payload.current_branch.upstreamAhead)
        assert.are.equal(1, payload.current_branch.upstreamBehind)
        assert.are.equal(2, payload.counts.branches)
        assert.are.equal(1, payload.counts.local_branches)
        assert.are.equal(1, payload.counts.remote_branches)
        assert.are.equal(1, payload.counts.head_branches)
        assert.are.equal(1, payload.counts.remotes)
        assert.are.equal(1, payload.counts.tags)
        assert.are.equal(1, payload.counts.stashes)
        assert.are.equal(1, payload.counts.worktrees)
        assert.are.equal(1, payload.counts.submodules)
        assert.are.equal('origin', payload.remotes[1].name)
        assert.are.equal('origin/main', payload.remotes[1].defaultBranch)
        assert.are.same({ '+refs/heads/*:refs/remotes/origin/*' }, payload.remotes[1].fetchRefspecs)
        assert.is_nil(payload.tags)
        assert.is_nil(payload.stashes)
        assert.is_nil(payload.worktrees)
        assert.is_nil(payload.submodules)
    end)

    it('returns Stratum ref state through a read-only Git tool', function()
        local root = vim.fs.dirname(temp_path)
        local target = vim.fs.joinpath(root, 'nested', 'file.lua')
        local state_calls = {}
        package.loaded['stratum'] = {
            state = function(path)
                table.insert(state_calls, path)
                return {
                    status = 'connected',
                    stale = true,
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot_version = 15,
                    last_error = 'refresh queued',
                    snapshot = {
                        head = {
                            kind = 'detached',
                            oid = 'detached-oid',
                        },
                        headCommit = {
                            oid = 'detached-oid',
                            parentOids = {},
                            summary = 'detached commit',
                            timeSeconds = 456,
                        },
                        upstream = nil,
                        operation = {
                            kind = 'rebase',
                            heads = {
                                {
                                    role = 'rebase',
                                    oid = 'rebase-oid',
                                },
                            },
                        },
                        remotes = {},
                        branches = {},
                        tags = {
                            {
                                name = 'v2',
                                oid = 'tag-oid',
                            },
                        },
                        stashes = {
                            {
                                index = 0,
                                oid = 'stash-oid',
                            },
                        },
                        worktrees = {
                            {
                                path = root,
                                branch = 'main',
                            },
                        },
                        submodules = {
                            {
                                name = 'vendor/lib',
                                path = 'vendor/lib',
                            },
                        },
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('tools/call', {
            name = 'neovim/git/list_refs',
            arguments = {
                path = target,
                include_tags = true,
                include_stashes = true,
                include_worktrees = true,
                include_submodules = true,
            },
        }, 14, {})
        local payload = vim.json.decode(response.result.content[1].text)

        assert.are.same({ target }, state_calls)
        assert.is_true(payload.available)
        assert.is_true(payload.stale)
        assert.are.equal('refresh queued', payload.last_error)
        assert.are.equal(15, payload.snapshot_version)
        assert.are.equal('detached', payload.head.kind)
        assert.are.equal('detached commit', payload.headCommit.summary)
        assert.are.equal('rebase', payload.operation.kind)
        assert.are.equal('v2', payload.tags[1].name)
        assert.are.equal('stash-oid', payload.stashes[1].oid)
        assert.are.equal(root, payload.worktrees[1].path)
        assert.are.equal('vendor/lib', payload.submodules[1].path)
    end)

    it('rejects invalid Git list refs tool arguments', function()
        local plugin = require('ministry')
        plugin.setup()

        local path_response = plugin.handle_request('tools/call', {
            name = 'neovim/git/list_refs',
            arguments = {
                path = false,
            },
        }, 15, {})
        local tags_response = plugin.handle_request('tools/call', {
            name = 'neovim/git/list_refs',
            arguments = {
                include_tags = 'yes',
            },
        }, 16, {})

        assert.are.equal(-32602, path_response.error.code)
        assert.is_true(path_response.error.message:find('path must be a string', 1, true) ~= nil)
        assert.are.equal(-32602, tags_response.error.code)
        assert.is_true(tags_response.error.message:find('include_tags must be a boolean', 1, true) ~= nil)
    end)

    it('returns Stratum changed paths for the current buffer repository', function()
        local root = vim.fs.dirname(temp_path)
        package.loaded['stratum'] = {
            state = function()
                return {
                    status = 'connected',
                    stale = false,
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot_version = 12,
                    snapshot = {
                        paths = {
                            staged = { 'staged.lua' },
                            unstaged = { 'changed.lua' },
                            untracked = { 'new.lua' },
                            ignored = { 'build/output.log' },
                            conflicted = { 'conflict.lua' },
                            conflicts = {
                                {
                                    path = 'conflict.lua',
                                },
                            },
                            entries = {
                                {
                                    path = 'staged.lua',
                                    status = {
                                        indexModified = true,
                                    },
                                },
                            },
                        },
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://paths',
        }, 9, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal(temp_path, payload.path)
        assert.are.equal(root, payload.repo.root)
        assert.are.equal(12, payload.snapshot_version)
        assert.are.equal(1, payload.counts.staged)
        assert.are.equal(1, payload.counts.unstaged)
        assert.are.equal(1, payload.counts.untracked)
        assert.are.equal(1, payload.counts.ignored)
        assert.are.equal(1, payload.counts.conflicted)
        assert.are.equal(1, payload.counts.conflicts)
        assert.are.equal(1, payload.counts.entries)
        assert.are.same({ 'staged.lua' }, payload.paths.staged)
        assert.are.same({ 'changed.lua' }, payload.paths.unstaged)
        assert.are.same({ 'new.lua' }, payload.paths.untracked)
        assert.are.same({ 'build/output.log' }, payload.paths.ignored)
        assert.are.same({ 'conflict.lua' }, payload.paths.conflicted)
        assert.is_nil(payload.entries)
        assert.is_nil(payload.conflicts)
    end)

    it('returns Stratum changed paths through a read-only Git tool', function()
        local root = vim.fs.dirname(temp_path)
        local target = vim.fs.joinpath(root, 'subdir', 'file.lua')
        local state_calls = {}
        package.loaded['stratum'] = {
            state = function(path)
                table.insert(state_calls, path)
                return {
                    status = 'connected',
                    stale = true,
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot_version = 13,
                    last_error = 'worker restarted',
                    snapshot = {
                        paths = {
                            staged = { 'old.lua' },
                            unstaged = {},
                            untracked = {},
                            ignored = {},
                            conflicted = { 'conflict.lua' },
                            conflicts = {
                                {
                                    path = 'conflict.lua',
                                },
                            },
                            entries = {
                                {
                                    path = 'old.lua',
                                    stagedNewPath = 'renamed.lua',
                                    status = {
                                        indexRenamed = true,
                                    },
                                },
                            },
                        },
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('tools/call', {
            name = 'neovim/git/list_paths',
            arguments = {
                path = target,
                include_entries = true,
            },
        }, 10, {})
        local payload = vim.json.decode(response.result.content[1].text)

        assert.are.same({ target }, state_calls)
        assert.is_true(payload.available)
        assert.is_true(payload.stale)
        assert.are.equal('worker restarted', payload.last_error)
        assert.are.equal(13, payload.snapshot_version)
        assert.are.same({ 'old.lua' }, payload.paths.staged)
        assert.are.equal('old.lua', payload.entries[1].path)
        assert.are.equal('renamed.lua', payload.entries[1].stagedNewPath)
        assert.are.equal('conflict.lua', payload.conflicts[1].path)
    end)

    it('rejects invalid Git list paths tool arguments', function()
        local plugin = require('ministry')
        plugin.setup()

        local path_response = plugin.handle_request('tools/call', {
            name = 'neovim/git/list_paths',
            arguments = {
                path = false,
            },
        }, 11, {})
        local entries_response = plugin.handle_request('tools/call', {
            name = 'neovim/git/list_paths',
            arguments = {
                include_entries = 'yes',
            },
        }, 12, {})

        assert.are.equal(-32602, path_response.error.code)
        assert.is_true(path_response.error.message:find('path must be a string', 1, true) ~= nil)
        assert.are.equal(-32602, entries_response.error.code)
        assert.is_true(entries_response.error.message:find('include_entries must be a boolean', 1, true) ~= nil)
    end)

    it('returns Stratum path state for the current buffer', function()
        local root = vim.fs.dirname(temp_path)
        local relative = vim.fs.basename(temp_path)
        package.loaded['stratum'] = {
            state = function()
                return {
                    status = 'connected',
                    stale = false,
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot_version = 9,
                    snapshot = {
                        paths = {
                            staged = { relative },
                            unstaged = { relative },
                            untracked = {},
                            ignored = {},
                            conflicted = { relative },
                            conflicts = {
                                {
                                    path = relative,
                                    ours = {
                                        path = relative,
                                        oid = 'ours',
                                        mode = 33188,
                                    },
                                },
                            },
                            entries = {
                                {
                                    path = relative,
                                    status = {
                                        indexModified = true,
                                        workdirModified = true,
                                        conflicted = true,
                                    },
                                    diff = {
                                        added = 2,
                                        changed = 3,
                                        removed = 1,
                                    },
                                },
                            },
                        },
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://path',
        }, 3, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_true(payload.available)
        assert.are.equal(temp_path, payload.path)
        assert.are.equal(relative, payload.relative_path)
        assert.are.equal(9, payload.snapshot_version)
        assert.is_true(payload.path_state.dirty)
        assert.is_true(payload.path_state.staged)
        assert.is_true(payload.path_state.unstaged)
        assert.is_true(payload.path_state.conflicted)
        assert.are.same({ 'staged', 'unstaged', 'conflicted' }, payload.path_state.categories)
        assert.are.equal(2, payload.diff.added)
        assert.are.equal(3, payload.diff.changed)
        assert.are.equal(1, payload.diff.removed)
        assert.are.equal(relative, payload.entry.path)
        assert.are.equal(relative, payload.conflict.path)
    end)

    it('returns Stratum path state through a read-only Git tool', function()
        local root = vim.fs.dirname(temp_path)
        local target = vim.fs.joinpath(root, 'renamed.lua')
        local state_calls = {}
        package.loaded['stratum'] = {
            state = function(path)
                table.insert(state_calls, path)
                return {
                    status = 'connected',
                    repo = {
                        id = root,
                        root = root,
                    },
                    snapshot = {
                        paths = {
                            staged = { 'old.lua' },
                            unstaged = {},
                            untracked = {},
                            ignored = {},
                            conflicted = {},
                            entries = {
                                {
                                    path = 'old.lua',
                                    stagedNewPath = 'renamed.lua',
                                    status = {
                                        indexRenamed = true,
                                    },
                                },
                            },
                        },
                    },
                }
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('tools/call', {
            name = 'neovim/git/path_state',
            arguments = {
                path = target,
            },
        }, 4, {})
        local payload = vim.json.decode(response.result.content[1].text)

        assert.are.same({ target }, state_calls)
        assert.is_true(payload.available)
        assert.are.equal('renamed.lua', payload.relative_path)
        assert.is_true(payload.path_state.staged)
        assert.is_true(payload.path_state.dirty)
        assert.are.equal('old.lua', payload.entry.path)
        assert.are.equal('renamed.lua', payload.entry.stagedNewPath)
    end)

    it('rejects invalid Git path state tool arguments', function()
        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('tools/call', {
            name = 'neovim/git/path_state',
            arguments = {
                path = 42,
            },
        }, 5, {})

        assert.are.equal(-32602, response.error.code)
        assert.is_true(response.error.message:find('path must be a string', 1, true) ~= nil)
    end)

    it('surfaces Stratum repository errors without failing the resource read', function()
        package.loaded['stratum'] = {
            state = function()
                return nil, 'path is not inside a Git repository'
            end,
            snapshot_summary = function()
                error('should not summarize absent state')
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://repository',
        }, 6, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_false(payload.available)
        assert.are.equal('path is not inside a Git repository', payload.reason)
    end)

    it('surfaces thrown Stratum errors as stable unavailable payloads', function()
        package.loaded['stratum'] = {
            state = function()
                error('stratum exploded')
            end,
        }

        local plugin = require('ministry')
        plugin.setup()

        local response = plugin.handle_request('resources/read', {
            uri = 'neovim/git://repository',
        }, 7, {})
        local payload = vim.json.decode(response.result.contents[1].text)

        assert.is_nil(response.error)
        assert.is_false(payload.available)
        assert.are.equal('stratum', payload.provider)
        assert.is_true(payload.reason:find('stratum exploded', 1, true) ~= nil)
    end)
end)
