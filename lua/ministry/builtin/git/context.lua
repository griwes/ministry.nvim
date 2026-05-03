local M = {}

local path_state_keys = { 'staged', 'unstaged', 'untracked', 'ignored', 'conflicted' }
local path_alias_keys = {
    'path',
    'stagedOldPath',
    'stagedNewPath',
    'workdirOldPath',
    'workdirNewPath',
    'staged_old_path',
    'staged_new_path',
    'workdir_old_path',
    'workdir_new_path',
}
local staged_status_keys = {
    'indexNew',
    'indexModified',
    'indexDeleted',
    'indexRenamed',
    'indexTypechange',
    'index_new',
    'index_modified',
    'index_deleted',
    'index_renamed',
    'index_typechange',
}
local unstaged_status_keys = {
    'workdirModified',
    'workdirDeleted',
    'workdirTypechange',
    'workdirRenamed',
    'workdirUnreadable',
    'workdir_modified',
    'workdir_deleted',
    'workdir_typechange',
    'workdir_renamed',
    'workdir_unreadable',
}
local untracked_status_keys = { 'workdirNew', 'workdir_new' }
local ignored_status_keys = { 'ignored' }
local conflicted_status_keys = { 'conflicted' }

---@return table?
local function load_stratum()
    local ok, stratum = pcall(require, 'stratum')
    return ok and stratum or nil
end

---@param path string
---@return string
local function normalize_path(path)
    return vim.fs.normalize(path)
end

---@return string?
local function current_buffer_path()
    local name = vim.api.nvim_buf_get_name(0)
    if name == '' then
        return nil
    end

    return normalize_path(name)
end

