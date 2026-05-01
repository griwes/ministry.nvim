---@class ministry.EndpointDescriptor
---@field transport 'socket'|'http'
---@field socket_kind? 'abstract'
---@field socket_name? string
---@field url? string
---@field http_host? string
---@field http_port? integer
---@field command string
---@field args string[]
---@field env table<string, string>
---@field invocation table

---@class ministry.ToolSpec
---@field name string
---@field description? string
---@field input_schema? table
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil
---@field ministry_source? ministry.ServerSource

---@class ministry.ResourceSpec
---@field uri string
---@field name? string
---@field description? string
---@field mime_type? string
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil

---@class ministry.ResourceTemplateSpec
---@field name string
---@field uri_template string
---@field description? string
---@field mime_type? string
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil

---@class ministry.PromptSpec
---@field name string
---@field description? string
---@field arguments? table[]
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil

---@class ministry.ServerSpec
---@field name string
---@field title? string
---@field description? string
---@field tools? ministry.ToolSpec[]
---@field resources? ministry.ResourceSpec[]
---@field resource_templates? ministry.ResourceTemplateSpec[]
---@field prompts? ministry.PromptSpec[]
---@field ministry_source? ministry.ServerSource

---@alias ministry.ServerSourceKind 'native'|'config'
---@alias ministry.ExternalTransport 'stdio'|'http'
---@alias ministry.ApprovalDecision 'allow'|'reject'|'ask'

---@class ministry.ServerSource
---@field kind ministry.ServerSourceKind
---@field name? string
---@field path? string

---@class ministry.ExternalServerSpec
---@field name string
---@field source ministry.ServerSource
---@field transport ministry.ExternalTransport
---@field command? string
---@field args? string[]
---@field env? table<string, string>
---@field cwd? string
---@field url? string
---@field headers? table<string, string>

---@class ministry.ExternalConfig
---@field enabled boolean
---@field config string|string[]|nil
---@field workspace ministry.ExternalWorkspaceConfig
---@field request_timeout_ms integer

---@class ministry.ExternalWorkspaceConfig
---@field enabled boolean
---@field look_for string[]
---@field reload_on_dir_changed boolean

---@class ministry.ApprovalConfig
---@field enabled boolean
---@field default ministry.ApprovalDecision
---@field persistence boolean
---@field path? string
---@field provider? fun(request: ministry.ApprovalRequest): ministry.ApprovalDecision|boolean|nil

---@class ministry.ApprovalRequest
---@field server string
---@field method string
---@field namespaced_name string
---@field arguments table
---@field context table

---@class ministry.UiConfig
---@field width number
---@field height number
---@field border string|string[]

---@class ministry.ServerStatus
---@field name string
---@field source ministry.ServerSource
---@field transport string
---@field command? string
---@field args? string[]
---@field url? string
---@field state string
---@field error? string
---@field policy table

---@class ministry.Config
---@field socket_prefix string
---@field bridge_command string
---@field transport 'socket'|'http'
---@field http_host string
---@field http_port integer
---@field http_token? string
---@field auto_start boolean
---@field external ministry.ExternalConfig
---@field approval ministry.ApprovalConfig
---@field ui ministry.UiConfig
