# FAC Architecture Evidence Index

Evidence date: 2026-09-05, repo `main` @ v2.5.1. Paths relative to repo root; the Python package lives in `frappe_assistant_core/`. Evidence gathered by `system-modeler` skill via direct file reads + an Explore agent pass; corroborated against `docs/internals/INTERNALS.md` and `docs/api/API_REFERENCE.md`.

## Nodes

| Node | Claim | sourceRefs | Confidence |
|---|---|---|---|
| MCP HTTP Endpoint | `handle_mcp()` whitelisted POST/GET/HEAD, StreamableHTTP, builds per-request tool registry | `frappe_assistant_core/api/fac_endpoint.py:330-344, 54-109` | high |
| Auth gate | Bearer → `OAuth Bearer Token` lookup + expiry check; or `token api_key:api_secret` → `User.api_key` compare; then `frappe.set_user(user)`; 401 with `WWW-Authenticate: resource_metadata` | `api/fac_endpoint.py:161-327, 214-224, 257-273` | high |
| User gate | `User.assistant_enabled` custom field checked per request | `api/fac_endpoint.py:43-51, 373-376`; `hooks.py:268` (fixture) | high |
| OAuth suite | Frappe's own `frappe.integrations.oauth2` is the authorization server; FAC overrides `get_token` (Basic-auth fix) and `openid_configuration` (adds PKCE S256, jwks_uri, mcp_endpoint); RFC 7591 dynamic registration; `.well-known/*` via custom `page_renderer` | `hooks.py:165-168, 174`; `api/oauth_token.py:37-71`; `api/oauth_discovery.py:72-152, 190-219`; `api/oauth_registration.py:70-71`; `api/oauth_wellknown_renderer.py:30-89` | high |
| MCP Server Core | Hand-rolled JSON-RPC 2.0 router, **no official `mcp` SDK, no Pydantic, no SSE**; methods: initialize, tools/list, tools/call, resources/list|read|templates, prompts/list|get, ping; protocol version default `2025-06-18` | `mcp/server.py:40-64, 142-243, 289-314, 443-478`; grep `from mcp|import mcp` = 0 matches; `pyproject.toml:29-59` (no mcp dep) | high |
| Tool Registry | Per-request registry; filters by plugin enablement, `FAC Tool Configuration`, `FAC Tool Role Access`; 60 s `frappe.cache` config cache | `core/tool_registry.py:34-42, 47-48, 58, 106` | high |
| Plugin Manager | Filesystem discovery of `frappe_assistant_core.plugins.*` declaring `plugin.py`; persistence via `FAC Plugin Configuration` doctype; singleton | `utils/plugin_manager.py:90-195` | high |
| Plugins & tool counts | Core 17, Data Science 4, Visualization 3, Custom Tools dynamic = 24 built-in | `plugins/core/plugin.py:42-72`; `plugins/data_science/plugin.py:53-60`; `plugins/visualization/plugin.py:53-59`; `plugins/custom_tools/plugin.py:27-123` | high |
| External tools hook | `assistant_tools` hook from other apps imported at request time, registered under `custom_tools`, only when that plugin is enabled; requires BaseTool subclass | `core/tool_registry.py:374-429`; `hooks.py:278-280` | high |
| Skills hook | `assistant_skills` → `FAC Skill` docs installed from other apps; cleaned on app uninstall | `utils/migration_hooks.py:638-690`; `hooks.py:104` | high |
| Code sandbox | `run_python_code` spawns disposable subprocess (`python -m ...code_execution_subprocess`, JSON over stdin) with RLIMIT_CPU/AS, SIGALRM, import allowlist, restricted `__builtins__`; not Frappe `safe_exec` | `plugins/data_science/tools/run_python_code.py:268-273, 759`; `utils/code_execution_subprocess.py:20-21, 90-206` | high |
| Audit trail | Every tool execution → `log_tool_execution()` → `Assistant Audit Log` insert(ignore_permissions), args sanitized, output clamped 50 KB | `utils/audit_trail.py:62-147, 40-59, 150-160`; called from `core/base_tool.py:417, 427` | high |
| DocTypes (9) | Assistant Audit Log, Assistant Core Settings, FAC Plugin Configuration, FAC Skill, FAC Tool Configuration, FAC Tool Role Access, Prompt Category, Prompt Template, Prompt Template Argument | `frappe_assistant_core/assistant_core/doctype/` (9 dirs) | high |
| Cache layer | TTL table (dashboard 300 s, settings 1800 s, tool_registry 3600 s, health 600 s) over `frappe.cache` (Redis); invalidation via `doc_events` (settings on_update, audit after_insert); warm cron | `utils/cache.py:32-109`; `hooks.py:138-141, 149` | high |
| Scheduler | cron `0 0 * * *` cleanup_old_logs; `*/30 * * * *` warm_cache; single `frappe.enqueue` (enable_background_api) on settings toggle | `hooks.py:146-152`; `assistant_core/doctype/assistant_core_settings/assistant_core_settings.py:168-172` | high |
| Claude Desktop bridge | Optional DXT-style stdio→HTTP bridge, client-side, token auth + session headers, ThreadPoolExecutor(5) | `client_packages/claude-desktop/README.md:5-9`; `client_packages/claude-desktop/server/frappe_assistant_stdio_bridge.py:15-45` | high |
| Permission query conditions | Audit Log / Prompt Template / FAC Skill get custom query conditions | `hooks.py:116-120` | high |
| Roles & fixtures | Standard roles Assistant User / Assistant Admin; User `assistant_enabled` custom field fixture | `hooks.py:244-247, 267-272` | high |
| LLM Provider API | The MCP client (not FAC) talks to model APIs; FAC has no LLM API client code | contextual, inferred | low |