---@param root string?
---@param path string
---@return string?
local function relative_path(root, path)
    if type(root) ~= 'string' or root == '' then
        return nil
    end

    local ok, relative = pcall(vim.fs.relpath, normalize_path(root), normalize_path(path))
    if ok and type(relative) == 'string' then
        return relative == '' and '.' or relative
    end

    local normalized_root = normalize_path(root)
    local normalized_path = normalize_path(path)
    if normalized_path == normalized_root then
        return '.'
    end

    local prefix = normalized_root .. '/'
    if normalized_path:sub(1, #prefix) == prefix then
        return normalized_path:sub(#prefix + 1)
    end

    return nil
end

---@param values any
---@param needle string?
---@return boolean
local function contains_path(values, needle)
    if type(values) ~= 'table' or type(needle) ~= 'string' then
        return false
    end

    for _, value in ipairs(values) do
        if value == needle then
            return true
        end
    end

    return false
end

---@param value any
---@return integer
local function list_length(value)
    return type(value) == 'table' and #value or 0
end

---@param value any
---@return table
local function list_or_empty(value)
    return type(value) == 'table' and vim.deepcopy(value) or {}
end

---@param value any
---@return table?
local function table_or_nil(value)
    return type(value) == 'table' and vim.deepcopy(value) or nil
end

---@param status table?
---@param keys string[]
---@return boolean
local function has_any_status(status, keys)
    if type(status) ~= 'table' then
        return false
    end

    for _, key in ipairs(keys) do
        if status[key] == true then
            return true
        end
    end

    return false
end

---@param entry table?
---@param path string?
---@return boolean
local function entry_matches_path(entry, path)
    if type(entry) ~= 'table' or type(path) ~= 'string' then
        return false
    end

    for _, key in ipairs(path_alias_keys) do
        if entry[key] == path then
            return true
        end
    end

    return false
end

---@param paths table
---@param path string?
---@return table?
local function path_entry(paths, path)
    if type(paths.entries) ~= 'table' then
        return nil
    end

    for _, entry in ipairs(paths.entries) do
        if entry_matches_path(entry, path) then
            return entry
        end
    end

    return nil
end

---@param paths table
---@param path string?
---@return table?
local function conflict_entry(paths, path)
    if type(paths.conflicts) ~= 'table' then
        return nil
    end

    for _, conflict in ipairs(paths.conflicts) do
        if conflict.path == path then
            return conflict
        end
    end

    return nil
end

---@param paths table
---@return table
local function path_counts(paths)
    return {
        staged = list_length(paths.staged),
        unstaged = list_length(paths.unstaged),
        untracked = list_length(paths.untracked),
        ignored = list_length(paths.ignored),
        conflicted = list_length(paths.conflicted),
        conflicts = list_length(paths.conflicts),
        entries = list_length(paths.entries),
    }
end

---@param paths table
---@return table
local function path_sets(paths)
    return {
        staged = list_or_empty(paths.staged),
        unstaged = list_or_empty(paths.unstaged),
        untracked = list_or_empty(paths.untracked),
        ignored = list_or_empty(paths.ignored),
        conflicted = list_or_empty(paths.conflicted),
    }
end

---@param branches any
---@return table
local function branch_counts(branches)
    local counts = {
        local_branches = 0,
        remote_branches = 0,
        head_branches = 0,
        branches = list_length(branches),
    }
    if type(branches) ~= 'table' then
        return counts
    end

    for _, branch in ipairs(branches) do
        if type(branch) == 'table' then
            if branch.kind == 'local' then
                counts.local_branches = counts.local_branches + 1
            elseif branch.kind == 'remote' then
                counts.remote_branches = counts.remote_branches + 1
            end

            if branch.isHead == true or branch.is_head == true then
                counts.head_branches = counts.head_branches + 1
            end
        end
    end

    return counts
end

---@param snapshot table?
---@return table
local function ref_counts(snapshot)
    snapshot = type(snapshot) == 'table' and snapshot or {}
    local counts = branch_counts(snapshot.branches)
    counts.remotes = list_length(snapshot.remotes)
    counts.tags = list_length(snapshot.tags)
    counts.stashes = list_length(snapshot.stashes)
    counts.worktrees = list_length(snapshot.worktrees)
    counts.submodules = list_length(snapshot.submodules)
    return counts
end

---@param branches any
---@return table?
local function current_branch(branches)
    if type(branches) ~= 'table' then
        return nil
    end

    for _, branch in ipairs(branches) do
        if type(branch) == 'table' and (branch.isHead == true or branch.is_head == true) then
            return vim.deepcopy(branch)
        end
    end

    return nil
end

---@param paths table
---@param path string?
---@param entry table?
---@return table
local function path_categories(paths, path, entry)
    local status = type(entry) == 'table' and entry.status or nil
    local categories = {
        staged = contains_path(paths.staged, path) or has_any_status(status, staged_status_keys),
        unstaged = contains_path(paths.unstaged, path) or has_any_status(status, unstaged_status_keys),
        untracked = contains_path(paths.untracked, path) or has_any_status(status, untracked_status_keys),
        ignored = contains_path(paths.ignored, path) or has_any_status(status, ignored_status_keys),
        conflicted = contains_path(paths.conflicted, path) or has_any_status(status, conflicted_status_keys),
    }

    local names = {}
    for _, key in ipairs(path_state_keys) do
        if categories[key] then
            table.insert(names, key)
        end
    end

    return {
        staged = categories.staged,
        unstaged = categories.unstaged,
        untracked = categories.untracked,
        ignored = categories.ignored,
        conflicted = categories.conflicted,
        dirty = #names > 0,
        categories = names,
    }
end

---@param stratum table
---@param snapshot table?
---@return table?
local function snapshot_summary(stratum, snapshot)
    if type(snapshot) ~= 'table' then
        return nil
    end

    if type(stratum.snapshot_summary) == 'function' then
        local ok, summary = pcall(stratum.snapshot_summary, snapshot)
        if ok and type(summary) == 'table' then
            return summary
        end
    end

    return nil
end

---@param repo table?
---@return table?
local function repo_identity(repo)
    if type(repo) ~= 'table' then
        return nil
    end

    return {
        id = repo.id,
        root = repo.root,
    }
end

---@param path string?
---@return table?, table?, table?
local function repository_state(path)
    if path == nil then
        return {
            available = false,
            provider = 'stratum',
            reason = 'current buffer has no file path',
        }
    end

    local stratum = load_stratum()
    if stratum == nil then
        return {
            available = false,
            provider = 'stratum',
            path = path,
            reason = 'stratum.nvim is not available',
        }
    end

    if type(stratum.state) ~= 'function' then
        return {
            available = false,
            provider = 'stratum',
            path = path,
            reason = 'stratum.nvim does not expose repository state',
        }
    end

    local ok, state, state_err = pcall(stratum.state, path)
    if not ok then
        return {
            available = false,
            provider = 'stratum',
            path = path,
            reason = tostring(state),
        }
    end

    if type(state) ~= 'table' then
        return {
            available = false,
            provider = 'stratum',
            path = path,
            reason = state_err or 'repository state is unavailable',
        }
    end

    return nil, stratum, state
end

---@return table
function M.repository_summary()
    local path = current_buffer_path()
    local unavailable, stratum, state = repository_state(path)
    if unavailable ~= nil then
        return unavailable
    end

    return {
        available = state.status == 'connected' and type(state.snapshot) == 'table',
        provider = 'stratum',
        path = path,
        repo = repo_identity(state.repo),
        status = state.status,
        stale = state.stale == true,
        last_error = state.last_error,
        snapshot_version = state.snapshot_version,
        summary = snapshot_summary(stratum, state.snapshot),
    }
end

---@param path? string
---@return table
function M.repository_overview(path)
    path = path ~= nil and normalize_path(path) or current_buffer_path()
    local unavailable, stratum, state = repository_state(path)
    if unavailable ~= nil then
        return unavailable
    end

    local snapshot = type(state.snapshot) == 'table' and state.snapshot or nil
    local paths = snapshot ~= nil and type(snapshot.paths) == 'table' and snapshot.paths or {}
    local repo = repo_identity(state.repo)
    local relative = relative_path(repo and repo.root, path)
    local entry = path_entry(paths, relative)

    local payload = {
        available = state.status == 'connected' and snapshot ~= nil,
        provider = 'stratum',
        path = path,
        relative_path = relative,
        repo = repo,
        status = state.status,
        stale = state.stale == true,
        last_error = state.last_error,
        snapshot_version = state.snapshot_version,
        summary = snapshot_summary(stratum, snapshot),
        counts = {
            paths = path_counts(paths),
            refs = ref_counts(snapshot),
        },
        path_state = path_categories(paths, relative, entry),
        entry = entry,
        conflict = conflict_entry(paths, relative),
    }

    if snapshot ~= nil then
        payload.head = table_or_nil(snapshot.head)
        payload.headCommit = table_or_nil(snapshot.headCommit)
        payload.upstream = table_or_nil(snapshot.upstream)
        payload.operation = table_or_nil(snapshot.operation)
        payload.current_branch = current_branch(snapshot.branches)
    end

    return payload
end

---@param path? string
---@return table
function M.path_state(path)
    path = path ~= nil and normalize_path(path) or current_buffer_path()
    local unavailable, _, state = repository_state(path)
    if unavailable ~= nil then
        return unavailable
    end

    local snapshot = type(state.snapshot) == 'table' and state.snapshot or nil
    local paths = type(snapshot) == 'table' and type(snapshot.paths) == 'table' and snapshot.paths or {}
    local repo = repo_identity(state.repo)
    local relative = relative_path(repo and repo.root, path)
    local entry = path_entry(paths, relative)
    local conflict = conflict_entry(paths, relative)

    return {
        available = state.status == 'connected' and snapshot ~= nil,
        provider = 'stratum',
        path = path,
        relative_path = relative,
        repo = repo,
        status = state.status,
        stale = state.stale == true,
        last_error = state.last_error,
        snapshot_version = state.snapshot_version,
        path_state = path_categories(paths, relative, entry),
        entry = entry,
        conflict = conflict,
    }
end

---@param path? string
---@param opts? { include_entries?: boolean }
---@return table
function M.repository_paths(path, opts)
    opts = opts or {}
    path = path ~= nil and normalize_path(path) or current_buffer_path()
    local unavailable, _, state = repository_state(path)
    if unavailable ~= nil then
        return unavailable
    end

    local snapshot = type(state.snapshot) == 'table' and state.snapshot or nil
    local paths = type(snapshot) == 'table' and type(snapshot.paths) == 'table' and snapshot.paths or {}
    local payload = {
        available = state.status == 'connected' and snapshot ~= nil,
        provider = 'stratum',
        path = path,
        repo = repo_identity(state.repo),
        status = state.status,
        stale = state.stale == true,
        last_error = state.last_error,
        snapshot_version = state.snapshot_version,
        counts = path_counts(paths),
        paths = path_sets(paths),
    }

    if opts.include_entries == true then
        payload.entries = list_or_empty(paths.entries)
        payload.conflicts = list_or_empty(paths.conflicts)
    end

    return payload
end

---@param path? string
---@param opts? { include_tags?: boolean, include_stashes?: boolean, include_worktrees?: boolean, include_submodules?: boolean }
---@return table
function M.repository_refs(path, opts)
    opts = opts or {}
    path = path ~= nil and normalize_path(path) or current_buffer_path()
    local unavailable, _, state = repository_state(path)
    if unavailable ~= nil then
        return unavailable
    end

    local snapshot = type(state.snapshot) == 'table' and state.snapshot or nil
    local payload = {
        available = state.status == 'connected' and snapshot ~= nil,
        provider = 'stratum',
        path = path,
        repo = repo_identity(state.repo),
        status = state.status,
        stale = state.stale == true,
        last_error = state.last_error,
        snapshot_version = state.snapshot_version,
        counts = ref_counts(snapshot),
    }

    if snapshot ~= nil then
        payload.head = table_or_nil(snapshot.head)
        payload.headCommit = table_or_nil(snapshot.headCommit)
        payload.upstream = table_or_nil(snapshot.upstream)
        payload.operation = table_or_nil(snapshot.operation)
        payload.branches = list_or_empty(snapshot.branches)
        payload.current_branch = current_branch(snapshot.branches)
        payload.remotes = list_or_empty(snapshot.remotes)
    end

    if opts.include_tags == true and snapshot ~= nil then
        payload.tags = list_or_empty(snapshot.tags)
    end
    if opts.include_stashes == true and snapshot ~= nil then
        payload.stashes = list_or_empty(snapshot.stashes)
    end
    if opts.include_worktrees == true and snapshot ~= nil then
        payload.worktrees = list_or_empty(snapshot.worktrees)
    end
    if opts.include_submodules == true and snapshot ~= nil then
        payload.submodules = list_or_empty(snapshot.submodules)
    end

    return payload
end

return M
