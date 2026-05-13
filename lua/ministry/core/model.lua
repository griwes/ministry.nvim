---@class ministry.EndpointDescriptor
---@field transport 'socket'|'http'
---@field socket_kind? 'filesystem'
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

---@class ministry.NamespaceDescriptions
---@field tools? table<string, string>
---@field resources? table<string, string>
---@field resource_templates? table<string, string>
---@field prompts? table<string, string>

---@class ministry.ServerSpec
---@field name string
---@field title? string
---@field description? string
---@field tools? ministry.ToolSpec[]
---@field resources? ministry.ResourceSpec[]
---@field resource_templates? ministry.ResourceTemplateSpec[]
---@field prompts? ministry.PromptSpec[]
---@field namespaces? ministry.NamespaceDescriptions
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
---@field providers string[]
---@field reservation_ttl_ms integer

---@class ministry.LimitsConfig
---@field http_body_bytes integer
---@field http_header_bytes integer
---@field request_timeout_ms integer
---@field socket_line_bytes integer

---@class ministry.TerminalConfig
---@field max_output_bytes integer
---@field max_wait_timeout_ms integer
---@field wait_timeout_ms integer

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
---@field tools? { name: string, description?: string }[]
---@field resources? { uri: string, name?: string, description?: string }[]
---@field resource_templates? { uri_template: string, name?: string, description?: string }[]
---@field prompts? { name: string, description?: string }[]
---@field namespaces? ministry.NamespaceDescriptions

---@class ministry.Config
---@field socket_prefix string
---@field bridge_command string
---@field transport 'socket'|'http'
---@field http_host string
---@field http_port integer
---@field http_token? string
---@field auto_start boolean
---@field limits ministry.LimitsConfig
---@field terminal ministry.TerminalConfig
---@field external ministry.ExternalConfig
---@field approval ministry.ApprovalConfig
---@field ui ministry.UiConfig
