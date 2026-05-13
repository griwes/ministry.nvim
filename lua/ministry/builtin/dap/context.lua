local M = {}

local REQUEST_TIMEOUT_MS = 2000

local function normalize_path(path)
    if type(path) ~= 'string' or path == '' then
        return path
    end

    return vim.fs.normalize(path)
end

local function normalize_uri_path(uri)
    if type(uri) ~= 'string' or uri == '' then
        return nil
    end

    if vim.startswith(uri, 'file://') then
        return normalize_path(vim.uri_to_fname(uri))
    end

    return nil
end

local function load_dap()
    local ok, dap = pcall(require, 'dap')
    return ok and dap or nil
end

local function current_session()
    local dap = load_dap()
    if dap == nil or type(dap.session) ~= 'function' then
        return nil, dap
    end

    local session = dap.session()
    if type(session) ~= 'table' then
        return nil, dap
    end

    return session, dap
end

local function current_frame(session)
    if type(session) ~= 'table' then
        return nil
    end

    if type(session.current_frame) == 'table' then
        return session.current_frame
    end

    if type(session.current_thread) == 'table' and type(session.current_thread.frame) == 'table' then
        return session.current_thread.frame
    end

    return nil
end

local function current_thread_id(session)
    if type(session) ~= 'table' then
        return nil
    end

    if type(session.current_thread) == 'table' and type(session.current_thread.id) == 'number' then
        return session.current_thread.id
    end

    local frame = current_frame(session)
    if type(frame) == 'table' and type(frame.threadId) == 'number' then
        return frame.threadId
    end

    return nil
end

local function normalize_source(source)
    if type(source) ~= 'table' then
        return nil
    end

    local resolved_path = normalize_path(source.path) or normalize_uri_path(source.path)

    return {
        name = source.name,
        path = resolved_path,
        source_reference = source.sourceReference,
        presentation_hint = source.presentationHint,
        origin = source.origin,
        adapter_data = source.adapterData,
    }
end

local function normalize_frame(frame)
    if type(frame) ~= 'table' then
        return nil
    end

    return {
        id = frame.id,
        name = frame.name,
        line = frame.line,
        column = frame.column,
        end_line = frame.endLine,
        end_column = frame.endColumn,
        instruction_pointer_reference = frame.instructionPointerReference,
        module_id = frame.moduleId,
        presentation_hint = frame.presentationHint,
        source = normalize_source(frame.source),
    }
end

local function normalize_thread(thread)
    if type(thread) ~= 'table' then
        return nil
    end

    return {
        id = thread.id,
        name = thread.name,
        stopped = thread.stopped,
        reason = thread.reason,
        description = thread.description,
        frame = normalize_frame(thread.frame),
    }
end

local function normalize_scope(scope)
    if type(scope) ~= 'table' then
        return nil
    end

    return {
        name = scope.name,
        presentation_hint = scope.presentationHint,
        variables_reference = scope.variablesReference,
        named_variables = scope.namedVariables,
        indexed_variables = scope.indexedVariables,
        expensive = scope.expensive,
        source = normalize_source(scope.source),
        line = scope.line,
        column = scope.column,
        end_line = scope.endLine,
        end_column = scope.endColumn,
    }
end

local function normalize_variable(variable)
    if type(variable) ~= 'table' then
        return nil
    end

    return {
        name = variable.name,
        value = variable.value,
        type = variable.type,
        presentation_hint = variable.presentationHint,
        evaluate_name = variable.evaluateName,
        variables_reference = variable.variablesReference,
        named_variables = variable.namedVariables,
        indexed_variables = variable.indexedVariables,
        memory_reference = variable.memoryReference,
    }
end

local function normalize_breakpoint(path, breakpoint)
    if type(breakpoint) ~= 'table' then
        return nil
    end

    return {
        path = normalize_path(path),
        line = breakpoint.line,
        condition = breakpoint.condition,
        hit_condition = breakpoint.hitCondition,
        log_message = breakpoint.logMessage,
    }
end

local function request(session, command, arguments)
    if type(session) ~= 'table' or type(session.request) ~= 'function' then
        return nil,
            {
                code = -32000,
                message = 'No active dap.nvim session is available',
            }
    end

    local done = false
    local response_body = nil
    local response_err = nil

    session:request(command, arguments or {}, function(err, body)
        response_err = err
        response_body = body
        done = true
    end)

    vim.wait(REQUEST_TIMEOUT_MS, function()
        return done
    end, 10)

    if not done then
        return nil,
            {
                code = -32000,
                message = string.format('dap.nvim request timed out: %s', command),
            }
    end

    if response_err ~= nil then
        return nil, {
            code = -32000,
            message = tostring(response_err),
        }
    end

    return response_body or {}, nil
end

local function require_session()
    local session = current_session()
    if session == nil then
        return nil,
            {
                code = -32000,
                message = 'No active dap.nvim session is available',
            }
    end

    return session, nil
end

