# Document OCR / Storage Research Findings

_Date: 2026-08-23. Verification date: 2026-08-23._

## 1. Candidate Longlist

### 1.1 Paperless-ngx — v3.0.5

Paperless-ngx is the leading open-source document management system for personal and small-team use, currently at v3.0.5 (released 01 Aug 2026, 44.5k GitHub stars, GPL-3.0 license). The OCR pipeline is built on OCRmyPDF wrapping Tesseract: scanned images are OCRed into searchable PDF/A archives with an invisible text layer, while born-digital PDFs with embedded text are detected and skipped (configurable via `PAPERLESS_OCR_MODE`: `auto`, `redo`, `force`, `off`). Full-text search runs on Tantivy (replaced Whoosh in v3.0). The tagging model is rich: free-form tags with color coding, correspondents, document types, storage paths, and custom fields — all assignable via six matching algorithms (Any, All, Exact, Regular Expression, Fuzzy match, and Auto/ML neural classifier that learns from existing assignments). v3.0 adds built-in AI features: LLM-assisted title/tag/correspondent suggestions, a vector-indexed RAG system for similar-document retrieval, and a document chat grounded in the corpus. Ingestion paths include a consume directory (with subdirectory-as-tags), IMAP/POP3 email fetching with mail rules, REST API, and third-party mobile apps (SwiftPaperless on iOS, Paperless Mobile on Android — both documented in the project wiki). Docker deploy is a single `ghcr.io/paperless-ngx/paperless-ngx` image plus PostgreSQL and Redis/Valkey sidecars. Resource guidance from the docs: minimum 4 GB RAM, recommended 16 GB RAM / 8 cores for a basic deployment (the Tantivy search index, classification model, and optional LLM embedding backend add memory pressure). Auth supports remote-user header authentication and OIDC/social login via django-allauth (configurable with `PAPERLESS_APPS` + `PAPERLESS_SOCIALACCOUNT_PROVIDERS`), making it compatible with Authelia as the identity provider. Backups use the built-in `document_exporter` (full export of documents, thumbnails, metadata, and DB contents, incremental-update capable) or Docker volume backups. The project is actively maintained by a team with frequent releases.

**Sources:**
- GitHub repo (v3.0.5 release, 44.5k stars, GPL-3.0): <https://github.com/paperless-ngx/paperless-ngx>
- Latest release notes (v3.0.5, 01 Aug 2026): <https://github.com/paperless-ngx/paperless-ngx/releases/tag/v3.0.5>
- OCR configuration (`PAPERLESS_OCR_MODE`, `PAPERLESS_OCR_LANGUAGE`, etc.): <https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/docs/configuration.md>
- Advanced usage (matching algorithms, Auto classifier, AI features, SSO/OIDC): <https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/docs/advanced_usage.md>
- Administration (backup/export/import, management commands): <https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/docs/administration.md>
- Docker Compose setup: <https://github.com/paperless-ngx/paperless-ngx/tree/main/docker/compose>
- OIDC/social auth via django-allauth: <https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/docs/advanced_usage.md> (section "SSO and third party authentication")
- Related projects wiki (mobile apps): <https://github.com/paperless-ngx/paperless-ngx/wiki/Related-Projects>

### 1.2 Mayan EDMS — v4.12.1

Mayan EDMS is an enterprise-grade document management system in continuous development since 2011, currently at v4.12.1 (docs last updated 22 Aug 2026, Apache 2.0 license, hosted on GitLab with a GitHub mirror at 833 stars). OCR is provided via a pluggable engine system with Tesseract included by default; the OCR task can be distributed across multiple worker nodes, and the document's current language is passed to the Tesseract backend to improve recognition. Tagging uses color-coded labels (auto-calculated from the label text), hierarchical multi-level "cabinets" (nested folders where a single document can be filed in multiple cabinets simultaneously), and automatic tree indexes computed from templates over document metadata. The system includes a workflow engine, document versioning, non-destructive redactions, and fine-grained role-based access control. Auth supports OpenID Connect SSO (accounts auto-provisioned from the provider with endpoint auto-discovery), 2FA, and configurable authentication backends extensible to LDAP. Docker Compose deploy is the recommended starting point, using the official `mayanedms/mayanedms` image. System requirements: minimum 4 GB RAM / dual-core 1 GHz / PostgreSQL 13.11; recommended 16 GB RAM / 8 cores / 2 GHz+ / SSD for a basic deployment. The 90+ application modules and enterprise feature set make it heavier than Paperless-ngx — the docs explicitly note there is "no single resource profile or architecture that fits every production installation." It has a complete REST API and filesystem mirroring (indexes and cabinets exposed as a read-only filesystem). The project offers professional support and a knowledge base, but the open-source edition is fully functional.

