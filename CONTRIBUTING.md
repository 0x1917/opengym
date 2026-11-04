# Contributing

This repository packages [OpenGym](https://github.com/DuarteSantos8/openGym) into a single
container image and publishes it. It holds no application code — the `Dockerfile`, the
`runtime/` supervision scripts, and the CI workflows are the whole of it.

## Where a report or a change belongs

| Subject                                                                                        | Goes to                                                                                                |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| The image: build, `runtime/` scripts, s6 services, nginx config, CI, how the container behaves | Here — [issues](https://github.com/0x1917/opengym/issues) and pull requests                            |
| The Unraid template: fields, defaults, artwork, the Docker tab entry                           | [`0x1917/unraid-templates`](https://github.com/0x1917/unraid-templates/issues)                         |
| OpenGym itself: workouts, accounts, passkeys, the Coach, the API                               | Upstream — [DuarteSantos8/openGym](https://github.com/DuarteSantos8/openGym/issues)                    |
| Configuration and deployment of the app                                                        | [Upstream self-hosting guide](https://github.com/DuarteSantos8/openGym/blob/main/docs/SELF_HOSTING.md) |
| A security vulnerability                                                                       | [SECURITY.md](SECURITY.md), privately — not a public issue                                             |

If you are unsure, open it here and it will be moved rather than closed.

## Run the checks before you open a pull request

CI runs all of these, and a pull request that fails them will not be reviewed until it passes:

```sh
bash scripts/test-runtime.sh
```

The suite covers the crash policy, the nginx run script's signal handling, image ref
resolution, tag naming, and the Dockerfile invariants. It needs no Docker and no root, and
runs in about a second.

```sh
shellcheck -x -S warning scripts/*.sh runtime/*.sh runtime/s6-api-run runtime/s6-nginx-run
actionlint .github/workflows/*.yml
```

CI installs both; install them locally to run this before pushing.

```sh
docker build -t opengym:test .
bash scripts/smoke-test.sh opengym:test
```

The smoke test boots the image and walks the paths Unraid users depend on. It needs `docker`,
`curl`, `jq`, and `openssl`, and takes about 40 seconds. It is the only check here that needs
a working Docker daemon, and it is the one that catches a change which builds cleanly and then
fails to start. See [Test](README.md#test) for what each expectation proves.

## The invariants the tests enforce

A failing assertion here is usually telling you something deliberate, not obstructing you.
Each exists because the alternative was a bug:

- **No `USER` instruction.** s6-overlay must be PID 1 as root; each service then drops
  privileges with `s6-setuidgid` in its own run script. A `USER` line either duplicates that
  or breaks the init.
- **`EXPOSE 80` and nothing else.** The API is reachable only through nginx on loopback
  inside the container. Publishing a second port exposes the API to your host network.
- **Every context `COPY` source exists and is not in `.dockerignore`.** A missing source fails
  late in the build; an ignored one fails with a confusing "not found" after a cache hit.
- **Every `${VAR}` expanded in the `Dockerfile` is declared** with `ARG` or `ENV`.
- **Git tags are `v<version>`**, with `v<version>-<n>` for a rebuild. The `opengym-` prefix is
  gone: this repo builds one image, so a prefix buys nothing.

## Changing the image

- Keep the privilege model intact: a service that needs to write state drops to `opengym`
  (uid 99), and nothing runs as root except PID 1.
- Comments explain *why* a thing is done, especially where the obvious alternative fails.
  Those comments are the reason this repository is readable at all; a change that removes one
  needs to replace it with the reason.
- If you change behaviour a user can see, update [README.md](README.md) — the Test table, the
  environment table, or the design notes, whichever is now wrong. If the change affects what
  the image needs at run time, the Unraid template needs a matching change, in the templates
  repository, as a separate pull request.

## Versions, tags, and releases

Do not bump `UPSTREAM_VERSION`, create a git tag, or edit the publish workflow's release logic
in a pull request; the maintainer cuts releases. The scheme, for reference: image tags are
bare versions (`1.4.4`, `latest`), the git source tag is `v1.4.4`, and republishing the same
upstream release appends a rebuild number (`v1.4.4-1`). Only the newest image tag is supported.

## Pull request shape

- One concern per pull request. A formatting sweep mixed with a fix will be asked to split.
- Say why in the description, not just what. The diff already says what.
- Do not reorder `Dockerfile` layers for tidiness; the order is the cache.
- Do not reformat files you did not otherwise touch.

## Licensing

This repository is [AGPL-3.0](LICENSE). There is no CLA and no contributor agreement — by
opening a pull request you agree your contribution is licensed under the same terms as the
project. The upstream application carries its own license in
[`DuarteSantos8/openGym`](https://github.com/DuarteSantos8/openGym).
