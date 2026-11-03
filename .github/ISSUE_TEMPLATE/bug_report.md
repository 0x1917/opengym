---
name: Bug report
about: Report a problem with the image or its supervision layer
title: ""
labels: bug
assignees: ""
---

**What fails**
<!-- One sentence: what does not work, and what you expected instead. -->

**How the container runs**

- Image and tag: <!-- 0x1917/opengym:<version> or 0x1917/opengym:latest -->
- Deployed with: <!-- Unraid template, docker run, or docker compose -->
- Unraid version, or host distribution and version:
- CPU architecture: <!-- this image is built for x86_64 only -->
- Data path: <!-- new install or an existing /data directory -->

**Settings in use**
<!-- Fill in the ones you changed. Delete the rest. -->

- ORIGIN:
- BASE_PATH:
- PASSWORD_LOGIN:
- TRUST_PROXY:
- Reverse proxy in front: <!-- yes/no, and which one -->

**Steps to reproduce**

1.
2.
3.

**Logs**
<!-- docker logs <container>, or Docker tab > Logs. Keep the failing start. -->

```text

```

**Does it fail on another tag?**
<!-- If you run :latest, try the same steps on the version tag. That separates a
packaging regression from an upstream one. -->

**Additional context**
<!-- Anything else that helps.

Two kinds of report belong in another tracker, not this one:
- the Unraid template, its fields, its defaults, or the artwork:
  https://github.com/0x1917/unraid-templates/issues
- a bug inside the app itself:
  https://github.com/DuarteSantos8/openGym/issues -->