**Sources:**
- Official docs (v4.12.1): <https://docs.mayan-edms.com/>
- Features page (OCR, tagging/cabinets, OIDC SSO, workflows): <https://docs.mayan-edms.com/chapters/features.html>
- System requirements (4 GB min, 16 GB recommended): <https://docs.mayan-edms.com/chapters/requirements.html>
- Docker Compose install: <https://docs.mayan-edms.com/chapters/docker/install_docker_compose.html>
- GitHub mirror (833 stars, Apache 2.0): <https://github.com/mayan-edms/Mayan-EDMS>
- GitLab primary repo: <https://gitlab.com/mayan-edms/mayan-edms>

### 1.3 Teedy (formerly Sismics Docs) — v1.11

Teedy is a lightweight, open-source document management system (formerly "Sismics Docs"), currently at v1.11 (released 12 Mar 2024, 2.6k GitHub stars, GPL-2.0 license). It includes Tesseract-based OCR with multi-language support (configurable via `DOCS_DEFAULT_LANGUAGE` env var with 24+ language codes). Tagging supports nested/hierarchical tag structures displayed as a folder tree. The feature set includes Dublin Core metadata, custom user-defined metadata, workflow system, 256-bit AES encryption of stored files, file versioning, email import (EML), automatic inbox scanning, 2FA, LDAP authentication, RESTful API, webhooks, and a fully featured Android client. Docker image is `sismics/docs:v1.11` (or `sismics/docs:latest` for the master branch), listening on port 8080, with an embedded H2 database for testing or PostgreSQL for production. The project is maintained by a single developer (jendib/Benjamin Gamard) with sponsorship; the last release was over two years ago (March 2024), the issue tracker has 109 open issues, and there have been only 4 pull requests. The maintenance cadence is slow compared to Paperless-ngx. No OIDC support exists — only LDAP and local accounts. No official resource guidance is published, but the Java/Tomcat stack with Tesseract and PostgreSQL suggests a moderate footprint (likely 2-4 GB RAM).

**Sources:**
- GitHub repo (v1.11, 2.6k stars, GPL-2.0): <https://github.com/sismics/docs>
- Releases (v1.11, 12 Mar 2024): <https://github.com/sismics/docs/releases/tag/v1.11>
- README (features, Docker install, env vars): <https://github.com/sismics/docs>
- Demo: <https://demo.teedy.io>
- Homepage: <https://teedy.io>

### 1.4 Stirling-PDF — latest (PDF toolbox, not a DMS)

Stirling-PDF is the #1 PDF application on GitHub (90.2k stars, open-core license), providing 50+ PDF tools including merge, split, sign, redact, convert, compress, and OCR. It is a **PDF toolbox**, not a document management system: it has no document archive, no tagging or metadata system, no full-text search across a document collection, no consumption pipeline, and no workflow engine. The OCR feature runs Tesseract on uploaded PDFs to add a text layer, but the result is returned to the user — the file is not stored or indexed. It is available as a Docker image (`docker.stirlingpdf.com/stirlingtools/stirling-pdf`) with SSO/auditing in the paid enterprise tier. It belongs in the stack as a **complement** to a DMS (e.g., run a PDF through Stirling-PDF for manual repair/merge/sign before dropping it into Paperless-ngx's consume folder), not as a replacement.

**Sources:**
- GitHub repo (90.2k stars): <https://github.com/Stirling-Tools/Stirling-PDF>
- README (capabilities, quick start): <https://github.com/Stirling-Tools/Stirling-PDF>
- Documentation: <https://docs.stirlingpdf.com>

### 1.5 paperless-gpt — latest (LLM sidecar for Paperless-ngx)

