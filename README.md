# VS Code Server for Aridhia DRE

A full-featured, containerised VS Code (code-server) IDE pre-configured for clinical and
biomedical research workflows in Aridhia's Digital Research Environment. Ships with R 4.5,
Python 3, a curated set of data science packages, and AI coding assistance via Aira.

---

## What's included

### Language runtimes

| Runtime | Version | Notes |
|---------|---------|-------|
| R | 4.5 (CRAN) | Installed from the official CRAN Debian apt repo, not the stale distro version |
| Python | 3.x (system) | With pip, venv, and full dev headers |
| radian | latest | Modern R terminal; required for vscode-R extension attachment and httpgd plot rendering |
| uv | latest | Fast Python package and environment manager |

### R packages

Installed via [Posit Package Manager](https://packagemanager.posit.co/) (RSPM) binary
packages where available — avoids C++ compilation failures common on Debian base images.

| Package | Purpose |
|---------|---------|
| languageserver | R language server — powers autocomplete, diagnostics, go-to-definition |
| httpgd | Inline plot rendering in the VS Code R plot viewer (installed from GitHub) |
| vscDebugger | R debugging support for the rdebugger extension (installed from GitHub) |
| ellmer | Aira/OpenAI-compatible LLM client for R — auto-configured via `.Rprofile` |
| shiny | R Shiny web application framework |
| rmarkdown, knitr | Reproducible document authoring; PDF output via Pandoc |
| ggplot2 | Data visualisation |
| dplyr | Data manipulation (filter, select, mutate, summarise) |
| tidyr | Data reshaping (pivoting, separating columns) |
| readr | Reading rectangular data files (CSV etc.) |
| tibble | Modern data frames |
| purrr | Functional programming and iteration |
| stringr | String processing |
| forcats | Categorical variable (factor) handling |
| plotly | Interactive plots |
| DBI, RPostgres | PostgreSQL connectivity from R |
| RSQLite | SQLite connectivity from R |
| jsonlite | JSON parsing and generation |

### Python packages

| Package | Purpose |
|---------|---------|
| pandas, numpy | Core data science |
| matplotlib, seaborn, plotly | Visualisation |
| scikit-learn | Machine learning |
| dash, dash-bootstrap-components | Interactive web apps (Python equivalent of R Shiny) |
| shiny | Python Shiny web apps |
| debugpy | Python debugging (used by the debugpy extension) |
| ruff | Fast Python linter and formatter |
| psycopg2-binary | PostgreSQL connectivity |
| radian | R terminal (Python-based) |
| uv | Python package/environment manager |
| markdown, mistune | Markdown processing |

### VS Code extensions

All extensions are installed from [Open VSX](https://open-vsx.org/) at image build time
and baked into the image — no marketplace access required at runtime.

| Extension | Purpose |
|-----------|---------|
| `continue.continue` | AI coding assistant — chat and tab autocomplete via Aira |
| `ms-python.python` | Python language support |
| `ms-python.debugpy` | Python debugger |
| `charliermarsh.ruff` | Python linting and formatting |
| `reditorsupport.r` | R language support, plot viewer, workspace browser |
| `rdebugger.r-debugger` | R debugger |
| `posit.shiny` | R and Python Shiny app runner with inline preview |
| `mtxr.sqltools` | SQL editor and query runner |
| `mtxr.sqltools-driver-pg` | PostgreSQL driver for SQLtools |
| `alexcvzz.vscode-sqlite` | SQLite browser |
| `shd101wyy.markdown-preview-enhanced` | Rich Markdown preview with Pandoc export |
| `yzhang.markdown-all-in-one` | Markdown shortcuts, TOC, table formatting |
| `quarto.quarto` | Quarto document authoring (R/Python/Markdown) |
| `mechatroner.rainbow-csv` | CSV/TSV viewing and highlighting |
| `redhat.vscode-yaml` | YAML editing and validation |
| `eamodio.gitlens` | Git history, blame, and Gitea integration |

---

## Environment variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `WORKSPACE_API_KEY` | Yes | API key for Aira — injected into Continue config and R `.Rprofile` at startup |

---

## AI integration (Continue.dev + Aira)

The image uses [continue.dev](https://continue.dev/) rather than a general-purpose AI
extension. Two separate routes are configured:

**Chat** — routed directly to the Aira `/chat/completions` endpoint using `WORKSPACE_API_KEY`.
Users can ask questions, generate code, and explain files via the Continue sidebar.

**Tab autocomplete** — routed through a local FIM proxy (`fim_proxy.py`) running on
`127.0.0.1:8090`. Continue sends fill-in-the-middle (FIM) requests to the `/completions`
endpoint; the proxy translates these to `/chat/completions` format that Aira understands,
since Aira does not expose a native FIM endpoint. The proxy also sends an immediate SSE
keepalive to prevent Continue from timing out while waiting for the upstream response.

The Continue config is written fresh at every container start (so `WORKSPACE_API_KEY` is
always current) and then locked read-only (`chmod 444`) to prevent the extension from
overwriting it.

**R (ellmer)** — the `.Rprofile` in the workspace configures `ellmer` to use Aira as its
backend, making it available for R-native LLM workflows. If `ellmer` is not installed it
is skipped silently — it does not block the R session from starting.

---

## Persistent package libraries

Packages installed during a session are written to the workspace mount so they survive
container restarts:

| Language | Path |
|----------|------|
| R | `/home/workspace/files/R/<R-version>/` (e.g. `R/4.5.0/`) |
| Python | `/home/workspace/files/python-libs/` |

R's library search path (`R_LIBS`) is set to the workspace library first, then the
system site-library, so image-baked packages (`httpgd`, `languageserver` etc.) are
always found even if the workspace library is empty or on a read-only mount.

---

## Viewing running apps (Shiny, Dash)

The built-in code-server port proxy is **disabled** (`--disable-proxy`) because it
generates URLs that attempt to open an external browser, which crashes the session in
the TRE browser context.

To view a running app, use the built-in **Simple Browser**:

1. Start your app (R Shiny via the Run App button, Python via terminal)
2. `Ctrl+Shift+P` → `Simple Browser: Show`
3. Enter `http://127.0.0.1:<port>` (e.g. `http://127.0.0.1:8050` for Dash)

Python Dash apps must bind to `127.0.0.1`, not `0.0.0.0`.

The `workbench.openLinksInSimpleBrowser` setting is enabled — after a full container
restart this should intercept localhost URL clicks and open them in the Simple Browser
panel automatically.

---

## Markdown and PDF export

Markdown preview and export is provided by `markdown-preview-enhanced`. To export a
Markdown file to PDF via Pandoc:

1. Add a front matter block to your `.md` file:
   ```yaml
   ---
   output:
     pdf_document: default
   ---
   ```
2. Open the Markdown preview (`Ctrl+Shift+V`)
3. Right-click the preview → Export → Pandoc

`pandoc`, `texlive-latex-base`, and `lmodern` are pre-installed for PDF output.

---

## Git and Gitea

Standard VS Code git support works with any Gitea instance accessible from within the
workspace network. GitLens (`eamodio.gitlens`) is pre-installed for enhanced history
and blame views. Users will need to configure their git identity on first use:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

---

## Build

```bash
docker build -t vscode-tre:latest .
```

Extensions are installed from Open VSX during the build — outbound HTTPS to
`open-vsx.org` is required at build time only, not at runtime.

## Local testing

```bash
docker run -d \
  --name vscode-test \
  -p 8080:8080 \
  -e WORKSPACE_API_KEY=your-aira-key \
  -v /some/local/path:/home/workspace/files \
  vscode-tre:latest
```

Access at `http://localhost:8080`.

Without a workspace mount the container will still start, but R and Python packages
installed during the session will not persist.

---

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage image build |
| `fim_proxy.py` | FIM-to-chat translation proxy for Continue tab autocomplete |
