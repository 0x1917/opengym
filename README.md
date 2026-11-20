# OpenGym

[![Version](https://img.shields.io/docker/v/0x1917/opengym)](https://hub.docker.com/r/0x1917/opengym)
[![Build](https://github.com/0x1917/opengym/actions/workflows/build.yml/badge.svg)](https://github.com/0x1917/opengym/actions/workflows/build.yml)
[![Lint](https://github.com/0x1917/opengym/actions/workflows/lint.yml/badge.svg)](https://github.com/0x1917/opengym/actions/workflows/lint.yml)
[![Pulls](https://img.shields.io/docker/pulls/0x1917/opengym)](https://hub.docker.com/r/0x1917/opengym)
[![Image size](https://img.shields.io/docker/image-size/0x1917/opengym)](https://hub.docker.com/r/0x1917/opengym)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64-blue?logo=linux&logoColor=white)](#requirements)
[![License](https://img.shields.io/github/license/0x1917/opengym)](https://github.com/0x1917/opengym/blob/master/LICENSE)

Single-container build of [OpenGym](https://github.com/DuarteSantos8/openGym):
Node API, nginx-served SPA, exercise media, and the optional MCP server in one
image, supervised by s6-overlay. Built for Unraid - install it with the OpenGym template from
[`0x1917/unraid-templates`](https://github.com/0x1917/unraid-templates).

## How the image is built

Nothing is compiled here. The Dockerfile starts from upstream's published images
(`ghcr.io/duartesantos8/opengym-api`, `opengym-web` and `opengym-mcp`), all at the
release named by `ARG UPSTREAM_VERSION`, and adds the supervision layer:
s6-overlay, uid-99 ownership, an unprivileged nginx master, and the boot-time
config rendering they need.

- A build is layer copies, one `apk add` (nginx, gettext-envsubst, tzdata) and the 
  sha256-verified s6-overlay tarballs.
- The upstream **web** image supplies the built SPA, the nginx site template,
  the `BASE_PATH` guard, the exercise media, and the CSP string.
- The upstream **MCP** image supplies the MCP over HTTPS server: its whole
  `/app` tree, copied to `/opt/opengym-mcp`, because the server imports shared
  modules from upstream's `api/` and `frontend/` by relative path.

### Build

The build context is this directory, so run it from the repository root.

```sh
docker build -t opengym:latest .
```

The image carries three provenance labels: `image.revision` (default=`dev`), 
`image.created` (default=`unknown`), and `image.base.digest` (default=`unknown`). 
The CI chain fills them from the commit and from the pinned base image.

#### Test a different upstream release without editing the file

```sh
docker build -t opengym:beta                                             \
  --build-arg OPENGYM_API_IMAGE=ghcr.io/duartesantos8/opengym-api:<ver>  \
  --build-arg OPENGYM_WEB_IMAGE=ghcr.io/duartesantos8/opengym-web:<ver>  \
  .
```

`<ver>` is an upstream release tag. Override **both** refs together: nothing 
in the Dockerfile cross-checks that the API and web tags come from the same release.
For a real update, edit the ARG instead (see Version management).

## Run

Prebuilt on Docker Hub: `docker pull 0x1917/opengym:latest`.

```sh
docker run -d                         \
  --name opengym                      \
  --restart unless-stopped            \
  -p 8310:80                          \
  -e ORIGIN=http://{IP}}:8310         \
  -v /mnt/user/appdata/opengym:/data  \
  0x1917/opengym:latest
```

Only port 80 is published. nginx fronts everything and proxies `/api` to the
loopback API, so the app stays on a single origin (a passkey requirement).

## Test

`scripts/smoke-test.sh <image>` is the gate CI runs. It boots the image on a free 
loopback port with a throwaway data dir and fails on the first broken expectation.
Needs `docker`, `curl`, `jq`, and `openssl`.

```sh
bash scripts/smoke-test.sh opengym:test
```

| Check                                              | Proves                                                          |
| -------------------------------------------------- | --------------------------------------------------------------- |
| boots, `/api/health` ok through nginx              | both supervised services came up, proxy chain intact            |
| SPA responds with a CSP header                     | the web tier serves with upstream's policy                      |
| exercise media served                              | the media copy from the web image landed at the served path     |
| npm absent from the image                          | the runtime-free upstream target shipped, no npm tree           |
| API not running as root                            | the uid-99 drop in `s6-api-run`                                 |
| license texts ship (AGPL + notice)                 | a dropped `COPY` builds and boots fine, so nothing else notices |
| `PASSWORD_LOGIN` reaches the config endpoint       | image env surface and template rows agree                       |
| password signup + session cookie                   | the API can create a user and issue a session through the proxy |
| first user is administrator                        | `FIRST_USER_ADMIN` behaves as the template claims               |
| state written through the proxy                    | a real write path, not only a read                              |
| `/data` owned `99:100`                             | the Unraid appdata ownership contract                           |
| `docker stop` exits 0                              | no orphaned nginx, no swallowed signal                          |
| replacement keeps session + data, `BASE_PATH=/gym` | an upgrade does not lose data, and subpath mode serves          |
| `/mcp` answers JSON 503 while MCP is off           | MCP stays opt-in, and clients get upstream's readable error     |
| healthcheck passes with MCP off                    | the idle mcp service never marks the container unhealthy        |
| mcp runs as its own account, cannot read `/data`   | the AI-facing service is kept away from the data, like nginx    |
| healthcheck follows the mcp server while MCP is on | a dead MCP server shows as unhealthy, a restarted one recovers  |
| `/mcp` OAuth challenge and discovery document      | Claude and ChatGPT connectors can start their sign-in           |
| scoped token: tools follow scopes, reads the api   | the full MCP path, from nginx through the mcp server to the api |
| a revoked token is refused at once                 | revocation reaches the MCP path without a restart               |
| invalid `BASE_PATH` refused at boot                | misconfiguration fails loudly instead of 404-ing                |

Deliberate gaps: passkey ceremonies (needs a real browser), Coach provider jobs,
TLS and reverse-proxy behaviour, and anything requiring real user data.

## CI

Two workflows, chained. Neither one can do the other's job.

| Workflow                   | Trigger                                          | Does                                                                    |
| -------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------- |
| `build.yml`                | push to `master`, PR, dispatch on the same paths | build, smoke test, and package the image as an artifact                 |
| `publish.yml`              | `workflow_run` after `build` completes           | download that run's artifact, verify it, push, tag, and cut the release |

Build never touches the registry. Publish never builds. The image crosses the
boundary as `docker save | zstd` plus a `meta.json` holding the image ID, the
version, and the publish decision.

| Event                                                         | Build | Publish |
| ------------------------------------------------------------- | ----- | ------- |
| push to `master` changing a build input since the last tag    | yes   | yes     |
| push to `master` changing nothing that reaches the image      | yes   | no      |
| pull request                                                  | yes   | no      |
| dispatch, `force_publish=false`                               | yes   | no      |
| dispatch, `force_publish=true`                                | yes   | yes     |

Publish runs only from `master`, only after a green build, and only when the
bundle says so. It checks out `master`, never the build run's commit, so the job
holding a write token runs only code already on `master`; the build run's commit is
the target of the source tag. Before pushing it repeats the build-input comparison
against the highest tag: build decides before an earlier publish has tagged, so two
quick pushes would otherwise both publish, the second as a `<ver>-<n>` rebuild of an
unchanged image. Publish runs are serialised, so that tag is current. It then:

1. Loads the tarball and asserts the image ID matches the one in `meta.json`
2. Runs `smoke-test.sh` again on the loaded bytes, because they travelled
   through an artifact store
3. Tags and pushes its registry tag (`<ver>` on the first publish, `<ver>-<n>`
   on a rebuild), plus `latest` when it carries the highest tag of the series,
   and verifies the pushed digests match
4. Creates the git source tag (`v<ver>`, or `-<n>` for a rebuild)
5. Creates the GitHub release, whose notes quote upstream's changelog section
   for that version word for word, and state the digest that shipped

A rebuild moves that release onto the numbered source tag rather than opening a
second release, so each version keeps one release whose tag names the bytes it
was last cut from. On the registry the rebuild is a new tag of its own
(`<ver>-<n>`): the first-published `<ver>` tag is never overwritten, and
`latest` moves only when the run carries the highest tag of the series, so a
re-publish of an older build refreshes just its own tag.

Two manual paths:

```sh
# build now, publish on completion (one click, then the chain does the rest)
gh workflow run build.yml --ref master -f force_publish=true

# republish an existing build, no rebuild (run id from the Actions URL)
gh workflow run publish.yml -f build_run_id=1234567890
```

The first marks the bundle as publishable and lets the chained workflow push it. A
dispatch without the input builds and smokes only. The second re-pushes the
bytes from that build run - it no-ops the source tag if the commit already has one
and re-pushes that commit's own registry tag, leaving every other tag alone. It
still refuses if the bundle was never marked as publishable.

What matters:

- **The published image is the tested image.** The artifact carries the exact
  image ID the gate ran against and the publish side refuses to proceed if the
  ID it loads differs.
- **Publishing is gated on the image inputs.** Only the paths that reach the image
  count, listed in [`.github/build-inputs`](.github/build-inputs): `Dockerfile`,
  `.dockerignore`, `runtime/`, `LICENSE` and `NOTICE.md`. The baseline is the highest
  published tag. Lint fails if the Dockerfile copies from any other path, so a new
  `COPY` source cannot change the image without publishing it.
- `timeout-minutes: 25` on the build, 20 on the publish.
- Serialized runs: `build-<ref>` for builds, `publish` for publishes,
  both with `cancel-in-progress: false`, so `:latest` and the numbered tag series
  never race.
- Dependabot opens weekly PRs for new action majors; patch and minor updates
  arrive through the major tags.

### Upstream releases

`scout` (`.github/workflows/scout.yml`) runs daily, on demand, and on pull
requests that touch the checker script or that workflow (check only, since a PR
has no write token). It compares two upstreams: OpenGym's images (`ARG UPSTREAM_VERSION`)
and s6-overlay (`ARG S6_OVERLAY_VERSION` plus four tarball checksums, re-read from the release's
own `.sha256` assets). The logic is `scripts/upstream-check.sh` (`check` and `apply`), which needs
only `curl` and `jq` and therefore also runs by hand. When something newer
exists it updates the ARGs, re-vendors `NOTICE.md`, builds, runs the smoke gate,
and only then opens a PR. Nothing publishes until that PR is merged.

- The PR is opened with a token from the `0x1917-bot` GitHub App when the repository
  has the `APP_ID` variable and the `APP_PRIVATE_KEY` secret, so `build` and `lint` run on
  it as the ruleset requires. Without the app it falls back to `GITHUB_TOKEN`, whose PRs
  start no other workflow runs; the build and smoke evidence is then the check run's log
  and the PR body.
- The branch name carries the date and both versions, so a re-run on the same day
  is a no-op while the PR is open. Close it unmerged and the next run proposes it
  again.

## Version management

`ARG UPSTREAM_VERSION` is the single source of truth. Both image refs derive from
it, so one edit cannot leave the pair mismatched.

`<ver>` below is an upstream release tag such as `1.0.1`. The published version is whatever the ARG says.

| Thing                                 | Form                                            | Example                |
| ------------------------------------- | ----------------------------------------------- | ---------------------- |
| upstream image tag                    | bare semver (upstream's own convention)         | `opengym-api:<ver>`    |
| this repo's Hub tag                   | bare semver first publish, `<ver>-<n>` rebuilds | `0x1917/opengym:<ver>` |
| OCI `image.version` label             | bare semver                                     | `<ver>`                |
| git tag (CI)                          | `v` + version; rebuilds get `-<n>`              | `v<ver>`               |

### Update checklist

The daily check does steps 1 to 4 and opens a PR, merging that PR is step 5. By hand:

1. Read upstream's release notes and confirm both image tags exist
2. Edit `ARG UPSTREAM_VERSION`.
3. Re-vendor `NOTICE.md` from the new tag; re-copy `LICENSE` if upstream changed it.
4. Build and run `smoke-test.sh` locally.
5. Commit and push to `master`; CI publishes `<ver>` + `latest`.

### Caveats

- **Version tags are immutable after the first publish.** The first publish of
  a release claims `<ver>` on both registries; every rebuild pushes its own
  `<ver>-<n>` tag. `latest` moves only when the run carries the highest tag of
  the whole series, so re-publishing an older build never drags it backwards.
  The git side records the same series
  (`v<ver>`, then `v<ver>-<n>`), and the release for that core version is
  retargeted to the newest source tag. Inside the registry, `image.created` and
  `image.revision` still separate two builds of one release.
- **Rollback** is a previous release tag (`0x1917/opengym:<ver>`, or a rebuild's
  `<ver>-<n>`) or a local image. Old tags are not deleted.
- **The media is not AGPL.** Upstream's notice permits a non-commercial OpenGym
  fork to carry the unmodified 180px media with the notice, which is why
  `NOTICE.md` ships inside the image and is re-vendored on every release update.

## Environment

Everything below is read from the container environment at boot; changing a
value means recreating the container. Flags take `true`/`false` (`1`/`0`,
`on`/`off` and `yes`/`no` work too). Upstream's
[`.env.example`](https://github.com/DuarteSantos8/openGym/blob/main/.env.example)
and [`docs/SELF_HOSTING.md`](https://github.com/DuarteSantos8/openGym/blob/main/docs/SELF_HOSTING.md)
are the full reference; this is the subset that applies to this image.

Defaults are what this image (or, marked †, the Unraid template) sets. A plain
`docker run` without a † variable gets upstream's default, given in the text.

### Address and sign-in

| Variable           | Default      | Meaning                                                                                                                                       |
| ------------------ | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ORIGIN`           | *(required)* | Exact address users type, scheme and port included. A mismatch refuses sign-in with `origin-mismatch`.                                        |
| `RP_ID`            | *(empty)*    | Hostname from `ORIGIN`, no scheme or port. Required for passkeys; changing it invalidates them. Passkeys need HTTPS.                          |
| `RP_NAME`          | `openGym`    | Name shown in the browser's passkey prompt.                                                                                                   |
| `PASSWORD_LOGIN`   | `true` †     | Name and password sign-in next to passkeys, for plain-HTTP LAN installs and recovery (upstream default: off).                                 |
| `FIRST_USER_ADMIN` | `true` †     | First profile on an empty instance becomes admin; also applies to the first OIDC sign-in (upstream default: off).                             |
| `ADMIN_UIDS`       | *(empty)*    | Comma-separated account IDs (Settings > Account > Account ID) with admin dashboard access.                                                    |
| `ALLOW_GUEST`      | `true`       | `false` removes "Continue without account".                                                                                                   |
| `INVITE_ONLY`      | `false`      | Gate sign-ups behind admin-generated invite codes. Create an admin profile first.                                                             |
| `SESSION_DAYS`     | `90`         | Sign-in lifetime in days. Affects new sign-ins only.                                                                                          |
| `SESSION_SAMESITE` | *(lax)*      | `strict` never sends the session cookie on cross-site requests.                                                                               |
| `DEFAULT_LANG`     | *(empty)*    | Starting language for the sign-in screen and profiles that never chose one (`de`, `pt-BR`, ...; codes as in Settings > Language).             |

### Single sign-on (OIDC)

Off until `OIDC_ISSUER` and `OIDC_CLIENT_ID` are both set. Register
`<ORIGIN>/api/oidc/callback` as the redirect URI at the provider (Authentik,
Authelia, Keycloak, Pocket ID, voidAuth, ...).

| Variable              | Default                | Meaning                                                                                                              |
| --------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `OIDC_ISSUER`         | *(empty)*              | Issuer URL, e.g. `https://auth.example.com/application/o/opengym/`.                                                  |
| `OIDC_CLIENT_ID`      | *(empty)*              | Client ID registered at the provider.                                                                                |
| `OIDC_CLIENT_SECRET`  | *(empty)*              | Client secret. Leave empty for a public client (PKCE only).                                                          |
| `OIDC_LABEL`          | *(empty)*              | Button text: "Sign in with *label*".                                                                                 |
| `OIDC_SCOPES`         | `openid profile email` | Scopes requested.                                                                                                    |
| `OIDC_ALLOWED_GROUPS` | *(empty)*              | Comma-separated groups allowed in. **Empty lets anyone the provider authenticates create a profile.**                |
| `OIDC_GROUPS_CLAIM`   | `groups`               | Claim holding the groups, or a path such as `realm_access.roles`.                                                    |
| `OIDC_ROLE_MAP`       | *(empty)*              | Groups to roles, e.g. `access=opengym, admin=opengym-admins`.                                                        |
| `OIDC_ONLY`           | `false`                | The provider becomes the only way in (admins keep their passkeys).                                                   |
| `OIDC_EMAIL_LINKING`  | `false`                | Link a first provider sign-in to an existing profile by verified e-mail.                                             |
| `OIDC_LOGOUT`         | `false`                | Signing out also ends the provider session.                                                                          |
| `OIDC_TOKEN_AUTH`     | *(basic)*              | `post` sends the client secret in the body (`client_secret_post`).                                                   |
| `OIDC_REDIRECT_URI`   | *(derived)*            | Only needed for a `BASE_PATH` install.                                                                               |

### Proxy and networking

| Variable           | Default     | Meaning                                                                                                                         |
| ------------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `TRUST_PROXY`      | `true` †    | Honor `X-Forwarded-For`/`X-Real-IP`. Safe here: nginx in this image overwrites both with the real peer (upstream default: off). |
| `CF_CONNECTING_IP` | *(empty)*   | `$http_cf_connecting_ip`, only when Cloudflare is really in front; empty drops the header so a client cannot forge it.          |
| `BASE_PATH`        | *(empty)*   | Subpath deployments (`/gym`, no trailing slash) where the proxy passes the prefix through. Empty means site root.               |
| `NGINX_PORT`       | `80`        | nginx's listen port inside the container. Change the published port instead unless you have a reason.                           |
| `TZ`               | `Etc/UTC`   | Container timezone for logs and the audit log. Reminders fire in each user's own zone regardless.                               |

### Media uploads

Photos, GIFs, videos and sounds attached to custom exercises, stored under
`/data/uploads`. Sizes are MB (1024×1024 bytes).

| Variable                 | Default   | Meaning                                                                                                                             |
| ------------------------ | --------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `MEDIA_UPLOAD_MAX`       | `112m`    | nginx's body limit (`client_max_body_size`). Keep it above `MEDIA_VIDEO_MAX_MB`, and give any reverse proxy in front the same room. |
| `MEDIA_UPLOADS`          | `true`    | `false` turns uploads off; the app then offers a link field only.                                                                   |
| `MEDIA_QUOTA_MB`         | `200`     | Space per profile (`0` = no cap). On open sign-up, the worst case is this times the number of profiles.                             |
| `MEDIA_VIDEO_MAX_MB`     | `100`     | Per-video cap. Larger clips are shrunk on the device first where the browser can.                                                   |
| `MEDIA_VIDEO_MAX_SEC`    | `60`      | Per-video length cap.                                                                                                               |
| `MEDIA_IMAGE_MAX_MB`     | `2`       | Per-photo cap (photos are shrunk to 1600 px on the device).                                                                         |
| `MEDIA_GIF_MAX_MB`       | `8`       | Per-GIF cap.                                                                                                                        |
| `MEDIA_AUDIO_MAX_MB`     | `2`       | Per rest-timer sound cap.                                                                                                           |
| `MEDIA_MIN_FREE_MB`      | `512`     | Uploads are refused below this much free disk, so a full disk cannot take the instance down.                                        |

### Optional features

All off unless noted.

| Variable                 | Default   | Meaning                                                                                                                                 |
| ------------------------ | --------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `TRAINERS`               | `false`   | Gyms, gym leads and trainers; members choose per category what a trainer may see or change. See upstream `docs/TRAINERS.md`.            |
| `TRAINERS_LEAD_ACCESS`   | `row`     | What a gym lead gets: `row`, `mirror` or `none`.                                                                                        |
| `LIBRARY`                | `false`   | Community library: share exercises, plans, sounds and more with everyone on this server, moderated from the admin dashboard.            |
| `SHARE_REVIEW`           | `false`   | An admin approves every new library item first.                                                                                         |
| `SHARE_PERSONAL_MEDIA`   | `false`   | Allow workout and progress photos in the library (always reviewed).                                                                     |
| `ADMIN_DATA_VIEW`        | `false`   | Admin dashboard shows people's workouts and weigh-ins again (counts only since 1.4.5), with every look logged.                          |
| `API_TOKENS`             | `true`    | Per-profile scoped API tokens (Settings > API tokens). `false` removes the feature.                                                     |
| `INTEGRATIONS`           | *(empty)* | Comma-separated: `webhook` (signed JSON to Home Assistant, n8n, ntfy, ...), `strava` (needs `STRAVA_CLIENT_ID`/`STRAVA_CLIENT_SECRET`). |
| `INTEGRATIONS_ALLOW_LAN` | `false`   | Let webhooks reach private addresses. Every signed-in user can then make the server call into your network.                             |
| `NUTRITION_SOURCE`       | *(empty)* | `opennutrition`, with `NUTRITION_URL`, fills the trainer "nutrition" category.                                                          |
| `VAPID_SUBJECT`          | `ORIGIN`  | Contact for push services, e.g. `mailto:you@example.com`. Push works without it.                                                        |

### Activity log and AI Coach

| Variable               | Default  | Meaning                                                                                                                  |
| ---------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------ |
| `AUDIT_LOG`            | `true`   | Admin-dashboard activity log in `/data/audit.log`.                                                                       |
| `AUDIT_IP`             | `off`    | Record addresses: `off`, `net` (network only) or `full`.                                                                 |
| `AUDIT_MAX`            | `5000`   | Events kept (`0` = no limit).                                                                                            |
| `AUDIT_DAYS`           | `90`     | Days kept (`0` = no limit).                                                                                              |
| `COACH_DISABLED`       | `false`  | Kill switch over the admin's AI Coach toggle. The Coach itself is set up in the admin dashboard, not here.               |
| `COACH_JOB_TIMEOUT_MS` | `600000` | Longer Coach jobs, e.g. a local model on a CPU. Never below one minute.                                                  |

### MCP over HTTPS

Lets AI assistants (Claude, ChatGPT, Gemini, or a local client such as Claude
Code) read and change openGym data at `<ORIGIN>/mcp`, each with a scoped API
token. Upstream runs it as a separate container; this image bundles it as a
third supervised service, running as its own `mcp` account with no access to
`/data`. It only reaches data through the API, with the caller's token. See
upstream's [`docs/MCP_REMOTE.md`](https://github.com/DuarteSantos8/openGym/blob/main/docs/MCP_REMOTE.md).

| Variable              | Default     | Meaning                                                                                                                         |
| --------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `MCP`                 | `true`      | Starts the bundled MCP server, shows its address in Settings, and makes OpenGym the OAuth sign-in for assistant connectors.     |
| `MCP_ALLOWED_ORIGINS` | `ORIGIN`    | Browser origins allowed to call `/mcp`, comma-separated. Non-browser clients send none.                                         |
| `MCP_PORT`            | `3100`      | Port the MCP server listens on inside the container.                                                                            |
| `MCP_BACKEND`         | `127.0.0.1` | Where nginx sends `/mcp`. Change it only to use an external MCP container instead of the bundled one.                           |

With `MCP` off, `/mcp` answers a JSON 503. Connectors such as Claude's and
ChatGPT's call from the provider's servers, so they need `ORIGIN` to be a
public HTTPS address with openGym at the root of its host (or a proxy that
passes `BASE_PATH` through). A LAN-only instance still works with a token in
the `Authorization` header from a local client.

### Not applicable to this image

- `COMPOSE_PROFILES=mcp`: the MCP server is bundled, so `MCP=true` is all it
  takes.
- `COACH_EFFORT`, `API_TARGET=coach`: this image is upstream's `default` API
  target, without the Claude Agent SDK or Codex runtime. API-key Coach
  providers work; the in-container ones do not.
- `DATA_DIR`, `PORT`, `BACKEND`: wiring between nginx and the API inside this
  container. Map `/data` instead of moving it.

## First boot

1. Map a host path to `/data` (chowned to uid 99 at boot).
2. Set `ORIGIN`, plus `RP_ID` for passkeys, to the address people will use.
3. Open the WebUI and create a profile.
4. Healthy once nginx answers and `/api/health` comes back through the proxy.

## Design notes

- **One image, up to three supervised processes.** Upstream's compose runs
  `api`, `web` and the optional `mcp` as separate containers; merging them
  removes container-to-container DNS from the request path and leaves one
  artifact to build, back up and roll back. The mcp service idles unless
  `MCP=true`.
- **s6-overlay, sha256-verified at build.** pid-1 signal handling, privilege
  dropping, ordered one-shot init.
- **Crash policy.** A crashed service restarts after 1s; five deaths in 60s end
  the CMD so Docker's restart policy owns the failure. A failed stage 2 stops the
  boot (`S6_BEHAVIOUR_IF_STAGE2_FAILS=2`).
- **Every service unprivileged.** API as uid 99 (group `users`, Unraid's appdata
  convention), nginx as the distro `nginx` account, the MCP server as `mcp`.
  Only the API can read `/data`.
- **License texts ship in the image** at `/usr/share/opengym/`: the AGPL text
  (`LICENSE`) and upstream's third-party notice (`NOTICE.md`). The image
  redistributes upstream's build and the separately licensed exercise media, so
  the notice is a condition of carrying that media, not a formality.