paperless-gpt (by icereed, 2.6k GitHub stars, MIT license) is a Go-based sidecar application that pairs with Paperless-ngx to provide LLM-enhanced OCR and automatic document metadata generation. It does **not** replace Paperless-ngx — it connects to a running Paperless-ngx instance via its REST API using an API token. Key capabilities: (1) LLM-based OCR using vision-capable models (OpenAI gpt-4o, Ollama MiniCPM-V, Claude, Mistral) for better-than-Tesseract text extraction on difficult scans; (2) automatic title, tag, correspondent, and custom field generation via LLM prompts; (3) automatic OCR with tag-based triggers (`paperless-gpt-auto` tag); (4) a unified web UI for manual review and auto-processing; (5) searchable/selectable PDF generation with transparent text layers (via Google Document AI hOCR). Supported LLM backends: OpenAI, Ollama (including reasoning models like `qwen3:8b`), Mistral, Anthropic/Claude, and Azure OpenAI. OCR providers: LLM-based (default), Google Document AI, Azure Document Intelligence, and Docling Server. Docker deploy is a single container alongside Paperless-ngx. **Important security note:** paperless-gpt has no built-in authentication — its web UI and API are open to anyone who can reach the port, so it must sit behind a reverse proxy with auth (Authelia) or be restricted to a trusted network. Given the existing stack runs OpenWebUI/Ollama on rocketman, paperless-gpt could use the local Ollama instance for both LLM suggestions and vision OCR, keeping document content on-prem.

**Sources:**
- GitHub repo (2.6k stars, MIT): <https://github.com/icereed/paperless-gpt>
- README (features, OCR providers, Docker Compose example, security warning): <https://github.com/icereed/paperless-gpt>

### 1.6 paperless-ai — NOT VERIFIED

The repository `izzysoft/paperless-ai` returned a 404. There may be other projects with similar names (e.g., the built-in AI features in Paperless-ngx v3.0+ cover LLM suggestions and RAG natively). **Skipping this candidate** — the functionality is subsumed by paperless-gpt (external sidecar) and Paperless-ngx v3.0's native AI features.

### 1.7 Open WebUI Knowledge Base — RAG consumer, not a DMS

Open WebUI's Knowledge feature (verified from docs.openwebui.com) allows uploading documents (PDFs, spreadsheets, text, code) into knowledge bases that the AI can search via RAG. It supports 13 vector database backends (ChromaDB, PGVector, Qdrant, Milvus, etc.), 8 extraction engines (Tika, Docling, Azure, Mistral OCR, Datalab Marker, MinerU, PaddleOCR, custom loaders), hybrid search (BM25 + vector + cross-encoder reranking), agentic retrieval with native function calling, full-context injection mode, nested directories, incremental directory sync, and REST API management. **However**, Knowledge is a **chat-layer consumer**: it ingests documents for AI retrieval during conversations, but it has no scanning workflow, no OCR pipeline for physical documents, no tagging/metadata system for organizing a document archive, no consumption directory, no email ingestion, and no document management UI. It is the right place to **query** documents already managed by a DMS (Paperless-ngx can export documents, or its API can feed content into a Knowledge base), but it is not a document management system itself. The distinction matters: Knowledge answers "what does my corpus say about X?" during a chat; a DMS answers "where is my insurance policy from 2023?" and manages the lifecycle of the physical document.

**Sources:**
- Knowledge feature docs: <https://docs.openwebui.com/features/workspace/knowledge>
- Extraction engines and vector DBs: <https://docs.openwebui.com/features/workspace/knowledge> (Key Features section)
- API access and sync endpoints: <https://docs.openwebui.com/features/workspace/knowledge> (API access section)

### 1.8 Other candidates considered and excluded

- **Docmost** — real-time collaborative wiki/docs (like Notion), no scan/OCR workflow. <https://github.com/docmost/docmost>
- **Outline** — team wiki/knowledge base, no document scanning or OCR pipeline. <https://github.com/outline/outline>
- **Nextcloud Files + OCR** — file sync platform; OCR requires third-party apps (OCRmyPDF integration is community-maintained, not first-class), tagging exists but the scan-to-archive workflow is not native. <https://nextcloud.com>
- **Seafile** — file sync/sharing, no built-in OCR or document management workflow. <https://github.com/haiwen/seafile>

---

## 2. Comparison Matrix

