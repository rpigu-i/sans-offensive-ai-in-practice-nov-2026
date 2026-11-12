# SANS Workshop — Offensive AI in Practice
## Hands-on exploitation of a vulnerable app with open-source pentest tools · November 2026

In this lab you run three open-source, AI-assisted pentest tools — **ZAP**, **Shannon**, and **PentestGPT** — against a deliberately vulnerable web app (**OWASP Juice Shop**), all wired together with Docker Compose. Everything runs in containers on your own machine (or in a GitHub Codespace).

> **Do this at home before the workshop.** Run the setup and `./verify-setup.sh` on the same laptop and network you'll use on the day, at least a few days ahead. The verify step makes one live model call with your Anthropic API key (a few cents, no scan) to confirm the key works.

---

## Table of Contents

- [Before you start: cost & API credit](#before-you-start-cost--api-credit)
- [Prerequisites](#prerequisites)
- [Choose your path](#choose-your-path)
- [Setup](#setup)
- [Verify your setup](#verify-your-setup)
- [What you now have](#what-you-now-have)
- [Recommended running order](#recommended-running-order)
- [Run ZAP baseline](#run-zap-baseline)
- [Run Shannon](#run-shannon)
- [Run PentestGPT](#run-pentestgpt)
- [Run ARTEX (optional 4th tool)](#run-artex-optional-4th-tool)
- [Run Strix (optional 5th tool)](#run-strix-optional-5th-tool)
- [Where reports are saved](#where-reports-are-saved)
- [Resetting between runs](#resetting-between-runs)
- [Troubleshooting](#troubleshooting)
- [Quick reference (cheat sheet)](#quick-reference-cheat-sheet)

---

## Before you start: cost & API credit

Shannon and PentestGPT both call the Anthropic API on **your** key. ZAP does not use the API at all.

- **Load at least $40 of credit** on your Anthropic account, and make sure any spend limit on your organization or workspace allows it.
- **A completed lite Shannon run costs about $25–30.** One measured run in October 2026 cost **$27.01** (81 minutes, 217 turns, 8 agents). A PentestGPT session adds only ~$2.
- **If credit runs out mid-scan, every Shannon agent fails at once** with a non-retryable error, and you lose the run. `verify-setup.sh` makes a live call to check your key works but **cannot** detect low credit — so give yourself headroom.

> Earlier drafts of this README suggested "$15–20" and a $25 floor. That figure came from a run that was *stopped early* and extrapolated; a run that completes costs more. Budget for $40.

---

## Prerequisites

- **Docker + Docker Compose** — Docker Desktop: https://www.docker.com/products/docker-desktop/
- **An Anthropic API key** — https://platform.claude.com/ (see [cost & API credit](#before-you-start-cost--api-credit))
- **Resources:** at least **8 GB of memory** available to Docker and about **20 GB of free disk** (≈30 GB if you also build the optional ARTEX image; add ≈7 GB for the optional Strix images).
- **Free ports:** `3000`, `7233`, and `8233`.
- **Outbound network** to `api.anthropic.com`, Docker Hub, GitHub, npm, PyPI, and the Ubuntu package mirrors. A TLS-inspecting proxy breaks the image builds and the API calls.

Clone this repository:

```bash
# HTTPS (works everywhere)
git clone https://github.com/rpigu-i/sans-offensive-ai-in-practice-nov-2026.git

# …or SSH, if you have GitHub SSH keys set up
git clone git@github.com:rpigu-i/sans-offensive-ai-in-practice-nov-2026.git
```

---

## Choose your path

Pick the one that matches your machine, then jump to [Setup](#setup):

- **Local on macOS / Linux** — the default. Just install Docker Desktop and continue to [Setup](#setup).
- **Windows** — see [Windows participants](#windows-participants) below, then [Setup](#setup).
- **No Docker allowed (locked-down laptop)** — run the whole lab in a browser via [GitHub Codespaces](#github-codespaces).

### Windows participants

The easiest option on Windows is [Codespaces](#github-codespaces). To run locally instead, note that all setup scripts and the tool containers are Linux, so run everything **inside WSL2** (recommended):

1. Install Docker Desktop with the WSL2 backend, and turn on integration for your Ubuntu distribution (Docker Desktop → Settings → Resources → WSL integration).
2. Open an **Ubuntu (WSL) terminal** and clone this repository into your Linux home folder (`cd ~`), **not** under `/mnt/c/...`. Files on the Windows drive are slow to share with containers, are scanned by endpoint security, and can end up with Windows line endings.
3. Run `./setup.sh` and the rest of [Setup](#setup) from that terminal. On Linux and WSL2, `setup.sh` records your user ID in `.env` so Shannon can write its findings to your folders.

**If you must use Git Bash instead of WSL2:**
- Before cloning anything, run `git config --global core.autocrlf input`. Git for Windows otherwise converts files to Windows (CRLF) line endings, and the scripts and containers fail with errors like `$'\r': command not found` or `/usr/bin/env: 'bash\r': No such file or directory`.
- Put `MSYS_NO_PATHCONV=1` in front of the Shannon `docker compose run` commands. Without it, Git Bash rewrites `/app/repos/...` into a Windows path.
- Don't use PowerShell or Command Prompt: the multi-line commands use bash `\` line continuations.

**Corporate laptops: check these with IT before the workshop.**
- **Docker Desktop:** must be allowed and licensed (larger companies need a paid Docker subscription), with virtualization and WSL2 enabled.
- **Endpoint security:** it may flag or quarantine ZAP, nmap, or the deliberately vulnerable Juice Shop source. Ask for an exception, or use a non-corporate machine.

### GitHub Codespaces

If you can't install Docker on your laptop, run the whole lab in a Codespace. You only need a browser and a GitHub account.

1. **Add your API key as a Codespaces secret** before you create the codespace: github.com → your profile → **Settings → Codespaces → Secrets → New secret**. Name it `ANTHROPIC_API_KEY`, paste your key, and give this repository access to it. Don't put the key in a file in the repository.
2. **Create the codespace:** on the repository page, click **Code → Codespaces → Create codespace on main**. Choose a machine with at least **4 cores** if asked (4-core = 16 GB memory, 32 GB disk). Pick **8 cores** (32 GB memory, 64 GB disk) if you plan to run ARTEX a lot — it uses your free core-hours twice as fast.
3. **Wait for setup.** The first start clones the tools and builds the Docker images, which takes several minutes. When it finishes, the lab services start automatically.
4. **Verify:** in the codespace terminal, run `cd workshop-bundle && ./verify-setup.sh`.
5. **Run the tools** with the commands below, from `workshop-bundle/` in the codespace terminal. Open the **Ports** tab to reach Juice Shop (3000) and the Temporal UI (8233) in your browser.

**Cost:** personal GitHub accounts include 120 core-hours of Codespaces a month for free (~30 hours on a 4-core machine). **Stop the codespace when you're not using it**, and delete it after the workshop. Try this a few days early — some corporate networks block Codespaces.

---

## Setup

All commands run from the **`workshop-bundle/`** directory — that's where `docker-compose.yml` lives.

```bash
cd sans-offensive-ai-in-practice-nov-2026/workshop-bundle
./setup.sh                    # clones the tools + Juice Shop source, creates folders
# Edit .env and add your ANTHROPIC_API_KEY
docker compose up -d          # start all services
```

`setup.sh` does everything the lab needs:
1. Creates the `tools/` and `workspace/` structure and the `out/` report folders.
2. Clones **Shannon** and **PentestGPT** (PentestGPT is pinned to commit `b986930`, the last version with the `pentestgpt` command).
3. Copies the Shannon configs (`juice-shop.yaml`, `juice-shop-lite.yaml`) into place.
4. Clones the **Juice Shop source** into `workspace/juice-shop/` (Shannon analyzes it as a white-box target) and sets a local git identity for it.

> **Note:** both Shannon and PentestGPT ship their own `Dockerfile`, and Docker Compose builds from those. **Don't overwrite them** with the files in `workshop-bundle/dockerfiles/` — those are outdated fallbacks that no longer build against current upstream code.

> **Note:** `docker compose up -d` also starts the `zap-baseline` service, which runs a one-shot ZAP scan immediately and then exits. That's expected — you'll see a `zap-baseline` container do ~5 minutes of work on startup. You can re-run it on demand later (see [Run ZAP baseline](#run-zap-baseline)).

<details>
<summary><strong>Manual setup (alternative — if you'd rather run each step yourself)</strong></summary>

```bash
cd workshop-bundle

# 1. API key
cp .env.example .env
# Edit .env and add your ANTHROPIC_API_KEY

# 2. Clone the tools
mkdir -p tools
git clone https://github.com/KeygraphHQ/shannon tools/shannon
git clone https://github.com/greydgl/pentestgpt tools/PentestGPT
# Upstream removed the `pentestgpt` command on 2026-07-13; pin to the last version that has it
git -C tools/PentestGPT checkout b986930

# 3. Shannon config
mkdir -p tools/shannon/configs
cp ../juice-shop.yaml tools/shannon/configs/juice-shop.yaml
cp ../juice-shop-lite.yaml tools/shannon/configs/juice-shop-lite.yaml

# 4. Juice Shop source (Shannon's white-box target)
git clone https://github.com/juice-shop/juice-shop.git workspace/juice-shop
cd workspace/juice-shop
git config user.email "pentest@localhost"
git config user.name "Pentest Agent"
cd ../..

# 5. Start services
docker compose up -d
```

The `git config` lines set a committer identity for the Juice Shop repo only — Shannon creates git checkpoints during pre-recon, which requires a configured user even though nothing is pushed upstream.

</details>

### If a key is already exported in your shell

Docker Compose reads `ANTHROPIC_API_KEY` from your environment **in preference to** `.env`. If you've exported the key in your shell (or a dotfile), editing `.env` has no effect — Compose keeps using the exported value. Either update it where it's exported, or `unset ANTHROPIC_API_KEY` in the terminal you run Compose from so `.env` wins.

---

## Verify your setup

```bash
docker compose ps          # all services should be Up (healthy)
./verify-setup.sh          # checks files, services, and makes one live key-check call
```

`verify-setup.sh` makes **one** live model call (a few cents, no scan) to confirm your key works and passes Shannon's security-access check. Fix any ✗ errors it reports before the workshop.

You should see these services:
- `juice-shop` — Up (healthy)
- `shannon-postgres` — Up (healthy)
- `shannon-temporal` — Up (healthy)
- `shannon-temporal-ui` — Up
- `pentestgpt` — Up
- (`shannon-worker` is **not** listed here — it's a one-shot job you launch with `docker compose run`; see [Run Shannon](#run-shannon).)

**Monitor URLs:**
- Juice Shop: http://localhost:3000
- Temporal UI: http://localhost:8233

---

## What you now have

<details>
<summary>Directory map (after setup)</summary>

```
sans-offensive-ai-in-practice-nov-2026/
├── README.md                          <-- You are here
└── workshop-bundle/
    ├── .env                           <-- Your API keys (copy from .env.example)
    ├── .env.example
    ├── docker-compose.yml             <-- Defines all services (run compose from here)
    │
    ├── tools/                         <-- Cloned tool repositories
    │   ├── shannon/                   <-- git clone https://github.com/KeygraphHQ/shannon
    │   │   ├── Dockerfile
    │   │   ├── apps/
    │   │   ├── configs/               <-- juice-shop.yaml, juice-shop-lite.yaml
    │   │   └── ...
    │   ├── PentestGPT/                <-- git clone https://github.com/greydgl/pentestgpt (pinned b986930)
    │   │   ├── Dockerfile
    │   │   └── ...
    │   └── artex/                     <-- (optional) git clone https://github.com/BillReyor/ARTEX
    │       ├── workshop.Dockerfile    <-- copied in by setup.sh (multi-stage build)
    │       └── ...
    │
    ├── workspace/                     <-- Shared working dir (mounted into containers)
    │   └── juice-shop/                <-- Target source for Shannon
    │       └── .shannon/deliverables/ <-- Shannon's security reports land here
    │
    └── out/                           <-- Tool output / reports
        ├── zap/                       <-- ZAP scan reports
        ├── shannon/                   <-- Shannon audit logs and session data
        ├── artex/                     <-- (optional) ARTEX findings, sessions, reports
        └── strix/                     <-- (optional) Strix runs: findings + final report
```

- The `tools/` directory holds **full git clones** of Shannon and PentestGPT — Compose needs each repo's `Dockerfile` to build the worker containers.
- `workspace/` is mounted into both Shannon and PentestGPT, so findings persist on your host.
- `out/` collects reports from ZAP and Shannon.

</details>

---

## Recommended running order

The three tools are independent and **safe to run at the same time** — they don't interfere with each other (separate outputs, no port or container clashes). Because Shannon is by far the longest, start it first and do the others while it works:

1. **Start Shannon first** ([Run Shannon](#run-shannon)) — the lite run takes roughly an hour. Kick it off and leave it.
2. **While Shannon runs**, do the [ZAP baseline](#run-zap-baseline) (~5 min) and a [PentestGPT session](#run-pentestgpt) (~10–20 min). Both share the live Juice Shop target with Shannon without any problem.
3. **Come back to Shannon** when it finishes and review its report.

Optionally, add [ARTEX](#run-artex-optional-4th-tool) as a supervised, GUI-driven segment. It's interactive (you approve each step), so run it as its own focused block rather than fire-and-forget — and not at the same time as a Shannon scan on a small machine.

Optionally, add [Strix](#run-strix-optional-5th-tool) as a fire-and-forget black-box scan with a live web dashboard. A `quick` run is a good contrast to Shannon's white-box analysis. The same small-machine caveat applies.

> Remember the AI tools all draw on the same API credit (ZAP is free). See [cost & API credit](#before-you-start-cost--api-credit).

---

## Run ZAP baseline

```bash
docker compose run --rm zap-baseline
# report at: ./out/zap/zap_baseline_report.html
```

This passive baseline scan takes about five minutes. The scan script ships in the official ZAP image.

> **Exit code 2 is normal.** ZAP baseline exits non-zero when it finds **warnings** (exit 2) or failures (exit 1); Juice Shop always produces warnings, so a clean run still "exits 2". That is **not** an error — check the report for the `PASS/WARN/FAIL` summary.

---

## Run Shannon

Shannon is a **white-box** AI pentester: it analyzes the target's source code to guide its exploitation strategy. The services from [Setup](#setup) should already be running.

Shannon writes intermediate findings into `workspace/juice-shop/.shannon/`. The Juice Shop source was cloned there by `setup.sh` — **you only need to re-clone it when resetting** between runs (see [Resetting between runs](#resetting-between-runs)).

> ⚠️ **Don't point Shannon at an empty repo.** Its pre-recon agents will spin for hundreds of turns looking for code that isn't there, and may fall back on stale deliverables — producing hallucinated findings instead of real ones.

### Workshop lite run (use this in the workshop)

Each participant runs Shannon on their own API key, so the workshop uses the smaller `juice-shop-lite.yaml`:

- `exploit: "false"` — runs recon and vulnerability analysis, skips the exploitation phase
- Focuses on two endpoints only: `/rest/user/login` and `/api/Users`

**Time and cost: about an hour, ~$25–30 per run** (see [cost & API credit](#before-you-start-cost--api-credit)). The focus rules don't shorten the first two phases, which analyze the whole Juice Shop codebase. Reference timings:

| Phase | Time |
|---|---|
| Login check | ~2 min |
| Pre-Recon | ~17 min |
| Recon | ~16 min |
| Vulnerability analysis (5 agents in parallel) | remainder |

Start the scan early and work on other material while it runs.

```bash
docker compose run --rm shannon-worker node apps/worker/dist/temporal/worker.js \
  http://juice-shop:3000 \
  /app/repos/juice-shop \
  --task-queue shannon \
  --config /app/configs/juice-shop-lite.yaml
```

If a live run fails, use the complete set of Shannon results in `example_deliverables/` to follow along.

### Full run (every phase, including exploitation)

The full configuration runs every phase, including exploitation. It takes longer and costs more than the lite run (a test run spent ~$28 before the account ran out of credit partway through exploitation):

```bash
docker compose run --rm shannon-worker node apps/worker/dist/temporal/worker.js \
  http://juice-shop:3000 \
  /app/repos/juice-shop \
  --task-queue shannon \
  --config /app/configs/juice-shop.yaml
```

> ℹ️ **Path note:** `/app/repos/juice-shop` and `/app/configs/juice-shop.yaml` are paths **inside the worker container**, mapped from the host via volume mounts in `docker-compose.yml`:
>
> | Inside container | On host (relative to `workshop-bundle/`) |
> |---|---|
> | `/app/repos/juice-shop` | `./workspace/juice-shop` |
> | `/app/configs/juice-shop.yaml` | `./tools/shannon/configs/juice-shop.yaml` |

### Monitor progress

- **Temporal Web UI** (recommended): http://localhost:8233 — real-time workflow execution, activity history, task queues.
- **Worker logs:** `docker compose logs -f shannon-worker`
- **Workflow status:** `docker compose exec shannon-worker node apps/worker/dist/temporal/query.js <workflow-id>`

The pentest runs through 5 phases: **Pre-Recon** → **Recon** → **Vulnerability Analysis** (5 parallel agents: injection, xss, auth, authz, ssrf) → **Exploitation** → **Reporting**.

### Results

- `workspace/juice-shop/.shannon/deliverables/` — security findings and reports
- `out/shannon/` — audit logs and session data

---

## Run PentestGPT

PentestGPT is included in `tools/PentestGPT/` and its container starts with `docker compose up -d`.

### Connect and run

```bash
docker compose exec -it pentestgpt bash   # drops you into /workspace
pentestgpt --target juice-shop:3000 --no-telemetry
```

Or with specific instructions:

```bash
pentestgpt --target juice-shop:3000 --no-telemetry --instruction "Focus on authentication bypass vulnerabilities"
```

> **Telemetry:** PentestGPT sends usage data to Langfuse (`us.cloud.langfuse.com`) unless you pass `--no-telemetry`. Every command here includes it.

### Common options

```bash
pentestgpt --target juice-shop:3000 --no-telemetry                 # Default mode (ctf: depth-first exploitation)
pentestgpt --target juice-shop:3000 --no-telemetry --mode pentest  # Breadth-first vulnerability identification
pentestgpt --target juice-shop:3000 --no-telemetry -v              # Verbose
pentestgpt --list-sessions                                         # List previous sessions
pentestgpt --target juice-shop:3000 --no-telemetry --resume --session-id <id>
```

PentestGPT prints progress as plain text: each stage (e.g. `[Stage 1/3] Asset Identification`), then every tool it runs (`[TOOL] Bash: ...`). It runs Claude Code inside the container with permission prompts off, so the commands it chooses run immediately — the container is the safety boundary.

### Output

The walkthrough it generates persists on your host at:

- `workshop-bundle/workspace/workspace/juice-shop-walkthrough.md`

It also prints a final report to the screen and saves a copy to `/tmp/FINAL_REPORT.md`, and keeps session state under `~/.pentestgpt/sessions`. **Both live inside the container and are *not* mounted, so they are lost when the container is recreated or removed.** To keep the final report, copy it out first:

```bash
docker compose cp pentestgpt:/tmp/FINAL_REPORT.md out/pentestgpt-FINAL_REPORT.md
```

To stop it, press **Ctrl+C**. If anything is still running, restart the container: `docker compose restart pentestgpt`.

> **`ENOENT: ... uv_cwd` error?** The container needs recreating: `docker compose up -d pentestgpt`.

---

## Run ARTEX (optional 4th tool)

ARTEX is an **AI autonomous pentester with a web dashboard and a human-in-the-loop approval gate** — a different flavour from the other three: instead of reading logs, you *watch and steer* the agents from a UI, approving each tool call. It runs an LLM-driven planner/worker agent system over a dual asset/exploration graph, records traffic through a MITM proxy, and visualizes findings, coverage, and token usage.

It's **optional** and gated behind the `artex` Docker Compose profile, so `docker compose up -d` never starts it. It's **built from source** (`setup.sh` clones ARTEX, and `docker compose` builds a multi-stage image — upstream publishes no usable image) and uses its **own** PostgreSQL, isolated from Shannon's.

> ⚠️ **Scope — read before using.** ARTEX is an autonomous pentester: only run it against systems you own or are explicitly authorized to test. In this workshop that means point ARTEX **only at the local Juice Shop container**, never at any real or internet-facing target. ARTEX is licensed under **AGPL-3.0**; see the project's README: https://github.com/BillReyor/ARTEX

### Start ARTEX

From `workshop-bundle/` (services from setup should already be running):

```bash
docker compose --profile artex up -d artex && docker builder prune -af
```

That starts ARTEX plus its dedicated Postgres and waits for Juice Shop to be healthy. **The first launch builds the image from source** (Next.js export → Go compile → Playwright/Chromium), which takes several minutes. The `docker builder prune -af` then deletes the build cache that leaves behind (several GB), keeping the image; on later launches there's nothing to build, so it's a no-op.

### First-run setup

1. **Open the dashboard** — **http://localhost:8787** locally, or the forwarded **8787** URL from the **Ports** tab in a Codespace.
2. On first visit you land on **`/setup`** to **set an admin password** (once per machine; this works over the Codespace forwarded URL too).

### Create and run a task

Click **Create new task** (top right). Two fields drive the run, and their names are a little unintuitive — **fill both** (ARTEX requires it):

| Field | What it actually wants | Example |
| --- | --- | --- |
| **Description** | The **target + background** — this is where the URL goes | `OWASP Juice Shop at http://juice-shop:3000, running locally in the workshop lab. Scope: this host only.` |
| **Target** | The **goal**, *not* the URL | `Demonstrate a SQL-injection authentication bypass on the login endpoint (/rest/user/login) — log in without valid credentials.` |

> Use the Compose hostname **`http://juice-shop:3000`** (not `localhost`) — ARTEX reaches Juice Shop over the Compose network. Keep the scope to the local Juice Shop only — the lab never targets any real or internet-facing system.

Click **Create**, open the task, and it runs **autonomously** — by default it does *not* pause for per-step approval (that's optional: enable a human-in-the-loop gate under **Intercept rule** / **Approval Records**). Watch it on:

- **Session** — live agent dialogue and running token counts
- **Tool execution** — every command the agents run
- **Discover** (and the Dashboard's Discover panel) — findings as they land

**What success looks like:** within a few minutes ARTEX reports a **Severe** finding — *SQL injection* on `POST /rest/user/login` — with a PoC like `{"email":"' OR 1=1--","password":"anything"}` that returns the **admin JWT** (`role=admin`). On `claude-sonnet-4-6` the run is roughly **130–200k tokens (≈$0.40)**.

The MITM proxy is published on **127.0.0.1:8788** (localhost only) if you want to route traffic through it.

### Cost

ARTEX calls the Anthropic API on the same `ANTHROPIC_API_KEY` as Shannon and PentestGPT, and it's autonomous — budget for it the same way and keep headroom (see [Before you start: cost & API credit](#before-you-start-cost--api-credit)). ZAP is the only tool that costs nothing.

> **Model & cost.** `.env` ships **`ARTEX_LLM_MODEL=claude-sonnet-4-6`** by default to keep the workshop cheap (~$0.40/run). If you **clear** `ARTEX_LLM_MODEL`, ARTEX falls back to an **Opus** model — several times the cost and tokens. Change the model in `.env` or in the ARTEX UI (**System → LLM**) before starting a task. The same `.env` applies in a Codespace (the Codespaces secret only supplies the API key, not the model).

### Output

ARTEX persists findings, sessions, and reports to **`out/artex/`** on the host (mounted at `/app/data`). The admin account lives in `artex-postgres`, so it survives restarts; the session signing key is regenerated when the container is recreated, so you may need to log in again after a rebuild.

### Stop ARTEX

```bash
docker compose --profile artex stop artex artex-postgres
# or remove them: docker compose --profile artex rm -sf artex artex-postgres
```

### Running ARTEX in a Codespace

ARTEX runs in a Codespace the same way the rest of the lab does, with a few caveats:

- **Forward the port.** Codespaces auto-forwards **8787** (and the 8788 proxy) as **Private** — open the **Ports** tab and click the forwarded **8787** URL. The localhost binding doesn't block this; the `/setup` and login flow works over the forwarded HTTPS URL, and "Private" keeps the (initially passwordless) dashboard off the public internet.
- **Resources.** ARTEX plus its Postgres on top of the rest of the stack can exhaust a 4-core/16 GB Codespace. **Don't run ARTEX and a Shannon scan at the same time** on a 4-core machine — stop one first — or use a larger (8-core/32 GB) Codespace.
- **Core-hours and disk.** ARTEX is interactive and long-lived, so it burns Codespaces core-hours faster. Its first run builds from source on the Codespace's amd64 architecture (image ≈2.4 GB plus build cache) — expect a multi-minute build and watch disk on a 4-core (32 GB) Codespace. The [Start ARTEX](#start-artex) command already prunes the build cache, and `./verify-setup.sh` warns when disk is low; check it yourself with `df -h /workspaces && docker system df`. Stop the Codespace when idle.

> **Reproducible builds.** `setup.sh` pins ARTEX to a specific commit (`ARTEX_REF` in `setup.sh`), so every participant builds the same source. Bump that ref when you want a newer ARTEX.

---

## Run Strix (optional 5th tool)

[Strix](https://github.com/usestrix/strix) is an **autonomous, multi-agent AI pentester**. A coordinating agent spawns specialist agents (recon, injection, auth, ...) that work inside a **sandbox container** loaded with real tooling: a Caido intercepting proxy, a headless browser, a terminal and a Python exploit runtime. It **validates findings with working PoCs** before reporting them. It differs from the other tools in two ways. Unlike ARTEX there's no approval gate, so it runs on its own like Shannon. Unlike Shannon it tests **black-box over HTTP** and doesn't read the source. You follow it in a terminal UI or a local web dashboard.

It's **optional** and gated behind the `strix` Docker Compose profile, so `docker compose up -d` never starts it. Nothing is cloned: Compose builds a small image from the **pinned `strix-agent` PyPI wheel** (upstream ships Linux amd64/arm64 wheels with the TUI and dashboard prebuilt). It then pulls the pinned **sandbox image** `ghcr.io/usestrix/strix-sandbox` the first time you scan.

> ⚠️ **Scope — read before using.** Strix is an autonomous pentester: only run it against systems you own or are explicitly authorized to test. In this workshop that means pointing Strix **only at the local Juice Shop container** (`http://juice-shop:3000`), never at any real or internet-facing target. Strix is licensed under **Apache-2.0**: https://github.com/usestrix/strix

> 🔐 **How it's wired (and why it's opt-in).** The Strix CLI starts its sandbox as a sibling container, so the `strix` service mounts **`/var/run/docker.sock`**, which gives it control of your Docker daemon. The sandbox joins a dedicated **`strix-net`** network that only Juice Shop and the Strix controller are on, so the agents can reach the target but not Shannon's Postgres/Temporal or anything else in the lab. Its memory is capped at 4 GB (`STRIX_SANDBOX_MEM_LIMIT`).

### Build Strix (once)

From `workshop-bundle/`:

```bash
docker compose --profile strix build strix
docker pull ghcr.io/usestrix/strix-sandbox:1.3.0   # ≈1.4 GB download, ≈5.8 GB on disk
```

Pulling the sandbox ahead of time is optional; the first scan pulls it anyway, but then the scan sits idle for a few minutes.

### Run a scan

```bash
docker compose --profile strix run --rm strix \
  -n -t http://juice-shop:3000 --scan-mode quick --max-budget-usd 10 \
  --instruction "Workshop lab. Scope: http://juice-shop:3000 only."
```

- **`-n`** runs headless: findings stream to the terminal and the final report prints at the end. Leave out `-n` for the interactive terminal UI.
- **`--scan-mode quick`** keeps it to minutes. `standard` takes 30–60 min and `deep` (upstream's default) takes 1–4 h, with matching API cost.
- **`--max-budget-usd`** is a hard spending cap. The agents get wrap-up warnings as they approach it and the scan stops cleanly at the limit. **Always set it in the workshop.** Strix runs several agents in parallel, and a quick scan spends **~$2 on reconnaissance alone before it validates anything** — a cap that low stops with **0 findings**. A *completed* quick run against Juice Shop cost about **$5.4** (see below), so set the cap to **$10** to leave headroom; cutting it too close budget-stops the scan just before it reports. Narrow the work with `--instruction` to spend less.
- **`--instruction`** steers the agents, for example `"Focus on SQL injection in POST /rest/user/login"`.

> Use the Compose hostname **`http://juice-shop:3000`** (not `localhost`). The sandbox reaches Juice Shop over `strix-net`.

A headless run **exits non-zero when it finds vulnerabilities**. That's by design for CI, not an error.

**What success looks like:** one measured quick run (November 2026, `claude-sonnet-4-6`, `STRIX_REASONING_EFFORT=medium`) finished in **~15 minutes** for **~$5.4** (≈13M tokens, nearly all cached) and reported **6 vulnerabilities — 1 critical, 5 medium**:

- **Critical — SQL injection auth bypass** on `POST /rest/user/login`: `{"email":"' OR 1=1--","password":"x"}` logs in as admin.
- **Medium** — IDOR on `/rest/basket/:id` (cross-user baskets), broken function-level authorization (any user can list all accounts via `GET /api/Users`), unauthenticated `GET /rest/admin/application-configuration`, password change without the current password on `/rest/user/change-password`, and DOM-based XSS in the search query parameter.

Each finding carries a validated PoC and reproduction steps. Your run will vary — Strix is non-deterministic.

### Watch it in the dashboard

In a second terminal (while a scan runs, or afterwards):

```bash
docker compose --profile strix run --rm --service-ports strix view --host 0.0.0.0 --port 8789 --no-open
```

It prints a link with an access token in it. Open that link with **`localhost`** in place of `0.0.0.0` (in a Codespace, use the forwarded **8789** URL and keep the token part). The dashboard shows findings with severity and reproduction steps, plus a live graph of the agent team. The port is published on **127.0.0.1 only**, because the tokened link grants access to the run. Press **Ctrl+C** to stop it. `strix view <run-name>` opens an older run.

### Cost

Strix calls the Anthropic API on the same `ANTHROPIC_API_KEY` as the other AI tools (Compose passes it in as `LLM_API_KEY`). It's multi-agent and autonomous, so give it headroom like Shannon (see [Before you start: cost & API credit](#before-you-start-cost--api-credit)) and keep `--max-budget-usd` on.

> **Model & cost.** `.env` ships **`STRIX_LLM=anthropic/claude-sonnet-4-6`** and **`STRIX_REASONING_EFFORT=medium`** to keep the workshop cheap (upstream's default effort is `high`). To change the model, set `STRIX_LLM` in `.env` to another LiteLLM model id such as `anthropic/claude-opus-4-6`; that costs more. Telemetry to Strix is off by default (`STRIX_TELEMETRY=0`).

### Output

Each run writes to **`out/strix/<run-name>/`** on the host (mounted at `/work/strix_runs`). That folder holds `findings.sarif` (the validated vulnerabilities, SARIF 2.1.0), `coverage.json` (what was tested and the gaps), `run.json` (the run record with token/cost usage) and `strix.log`. In headless mode the prose penetration-test report prints to the terminal at the end; re-open any run — with its findings and agent graph — in the [dashboard](#watch-it-in-the-dashboard) with `strix view <run-name>`. On Linux/Codespaces the files are owned by root, because the container runs as root to use the Docker socket. Use `sudo` to delete them.

### Stop / clean up Strix

Scans are one-shot (`run --rm`), so there's no long-running service to stop. Press **Ctrl+C** to abort a scan. If a sandbox container is left behind, remove it with:

```bash
docker ps -a --filter label=strix-run-id                   # list leftover sandboxes
docker rm -f $(docker ps -aq --filter label=strix-run-id)  # remove them
```

To reclaim the disk, run `docker rmi ghcr.io/usestrix/strix-sandbox:1.3.0 workshop-bundle-strix`.

### Running Strix in a Codespace

It works the same way. The devcontainer's Docker-in-Docker daemon provides `/var/run/docker.sock`. Caveats:

- **Disk.** The sandbox image is ≈5.8 GB. On a 4-core (32 GB) Codespace that also has the ARTEX image, check `df -h /workspaces && docker system df` before pulling, and remove images you're done with.
- **Resources.** Don't run a Strix scan and a Shannon scan at the same time on a 4-core/16 GB machine.
- **Dashboard.** Forward port **8789** (it shows up in the **Ports** tab once the `view` command runs) and keep it **Private**.

> **Reproducible installs.** `dockerfiles/strix.Dockerfile` pins `STRIX_VERSION`, and `docker-compose.yml` pins the matching sandbox tag in `STRIX_IMAGE`. Bump both together.

---

## Where reports are saved

All host paths are relative to `workshop-bundle/`. Anything under `workspace/` or `out/` is bind-mounted, so it persists after a run.

| Tool | Report / output | Host path |
| --- | --- | --- |
| **ZAP** | Baseline scan report (HTML) | `out/zap/zap_baseline_report.html` |
| **Shannon** | Security findings and reports | `workspace/juice-shop/.shannon/deliverables/` |
| **Shannon** | Audit logs and session data | `out/shannon/` |
| **PentestGPT** | Generated walkthrough (Markdown) | `workspace/workspace/juice-shop-walkthrough.md` |
| **ARTEX** (optional) | Findings, sessions, and reports | `out/artex/` |
| **Strix** (optional) | Validated findings (SARIF), coverage, run record, log | `out/strix/<run-name>/` |

**Not saved to the host.** PentestGPT's `/tmp/FINAL_REPORT.md` and `~/.pentestgpt/sessions` live *inside* the container and are lost when it's recreated. Copy the report out if you want to keep it (command above).

> In a codespace the same paths apply under the repository root. Use **Download…** in the file explorer, or `gh codespace cp`, to pull a report onto your laptop.

---

## Resetting between runs

Shannon writes intermediate findings to `.shannon/deliverables/` inside the target repo. If you run Shannon again without clearing this, the new run ingests the previous run's output and its analysis degrades.

**Easy way:**
```bash
# From inside workshop-bundle/
./reset-workspace.sh
```

**Manual way:**
```bash
# From inside workshop-bundle/
cd workspace/juice-shop
rm -rf .shannon
git clean -fdx
git reset --hard
cd ../..
```

`git clean -fdx` removes untracked files (including anything Shannon dropped outside `.shannon/`), and `git reset --hard` reverts modifications Shannon's exploit attempts may have made to tracked files.

---

## Troubleshooting

### Shannon scan taking too long
1. **Check for stale deliverables.** If you didn't reset between runs, Shannon may be ingesting old findings and looping — run the [reset](#resetting-between-runs) commands.
2. **Verify the config loaded.** Early in the worker log, look for `Configuration file OK` with `configPath: '/app/configs/juice-shop-lite.yaml'`. If it's missing, the `--config` flag isn't being picked up and the scan has no scope limits.
3. **Narrow the `focus` rules** in the config further — fewer focus paths means fewer hypotheses and less exploit-phase work.

### Shannon Temporal not starting
"dependency failed to start: container shannon-temporal exited (1)":
```bash
docker compose logs shannon-temporal
docker compose ps shannon-postgres          # ensure Postgres is healthy
docker compose restart shannon-temporal
```

### Port already in use
If `7233` or `8233` is already allocated:
```bash
docker compose down
docker ps -a | grep temporal
docker rm -f <container-id>
docker compose up -d
```

### Viewing logs
```bash
docker compose logs -f <service-name>   # e.g. shannon-worker, shannon-temporal, juice-shop
```

### Reset everything
```bash
cd workshop-bundle
docker compose down -v   # remove volumes
docker compose up -d
```

---

## Quick reference (cheat sheet)

For when you've done the setup once and just need the commands.

```bash
# First-time setup
cd sans-offensive-ai-in-practice-nov-2026/workshop-bundle
./setup.sh
# Edit .env and add your ANTHROPIC_API_KEY
docker compose up -d
./verify-setup.sh

# ZAP baseline (~5 min; exit 2 = warnings, not an error)
docker compose run --rm zap-baseline

# Shannon lite run (analysis only, two endpoints)
docker compose run --rm shannon-worker node apps/worker/dist/temporal/worker.js \
  http://juice-shop:3000 /app/repos/juice-shop \
  --task-queue shannon --config /app/configs/juice-shop-lite.yaml

# PentestGPT session (--no-telemetry turns off data sent to Langfuse)
docker compose exec -it pentestgpt bash
pentestgpt --target juice-shop:3000 --no-telemetry

# Strix quick black-box scan, capped at $10 (optional; exits non-zero when it finds issues)
docker compose --profile strix run --rm strix -n -t http://juice-shop:3000 --scan-mode quick --max-budget-usd 10
docker compose --profile strix run --rm --service-ports strix view --host 0.0.0.0 --port 8789 --no-open

# Reset Shannon's workspace between runs
./reset-workspace.sh
```

**Monitor:** Juice Shop http://localhost:3000 · Temporal UI http://localhost:8233
