+# Ministry Threat Model
+
+## Security boundary
+
+Ministry exposes Neovim state and tools over MCP. Any client that can reach an
+active endpoint may be able to read editor data and request state-changing
+operations. Ministry supplies transport checks, approval policy, and resource
+limits, but it does not sandbox Neovim, external MCP servers, or commands
+started by terminal tools.
+
+Trusted inputs are the user's configuration, installed provider modules, and
+explicitly activated external-server definitions. MCP clients, request
+arguments, remote server responses, and terminal output are untrusted.
+
+## Inbound transports
+
+- The default filesystem socket is created beneath a runtime directory that
+  Ministry creates or verifies as owned by the current user and mode 0700.
+  Possession of same-user access to the socket is effectively endpoint access;
+  there is no additional socket authentication.
+- Loopback HTTP may run without a bearer token. This assumes local processes
+  are within the user's trust boundary. Configure a token when that assumption
+  is too broad.
+- Non-loopback HTTP startup is rejected without `http_token`. Application
+  requests use bearer-token comparison, but HTTP is plaintext: use a trusted
+  TLS tunnel or reverse proxy before traffic crosses an untrusted network.
+- CORS controls which browser origins receive readable responses. It is not an
+  authentication mechanism. Valid preflight requests can be unauthenticated;
+  subsequent application requests still require the configured token.
+
+Endpoint descriptors may contain bearer headers. Do not publish them in logs,
+dotfiles, screenshots, or issue reports.
+
+## Tools and approvals
+
+Editor tools can expose open buffers, diagnostics, workspace metadata, and
+other session state. Terminal tools execute host commands and are disabled by
+default. Enabling them expands a reachable MCP client's authority to command
+execution under Neovim's user.
+
+Approval policy defaults to an interactive ask fallback. Persisted allow rules
+are security-sensitive configuration. One-shot approvals are bound to the
+originating transport or logical session when that identity exists, and
+session closure cancels reservations. Approval-provider modules are trusted
+Neovim code and can weaken or replace the normal decision path.
+
+## External MCP servers
+
+External-server discovery is opt-in. Discovery makes entries visible but does
+not start stdio commands until activation. Activating a stdio entry executes
+its configured command; HTTP entries can transmit configured headers and
+editor-derived request data. Review discovered entries, command paths,
+environments, working directories, URLs, and headers before activation.
+
+External servers can return misleading tool descriptions or hostile payloads.
+Namespace boundaries prevent accidental name collisions, not malicious server
+behavior.
+
+## Resource exhaustion and data retention
+
+Socket lines, HTTP headers and bodies, request lifetimes, active operations,
+terminal output, and wait periods have configured bounds. These limits reduce
+accidental or basic denial of service but do not make Neovim robust against a
+determined local peer. Approval decisions and resource results may reveal
+project details in state files or client logs.
+
+## Operational guidance
+
+- Prefer the default filesystem socket for same-user local clients.
+- Use bearer authentication plus TLS tunneling for any non-loopback HTTP use.
+- Keep terminal tools disabled unless command execution is required.
+- Review and minimize persisted approvals and external-server definitions.
+- Run Neovim in an external sandbox when serving mutually untrusted clients.
+

