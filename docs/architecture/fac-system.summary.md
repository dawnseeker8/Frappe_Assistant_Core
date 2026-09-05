# Frappe Assistant Core — Current-State Architecture Summary

Evidence date: 2026-09-05 · repo `main` @ v2.5.1 · produced by `system-modeler` (evidence model), `c4model` (Structurizr DSL), `graphviz` (dispatch chain DOT).

## What FAC is

Frappe Assistant Core (FAC) is a **Frappe app** (not a standalone service) that turns an ERPNext site into an MCP (Model Context Protocol) server. LLM clients — Claude Desktop/Web, ChatGPT, MCP Inspector — connect over HTTP, authenticate as a real Frappe user via OAuth 2.0 + PKCE (or an API key pair), and can then call **24 built-in tools** for document CRUD, search, reports, workflow approvals, Python analytics, file extraction and dashboards. Every call runs inside that user's Frappe permissions and is written to the `Assistant Audit Log`.

## How a request flows (the one-paragraph version)

Client POSTs JSON-RPC to `/api/method/frappe_assistant_core.api.fac_endpoint.handle_mcp` → the endpoint validates a Bearer token (`OAuth Bearer Token` doctype) or `token api_key:api_secret` and calls `frappe.set_user()` so all downstream ORM work runs with that user's permissions → a **per-request tool registry** is built (ToolRegistry + PluginManager, honoring plugin state / tool config / role access) → the hand-rolled `MCPServer.handle()` routes `initialize`, `tools/list`, `tools/call`, `resources/*`, `prompts/*`, `ping` → `tools/call` dispatches `BaseTool.execute()` on the resolved plugin tool → results are JSON-serialized (images extracted into MCP image blocks) → every execution is audit-logged. Transport is plain request/response JSON — **no SSE**; the "Streamable" part is the POST/GET endpoint contract.

## Core libraries (the question this doc exists to answer)

1. **Frappe framework (>=15, <17)** — the foundational library everything else hangs off. It provides: HTTP routing (`frappe.whitelist`, `hooks.py`), the DocType ORM and MariaDB access, the OAuth 2.0 authorization server (`frappe.integrations.oauth2`), `frappe.cache` (Redis), the scheduler and background-job queue, and werkzeug response plumbing. FAC never replaces these; it hooks into them.
2. **FAC's own hand-rolled MCP server (`frappe_assistant_core/mcp/`)** — deliberately **no official `mcp` Python SDK and no Pydantic**. `MCPServer` (mcp/server.py:40-64) implements JSON-RPC 2.0 + StreamableHTTP directly. This is the repo's most distinctive architectural choice: one small class plus `tool_adapter.py` instead of an SDK dependency.
3. **Data-science stack** (only loaded for the Data Science plugin): pandas, numpy, scipy, scikit-learn, matplotlib, seaborn, plotly, bokeh, altair, sympy, networkx — executed inside a **disposable subprocess sandbox** (`utils/code_execution_subprocess.py`: rlimits, SIGALRM, import allowlist, restricted builtins), not Frappe's `safe_exec`.
4. **Supporting**: `requests`/`httpx`, `jsonschema`; file processing `pypdf`, `pymupdf`, `python-docx`, `Pillow`, `beautifulsoup4`, `chardet`, `python-magic`; optional extras `paddleocr` (OCR) and `pdfplumber` (PDF tables).

## Extensibility model

- External Frappe apps add tools via the **`assistant_tools` hook** (imported at request time into the Custom Tools plugin, core/tool_registry.py:374-429) and skills via **`assistant_skills`** (→ `FAC Skill` doctypes).
- Internal extension is via plugins under `frappe_assistant_core/plugins/` (BasePlugin/BaseTool contract).
- Admin surface: FAC Admin desk page + `api/admin/*` whitelisted APIs.

## Artifacts

| File | Answers |
|---|---|
| `fac-system.structurizr.dsl` | C4 System Context + Container views (source of truth; open with Qoder's Structurizr DSL viewer, or paste into Structurizr Playground) |
| `fac-dispatch.dot` | Component-level request dispatch chain, clustered by layer (open with Qoder's DOT viewer, or `dot -Tsvg fac-dispatch.dot -o fac-dispatch.svg`) |
| `fac-system.evidence.md` | Node/edge evidence index with file:line refs, confidence, unknowns |
| `fac-system.summary.md` | This document |

## Known gaps & stale docs

See `fac-system.evidence.md` "Unknowns": sandbox data-access path untraced; docs still say MCP protocol `2025-03-26` while code defaults to `2025-06-18`; docs omit the API-key auth path and prompts/resources capabilities.

## Maintenance note

Regenerate/review these artifacts when: `mcp/server.py` methods change, a plugin is added, the auth chain changes, or Frappe version support (15–16) changes. Keep the DSL/DOT as source of truth; rendered SVGs are derived.
