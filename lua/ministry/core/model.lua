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

---@class ministry.Config
---@field socket_prefix string
---@field bridge_command string
---@field transport 'socket'|'http'
---@field http_host string
---@field http_port integer
---@field http_token? string
---@field auto_start boolean