| Candidate | OCR | Tagging | Auth / OIDC | Footprint | Ingestion | Maintenance |
|-----------|-----|---------|-------------|-----------|-----------|-------------|
| **Paperless-ngx v3.0.5** | Tesseract via OCRmyPDF; PDF/A archive with selectable text layer; `auto`/`redo`/`force`/`off` modes | Free-form tags + correspondents + doc types + storage paths + custom fields; 6 matching algorithms incl. Auto/ML | Remote-user header + OIDC/social via django-allauth (Authelia-compatible) | PostgreSQL + Redis + webserver; min 4 GB, rec 16 GB RAM | Consume dir, IMAP/POP3 email, REST API, mobile apps (SwiftPaperless, Paperless Mobile) | Active team, v3.0.5 Aug 2026, 44.5k stars |
| **Mayan EDMS v4.12.1** | Tesseract (pluggable, distributable across nodes); extracts text from PDFs | Color-coded tags + hierarchical cabinets + auto tree indexes + metadata fields | OIDC SSO (auto-discovery), 2FA, configurable backends | PostgreSQL + Redis + app; min 4 GB, rec 16 GB / 8 cores; 90+ modules | Browser upload, watched folders, IMAP/POP3, SANE scanners, cloud storage, email | Active since 2011, v4.12.1 Aug 2026, professional support |
| **Teedy v1.11** | Tesseract (24+ languages, `DOCS_DEFAULT_LANGUAGE`) | Nested/hierarchical tags + Dublin Core metadata + custom metadata | LDAP only, 2FA, local accounts — **no OIDC** | Java + PostgreSQL; moderate (est. 2-4 GB RAM), no official guidance | Browser upload, EML import, inbox scanning, bulk importer | Slow — last release Mar 2024, 109 open issues, solo maintainer |
| **Stirling-PDF** | Tesseract (adds text layer to uploaded PDFs) | **N/A** — not a DMS, no storage or organization | SSO in paid tier only | Single Java container; moderate | Upload → process → download (no storage) | Very active, 90.2k stars |
| **paperless-gpt** | LLM vision OCR (OpenAI/Ollama/Claude) + Google DocAI/Azure/Docling | Auto-generates tags/titles/correspondents **for Paperless-ngx** | **None** — must be proxied behind Authelia | Single Go container (~20 MB RAM reserved) | Watches Paperless-ngx tags; no independent ingestion | Active, 2.6k stars |
| **Open WebUI Knowledge** | Via extraction engines (Tika, Docling, Mistral OCR, PaddleOCR, etc.) | **N/A** — organized into KBs with directories, not tags | Inherits OpenWebUI auth (Authelia OIDC) | Part of existing OpenWebUI container | Upload, API, incremental directory sync | Active, already deployed |

---

## 3. Recommendation

### Recommended: Paperless-ngx v3.0.5 (+ paperless-gpt optional)

**Rationale:**

Paperless-ngx is the clear winner for this use case. It directly addresses both requirements — scan/import with OCR into searchable archives, and rich tagging with auto-assignment — and fits the composeyourself deployment pattern perfectly (single Docker image + PostgreSQL + Redis, config via env vars, behind Authelia). The v3.0 release adds native AI features (LLM suggestions, RAG, document chat) that align with the existing OpenWebUI/Ollama stack, potentially reducing the need for paperless-gpt if local Ollama models are sufficient.

**Why not Mayan EDMS:** Mayan is enterprise-grade and capable, but its 90+ module footprint and complexity are overkill for a single-user document archive. The maintenance burden (more containers, more config) and steeper learning curve don't justify the additional features (workflow engine, permission system, cryptographic signatures) that a personal stack won't use. The resource recommendation (16 GB / 8 cores) is the same as Paperless-ngx's _recommended_ spec, but Mayan's _minimum_ is also 4 GB — suggesting a heavier baseline.

**Why not Teedy:** Teedy is lightweight and functional, but the maintenance status is a concern: last release was March 2024 (over 2 years ago), 109 open issues, solo maintainer. Critically, it lacks OIDC support — only LDAP and local accounts — which means it cannot integrate with the existing Authelia SSO without a custom auth backend.

### Host placement: rocketman

Paperless-ngx belongs on **rocketman** (the Lenovo desktop with 16 GB RAM), not the CPX21 VPS. Reasons:
- OCR (Tesseract/OCRmyPDF) is CPU-intensive, especially for batch imports of scanned documents.
- The recommended spec is 16 GB RAM / 8 cores — rocketman matches this; the CPX21 (3 vCPU / 4-8 GB) would struggle during bulk OCR.
- Document storage grows over time; rocketman has larger local disk.
- The CPX21 already runs Caddy, Authelia, OpenWebUI, and SearXNG — adding a PostgreSQL-backed DMS would crowd it.
- Access over Tailscale from mobile/laptop is sufficient for a personal DMS; it doesn't need to be publicly reachable.

### Integration points with the existing stack

1. **Authelia OIDC SSO:** Paperless-ngx supports OIDC via django-allauth. Configure `PAPERLESS_APPS="allauth.socialaccount.providers.openid_connect"` and `PAPERLESS_SOCIALACCOUNT_PROVIDERS` with Authelia's OIDC endpoint. Set `PAPERLESS_REDIRECT_LOGIN_TO_SSO=true` to skip the local login form.

