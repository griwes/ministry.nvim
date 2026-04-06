---@class mcp.EndpointDescriptor
---@field transport 'socket'
---@field socket_kind 'abstract'
---@field socket_name string
---@field command string
---@field args string[]
---@field env table<string, string>

---@class mcp.ToolSpec
---@field name string
---@field description? string
---@field input_schema? table
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil

---@class mcp.ResourceSpec
---@field uri string
---@field name? string
---@field description? string
---@field mime_type? string
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil

---@class mcp.ResourceTemplateSpec
---@field name string
---@field uri_template string
---@field description? string
---@field mime_type? string
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil

---@class mcp.PromptSpec
---@field name string
---@field description? string
---@field arguments? table[]
---@field handler fun(arguments: table|nil, ctx: table): table|nil, table|nil

---@class mcp.ServerSpec
---@field name string
---@field title? string
---@field description? string
---@field tools? mcp.ToolSpec[]
---@field resources? mcp.ResourceSpec[]
---@field resource_templates? mcp.ResourceTemplateSpec[]
---@field prompts? mcp.PromptSpec[]

---@class mcp.Config
---@field socket_prefix string
---@field bridge_command string

