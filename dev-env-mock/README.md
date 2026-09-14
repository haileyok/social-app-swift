# dev-env-mock

Vendored standalone copy of the RN social app's `dev-env` mock server (Node), for Linux-side integration tests and (spiked) macOS CI runs.

## What it serves

- A mock **PDS** on `http://localhost:3000` (login, repo writes, blob upload)
- A mock **bsky appview** (same `@atproto/dev-env` TestNetwork; use via `atproto-proxy` header with the mock appview DID)
- A mock PLC + ozone
- Mock users `alice/bob/carla` (handle `<name>.test`, password `hunter2`, email `fake<n>@fake.com`) with follows and posts, via the manager API

**Not served: `chat.bsky.*`** — `TestNetwork` in `@atproto/dev-env` does not include a chat service ("must run separate chat service" per its own docs). Messages (Phase 5) tests must run against the `TestSupport` fake XRPC chat server instead. This is the documented plan fallback, now confirmed.

## Running (external PG/Redis, no Docker)

```bash
# prerequisites: postgres on :5433 (user pg / password password / db postgres), redis on :6380
pnpm install
pnpm start:external
# then create the test network with users/follows/posts:
curl -X POST 'http://localhost:1986?users&follows&posts'
```

The manager listens on :1986; POSTing restarts the underlying network.

### Local setup on this Linux workstation (recorded 2026-09-14)

- `postgresql` (18) via apt: create user `pg` (superuser, password `password`), db `postgres`, and a listener on port 5433 (`/etc/postgresql/18/main/conf.d/ports.conf` → `port = 5433`).
- `redis-server` via apt: `redis-server --port 6380 --daemonize yes`.

### macOS runner (ios.yml spike job)

- `brew install postgresql@16 redis` (or use runner preinstalls), start both with the same ports/credentials, then `pnpm install && pnpm start:external` the same way. The spike job in `.github/workflows/ios.yml` (`mock-server-spike`) proves this on `macos-26` and records results in its logs.

## Provenance / pin

Copied from `~/bluesky/social-app` at commit (see git history of the copy; the RN repo is read-only reference). `mock-server.ts`, `test-pds.ts`, `constants.ts` are lightly adapted:

- avatar asset path points inside this dir (`assets/` vendored alongside)
- `pnpm-workspace.yaml` declares itself (`packages: ['.']`) so it installs standalone
- lockfile regenerated for the standalone layout (the source's nested lockfile doesn't apply)

`@atproto/dev-env` version is pinned by `package.json` (`^0.5.3` at vendoring time; lockfile pins exact).
