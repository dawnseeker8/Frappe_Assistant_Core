workspace {
  name "Frappe Assistant Core - Current State Architecture"
  description "Evidence-backed C4 model. Evidence date: 2026-09-05. Produced by system-modeler + c4model skills from source code at commit main (v2.5.1)."

  model {
    llmUser = person "ERPNext User" "Asks business questions in natural language. Data access is scoped to their own Frappe permissions (frappe.set_user per request)."
    facAdmin = person "FAC Admin" "Enables the server, configures plugins/tools/skills, reviews the Assistant Audit Log via the FAC Admin desk page."

    llmClient = softwareSystem "MCP LLM Client" "Claude Desktop, Claude Web, ChatGPT or MCP Inspector. Connects as an OAuth 2.0 client (PKCE) and speaks MCP over StreamableHTTP." {
      tags "External"
    }
    llmProvider = softwareSystem "LLM Provider API" "Anthropic/OpenAI model APIs used by the client itself. FAC never calls them. Contextual, inferred edge." {
      tags "External, Inferred"
    }
    frappe = softwareSystem "Frappe Framework 15-16" "Host platform: whitelisted HTTP routing, DocType ORM, MariaDB, frappe.cache (Redis), OAuth2 server, scheduler, werkzeug responses." {
      tags "Platform"
    }
    erpApps = softwareSystem "ERPNext and other Frappe apps" "Business data and logic in the same site. External apps contribute tools via the assistant_tools hook and skills via assistant_skills." {
      tags "External"
    }
    stdioBridge = softwareSystem "Claude Desktop Bridge (optional)" "DXT-style stdio-to-HTTP bridge shipped in client_packages/claude-desktop; runs on the user desktop, not in the bench." {
      tags "External, Optional"
    }

    fac = softwareSystem "Frappe Assistant Core" "Frappe app exposing 24 built-in tools to MCP clients, inside user permissions, with audit logging." {
      mcpEndpoint = container "MCP HTTP Endpoint" "handle_mcp(): whitelisted POST/GET/HEAD route, StreamableHTTP transport, per-request tool registry, bearer/api-key auth gate." "Python / Frappe"
      oauthSuite = container "OAuth Endpoint Suite" ".well-known discovery renderer, RFC 7591 dynamic client registration, get_token and openid_configuration overrides on Frappe's oauth2 server." "Python / Frappe"
      mcpCore = container "MCP Server Core" "Hand-rolled JSON-RPC 2.0 router: initialize, tools/list, tools/call, resources, prompts, ping. No official MCP SDK, no SSE. Protocol version 2025-06-18 by default." "Python"
      registry = container "Tool Registry and Plugin Manager" "Per-request registry; filters by plugin state, FAC Tool Configuration and role access; discovers plugins under plugins/ and merges external assistant_tools hooks." "Python"
      plugins = container "Tool Plugins" "Core (17 tools), Data Science (4), Visualization (3), Custom Tools (dynamic). 24 built-in tools total." "Python"
      sandbox = container "Code Sandbox Subprocess" "Disposable subprocess for run_python_code: CPU/memory rlimits, SIGALRM, import allowlist, restricted builtins. OCR subprocess optional." "Python subprocess"
      audit = container "Audit Trail Writer" "log_tool_execution() inserts an Assistant Audit Log record for every tool call with sanitized args and clamped output." "Python / Frappe"
      cacheUtils = container "Cache Utilities" "TTL caches over frappe.cache (Redis); invalidated via doc_events; warmed by cron." "Python / Redis"
      jobs = container "Scheduled Jobs" "Cron: daily cleanup_old_logs, 30-minute warm_cache. One frappe.enqueue when server is enabled." "Frappe scheduler"
      adminPage = container "FAC Admin Desk Page" "Admin UI: endpoint URL, plugin/tool configuration, skills, prompt templates, audit log views." "Frappe Page"
      siteDb = container "Site Database" "MariaDB via Frappe ORM. Holds business DocTypes, OAuth Bearer Token and Client, and 9 FAC DocTypes (settings, plugin/tool config, skills, prompt templates, audit log)." "MariaDB"
      redis = container "Redis Cache" "frappe.cache: settings, tool-config, dashboard and health statistics caches." "Redis"
    }

    llmUser -> llmClient "Asks questions, reviews answers"
    facAdmin -> adminPage "Configures and reviews"
    llmClient -> llmProvider "Sends prompts to the model API" {
      tags "Inferred"
    }
    llmClient -> mcpEndpoint "POST JSON-RPC (MCP over StreamableHTTP) with Bearer token or api_key:secret" "HTTPS"
    stdioBridge -> mcpEndpoint "Forwards JSON-RPC over HTTP with token and session headers" "HTTPS"
    llmClient -> oauthSuite "OAuth 2.0 + PKCE: discover, register client, authorize, token" "HTTPS"
    mcpEndpoint -> frappe "Registered as whitelisted method; guest allowed; werkzeug JSON response" "in-process"
    oauthSuite -> frappe "Overrides frappe.integrations.oauth2 get_token and openid_configuration" "in-process"
    mcpEndpoint -> mcpCore "handle() with per-request tool registry"
    mcpCore -> registry "tools/list, tools/call"
    registry -> plugins "Loads and dispatches tool instances"
    erpApps -> registry "Contributes tools via assistant_tools hook" {
      tags "Request-time import"
    }
    plugins -> frappe "Document CRUD, search, reports, workflows under user permissions" "Frappe ORM"
    plugins -> sandbox "run_python_code spawns subprocess with JSON on stdin" "subprocess"
    sandbox -> siteDb "Analysis data access" {
      tags "Inferred"
    }
    plugins -> audit "BaseTool._safe_execute logs every execution" "in-process"
    audit -> siteDb "Inserts Assistant Audit Log (ignore_permissions)"
    registry -> redis "Tool-config cache, 60 s TTL"
    cacheUtils -> redis "get/set with TTL and invalidation"
    jobs -> siteDb "cleanup_old_logs (daily)"
    jobs -> redis "warm_cache (every 30 min)"
    adminPage -> siteDb "Reads/writes settings, skills, prompt templates, audit"
    frappe -> siteDb "DocType persistence"
    frappe -> redis "Cache API"
    erpApps -> siteDb "Owns business DocTypes in the same site database"
  }

  views {
    systemContext fac "FAC-SystemContext" {
      include *
      autolayout lr
    }

    container fac "FAC-Containers" {
      include *
      autolayout tb
    }

    styles {
      element "External" {
        color "#999999"
      }
      element "Inferred" {
        border dashed
      }
      element "Platform" {
        background "#E8F0FE"
      }
    }
  }
}