## Edges (key relationships)

| Edge | Protocol / nature | sourceRefs | Confidence |
|---|---|---|---|
| MCP Client → handle_mcp | HTTPS POST JSON-RPC, StreamableHTTP, no SSE | `api/fac_endpoint.py:330-344`; `mcp/server.py:443-459` | high |
| handle_mcp → MCPServer.handle | in-process call, registry passed per request (issue #197 concurrency fix) | `mcp/server.py:118-136`; `api/fac_endpoint.py:54-109` | high |
| tools/call → tool fn | `fn(**arguments)` + json.dumps(default=str), `_image_content` → MCP image block | `mcp/server.py:358-441, 390, 401-432` | high |
| Plugins → Frappe ORM | document CRUD / search / reports / workflows under requesting user's permissions | `plugins/core/` tools; `api/fac_endpoint.py:204, 271` (set_user) | high |
| BaseTool → Audit Log | in-process insert per execution | `core/base_tool.py:427` → `utils/audit_trail.py:119-143` | high |
| Registry → Redis | config cache 60 s | `core/tool_registry.py:47-48, 106` | high |
| Sandbox → site DB | analysis data access | not traced this pass | low (inferred) |

## Unknowns / validation tasks

1. **Subprocess data path**: how `code_execution_subprocess` connects to site data (frappe.init? socket? stdin payload?). Validate before claiming analysis tools read the DB from inside the sandbox. (Dashed edge in `fac-dispatch.dot`.)
2. **Docs vs code, protocol version**: `docs/api/API_REFERENCE.md:53-56` and `docs/internals/INTERNALS.md:138-139` say MCP `2025-03-26`; code default is `2025-06-18` (`mcp/server.py:299`, `api/fac_endpoint.py:339`, settings-overridable via `patches/v2_3/update_mcp_protocol_version.py`). Docs are stale.
3. **Docs omit API-key auth path** (`api/fac_endpoint.py:248-273`) and the prompts/resources capabilities now declared in `initialize` (`mcp/server.py:306-312`).
4. `chatgpt_search` / `chatgpt_fetch` tool names in code vs `search` / `fetch` in README table — likely renamed at a layer not yet inspected; cosmetic, verify if relevant.