2. **Backup via Borg (like Immich):** Paperless-ngx's `document_exporter` produces an incremental-update-capable export (documents, thumbnails, metadata, DB contents) to a target directory. Point the exporter at a volume, then have the existing Borg backup job include that export directory. Alternatively, back up the Docker volumes (`paperless_media`, `paperless_data`, `paperless_pgdata`) directly.

3. **OpenWebUI RAG integration:** Two paths exist:
   - **Native (Paperless-ngx v3.0):** Enable the built-in LLM index with an Ollama embedding backend (`PAPERLESS_AI_LLM_EMBEDDING_BACKEND=ollama`). The document chat and similar-document retrieval work entirely within Paperless-ngx.
   - **Knowledge Base sync:** Export documents from Paperless-ngx (via `document_exporter` or REST API) and sync them into an OpenWebUI Knowledge base for RAG during chat. The Knowledge API supports incremental sync (`POST /api/v1/knowledge/{id}/sync/diff` + `sync/cleanup`), so a cron job on rocketman could keep the KB current.

4. **paperless-gpt (optional):** If the built-in AI suggestions are insufficient, add paperless-gpt as a sidecar container on rocketman, pointing it at the local Ollama instance (`OLLAMA_HOST=http://host.docker.internal:11434` or the Tailscale IP of the Ollama container). Put it behind Authelia (no built-in auth). Use Ollama with a reasoning model like `qwen3:8b` for privacy-preserving, zero-marginal-cost auto-tagging.

5. **Stirling-PDF (optional complement):** If manual PDF repair/merge/sign is needed before archiving, Stirling-PDF can run as a separate container on rocketman. Users process a PDF there, then drop the result into Paperless-ngx's consume directory.

### composeyourself service shape (sketch)

```yaml
# docker-compose.rocketman.yml (overlay)
services:
  paperless-webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    environment:
      - PAPERLESS_SECRET_KEY=${PAPERLESS_SECRET_KEY}
      - PAPERLESS_DBENGINE=postgresql
      - PAPERLESS_DBHOST=paperless-postgres
      - PAPERLESS_DBUSER=${PAPERLESS_DB_USER}
      - PAPERLESS_DBPASS=${PAPERLESS_DB_PASS}
      - PAPERLESS_REDIS=redis://paperless-redis:6379
      - PAPERLESS_URL=https://paperless.${DOMAIN}
      - PAPERLESS_OCR_LANGUAGE=eng
      - PAPERLESS_OCR_MODE=auto
      # Authelia OIDC (example with Keycloak-style provider)
      - PAPERLESS_APPS=allauth.socialaccount.providers.openid_connect
      - PAPERLESS_SOCIALACCOUNT_PROVIDERS={"openid_connect":{"APPS":[{"provider_id":"authelia","name":"Authelia","client_id":"paperless","secret":"${PAPERLESS_OIDC_SECRET}","settings":{"server_url":"https://authelia.${DOMAIN}/.well-known/openid-configuration"}}]}}
      - PAPERLESS_REDIRECT_LOGIN_TO_SSO=true
    volumes:
      - paperless_media:/usr/src/paperless/media
      - paperless_data:/usr/src/paperless/data
      - paperless_consume:/usr/src/paperless/consume
    depends_on: [paperless-postgres, paperless-redis]

  paperless-postgres:
    image: postgres:16
    volumes: [paperless_pgdata:/var/lib/postgresql/data]

  paperless-redis:
    image: valkey/valkey:alpine
    volumes: [paperless_redis_data:/data]
```

---

## Summary

| Candidate | Verdict |
|-----------|---------|
| **Paperless-ngx v3.0.5** | **Recommended** — best fit for scan→OCR→tag→search workflow; OIDC via django-allauth; active development; Docker-native |
| Paperless-ngx + paperless-gpt | **Recommended optional** — adds LLM-enhanced OCR and auto-tagging via local Ollama; requires Authelia proxy (no built-in auth) |
| Mayan EDMS v4.12.1 | Rejected — enterprise overkill for single-user; heavier footprint; same resource rec but more complexity |
| Teedy v1.11 | Rejected — stale maintenance (Mar 2024); no OIDC; solo maintainer |
| Stirling-PDF | Not a DMS — useful complement for PDF manipulation before archiving |
| Open WebUI Knowledge | Not a DMS — RAG consumer for chat; no scan/OCR/tagging workflow |