function M.summary()
    local session, dap = current_session()
    if session == nil then
        return {
            available = dap ~= nil,
            active = false,
        }
    end

    return {
        available = true,
        active = true,
        session = {
            stopped_thread_id = current_thread_id(session),
            current_frame = normalize_frame(current_frame(session)),
            capabilities = vim.deepcopy(session.capabilities or {}),
        },
    }
end

function M.breakpoints()
    local _, dap = current_session()
    local items = {}

    local lazy_ok, lazy_breakpoints = pcall(require, 'dap.breakpoints')

    if lazy_ok and type(lazy_breakpoints.get) == 'function' then
        for bufnr, group in pairs(lazy_breakpoints.get() or {}) do
            local path = type(bufnr) == 'number' and normalize_path(vim.api.nvim_buf_get_name(bufnr)) or nil
            for _, breakpoint in ipairs(group or {}) do
                local normalized = normalize_breakpoint(path, breakpoint)
                if normalized ~= nil then
                    table.insert(items, normalized)
                end
            end
        end
    elseif dap ~= nil and type(dap.breakpoints) == 'table' then
        for path, group in pairs(dap.breakpoints) do
            for _, breakpoint in ipairs(group or {}) do
                local normalized = normalize_breakpoint(path, breakpoint)
                if normalized ~= nil then
                    table.insert(items, normalized)
                end
            end
        end
    end

    table.sort(items, function(left, right)
        if left.path ~= right.path then
            return tostring(left.path) < tostring(right.path)
        end

        return (left.line or -1) < (right.line or -1)
    end)

    return {
        active = current_session() ~= nil,
        breakpoints = items,
    }
end

function M.threads()
    local session, err = require_session()
    if err ~= nil then
        return nil, err
    end

    local body, request_err = request(session, 'threads', {})
    if request_err ~= nil then
        return nil, request_err
    end

    local items = {}
    for _, thread in ipairs(body.threads or {}) do
        local normalized = normalize_thread(thread)
        if normalized ~= nil then
            table.insert(items, normalized)
        end
    end

    table.sort(items, function(left, right)
        return (left.id or -1) < (right.id or -1)
    end)

    return {
        stopped_thread_id = current_thread_id(session),
        threads = items,
    }, nil
end

function M.stack(thread_id)
    local session, err = require_session()
    if err ~= nil then
        return nil, err
    end

    local resolved_thread_id = thread_id or current_thread_id(session)
    if type(resolved_thread_id) ~= 'number' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: thread_id must be an integer',
            }
    end

    local body, request_err = request(session, 'stackTrace', {
        threadId = resolved_thread_id,
    })
    if request_err ~= nil then
        return nil, request_err
    end

    local items = {}
    for _, frame in ipairs(body.stackFrames or {}) do
        local normalized = normalize_frame(frame)
        if normalized ~= nil then
            table.insert(items, normalized)
        end
    end

    return {
        thread_id = resolved_thread_id,
        total_frames = body.totalFrames,
        stack_frames = items,
    },
        nil
end

function M.scopes(frame_id)
    local session, err = require_session()
    if err ~= nil then
        return nil, err
    end

    if type(frame_id) ~= 'number' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: frame_id must be an integer',
            }
    end

    local body, request_err = request(session, 'scopes', {
        frameId = frame_id,
    })
    if request_err ~= nil then
        return nil, request_err
    end

    local items = {}
    for _, scope in ipairs(body.scopes or {}) do
        local normalized = normalize_scope(scope)
        if normalized ~= nil then
            table.insert(items, normalized)
        end
    end

    return {
        frame_id = frame_id,
        scopes = items,
    }, nil
end

function M.variables(variables_reference)
    local session, err = require_session()
    if err ~= nil then
        return nil, err
    end

    if type(variables_reference) ~= 'number' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: variables_reference must be an integer',
            }
    end

    local body, request_err = request(session, 'variables', {
        variablesReference = variables_reference,
    })
    if request_err ~= nil then
        return nil, request_err
    end

    local items = {}
    for _, variable in ipairs(body.variables or {}) do
        local normalized = normalize_variable(variable)
        if normalized ~= nil then
            table.insert(items, normalized)
        end
    end

    return {
        variables_reference = variables_reference,
        variables = items,
    }, nil
end

local function invoke_action(name)
    local session, dap = current_session()
    if session == nil or dap == nil then
        return nil,
            {
                code = -32000,
                message = 'No active dap.nvim session is available',
            }
    end

    local action = dap[name]
    if type(action) ~= 'function' then
        return nil,
            {
                code = -32000,
                message = string.format('dap.nvim action is unavailable: %s', name),
            }
    end

    action()

    return {
        ok = true,
        action = name,
    }, nil
end

function M.continue()
    return invoke_action('continue')
end

function M.pause()
    return invoke_action('pause')
end

function M.step_over()
    return invoke_action('step_over')
end

function M.step_into()
    return invoke_action('step_into')
end

function M.step_out()
    return invoke_action('step_out')
end

function M.terminate()
    return invoke_action('terminate')
end

function M.disconnect()
    return invoke_action('disconnect')
end

return M
