# Security policy

This repository packages [OpenGym](https://github.com/DuarteSantos8/openGym) into one
container image: Node API, nginx-served SPA, and exercise media, supervised by s6-overlay.
It is a build and packaging repository, not a fork of the application. That split decides
where a report belongs, so read the first section before opening anything.

## Where to report

| Subject                                                   | Report it at                                                                                 |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| This image: `Dockerfile`, `runtime/`, nginx, workflows    | [Private report here](https://github.com/0x1917/opengym/security/advisories/new)             |
| Upstream app: the API, the SPA, auth, the Coach           | [Upstream private report](https://github.com/DuarteSantos8/openGym/security/advisories/new)  |

The upstream project has its own policy, with its own supported-version rules:
[their SECURITY.md](https://github.com/DuarteSantos8/openGym/blob/main/SECURITY.md).

If you are unsure which side a bug sits on, report it here and it will be forwarded. A report
sent to the wrong place is fine, a report never sent is not.

Private vulnerability reporting is enabled on this repository, so the advisory thread is
visible only to you and the maintainer and becomes the place the fix is discussed and
published.

Please do not open a public issue with a working exploit that other people's instances are
vulnerable to and do not paste one into the upstream Discord, which is a public room.
Everything else is fine as a normal issue: a crash you can only trigger on your own box, a
scanner warning, a misconfiguration in the example commands.

## Supported versions

Only the **newest published image tag**. Image tags are the upstream release number
(`1.4.4`, `latest`); a fix ships as a new tag, and older tags are never patched. There is no
LTS, no maintenance branch, and no backport to a version you happen to be running.

```sh
docker pull 0x1917/opengym:latest
```

Pinning the digest rather than the tag protects you from a retag, not from a vulnerability:

```sh
docker image inspect --format '{{index .RepoDigests 0}}' 0x1917/opengym:1.4.4
```

## What the image does and does not protect

Worth knowing before you report, because half of what looks like a finding is a documented
trade-off:

- The container starts as root because s6-overlay is PID 1. Both long-running services drop
  privileges before exec: the API runs as `opengym` (uid 99), nginx as `nginx`.
- Only port 80 is published. The API is reachable through nginx on `127.0.0.1` inside the
  container, never from the host network directly.
- Application state lives in `/data`, owned by uid 99. A bind mount that hands that path to
  a different uid is a permissions bug on the host, not a container escape.
- Base images are pulled by upstream version tag, not by digest. The digest actually used is
  recorded in the image as `org.opencontainers.image.base.digest`, so you can check what went
  into a given build.
- The image ships no secrets. Configuration arrives as environment variables at run time.

Dependency alerts and base-image CVEs with no reachable exploit path are Dependabot's job
here; a report is more useful when it says how an attacker reaches the code.

## What to include

- The image tag and, if you have it, the digest.
- How you run it: `docker run`, a compose file, Unraid, or behind a reverse proxy, and what
  sits in front of it.
- Steps to reproduce, with the request or command that triggers it.
- What an attacker gets: data, another user's session, denial of service, nothing.
