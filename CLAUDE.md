# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Autonomys fork of **Blockscout** (v9.3.2) — an EVM blockchain explorer. Customized for the Autonomys network (Chain ID 870, native token AI3). Built with Elixir/OTP as a Phoenix umbrella project.

## Tool Versions

- Elixir 1.19.4-otp-27, Erlang 27.3.4.6, Node.js 20.17.0 (see `.tool-versions`)

## Build & Run Commands

```bash
# Install deps and compile
mix do deps.get, deps.compile, compile

# Database setup
mix ecto.create && mix ecto.migrate

# Run the server
mix phx.server

# Interactive shell with app loaded
iex -S mix

# Run with environment from init.sh (sets Autonomys-specific env vars)
source init.sh
```

## Testing & Code Quality

```bash
# Run all tests (umbrella-wide)
mix test

# Run tests for a specific app
mix test --app explorer
mix test --app block_scout_web
mix test --app indexer

# Run a single test file
mix test apps/explorer/test/explorer/chain_test.exs

# Run a specific test by line number
mix test apps/explorer/test/explorer/chain_test.exs:42

# Code formatting
mix format              # Auto-format
mix format --check-formatted  # Check only

# Linting
mix credo --strict

# Security scan
mix sobelow --config

# Static type checking (slow, uses cached PLTs in priv/plts/)
mix dialyzer --halt-exit-status
```

## Umbrella Architecture

Six Elixir apps under `apps/`, each with its own `mix.exs`, `config/`, `lib/`, and `test/`:

| App | Purpose |
|-----|---------|
| **explorer** | Data model layer — Ecto schemas, database queries, chain data access. The central `Explorer.Chain` module (141KB) is the main query interface. Schemas live in `explorer/chain/`. |
| **block_scout_web** | Phoenix HTTP layer — REST controllers, GraphQL, Etherscan-compatible API, Phoenix channels for real-time updates. |
| **indexer** | Blockchain data ingestion — fetchers for blocks, transactions, internal transactions, balances, tokens. Supervision trees manage concurrent fetcher processes. |
| **ethereum_jsonrpc** | Low-level JSON-RPC client — HTTP/WebSocket transport, batch requests, multi-client support (Geth, Erigon, Nethermind). |
| **nft_media_handler** | NFT metadata/media fetching and caching. |
| **utils** | Shared utilities across all apps. |

**Dependency flow**: `ethereum_jsonrpc` <- `explorer` <- `indexer` / `block_scout_web`

## Configuration

- **Compile-time**: `config/config.exs` imports per-app configs from `apps/*/config/config.exs`
- **Runtime**: `config/runtime.exs` (93KB) maps hundreds of environment variables — this is where most configuration lives
- **Helper**: `config/config_helper.exs` provides env var parsing utilities
- Prefer **runtime configuration** over compile-time. Use `Utils.RuntimeEnvHelper` and pattern matching instead of `Utils.CompileTimeEnvHelper` unless modifying existing database schemas.

## Key Environment Variables (Local Dev)

Set via `init.sh` or manually:

- `DATABASE_URL` — PostgreSQL connection (default: `postgresql://blockscout:blockscout@localhost:5432/autonomys`)
- `ETHEREUM_JSONRPC_HTTP_URL` / `_WS_URL` / `_TRACE_URL` — RPC endpoints
- `ETHEREUM_JSONRPC_VARIANT` — Node type (`geth`, `erigon`, etc.)
- `CHAIN_ID`, `COIN`, `COIN_NAME` — Network identity (870, AI3, AI3)
- `APPLICATION_MODE` — `all` (indexer+API) or `api` (API only)
- `DISABLE_CATCHUP_INDEXER`, `DISABLE_REALTIME_INDEXER` — Toggle indexers
- `INDEXER_DISABLE_*` — Disable specific fetchers

## Database

PostgreSQL with Ecto. Multiple repos exist (main `Explorer.Repo`, plus feature-specific repos like `Explorer.Repo.Account`).

```bash
# Migrations
mix ecto.migrate
mix ecto.rollback

# Specific repo
mix ecto.migrate -r Explorer.Repo.Account
mix ecto.create -r Explorer.Repo.Account
```

## Naming Conventions

- Use full names: `transaction` not `tx`/`txn`, `block_number` not `block_num`, `address_hash` not `address`
- API v2 responses: hashes as hex strings ending `_hash`, block numbers as numbers ending `_block_number`, indexes as numbers ending `_index`, aggregations as `transactions_count`, `blocks_count`

## CI/CD & Deployment

- GitHub Actions workflow (`.github/workflows/build-push.yml`) builds two Docker images: **indexer** (API disabled) and **api** (API enabled)
- Deploys only from `testnet` branch to OVH Managed Private Registry
- Tags: `{branch}-{commit_hash}` and `{branch}-latest`
- Docker build: multi-stage Alpine (`docker/Dockerfile`)
- Conventional commits: `feat:`, `fix:`, `chore:`, `doc:`, `perf:`, `refactor:`

## Docker Compose (Local Full Stack)

```bash
cd docker-compose
docker-compose -f docker-compose.yml up --build
```

Orchestrates: PostgreSQL, Redis, backend, frontend, NFT handler, and Rust microservices (stats, visualizer, sig-provider, user-ops-indexer) behind Nginx.
