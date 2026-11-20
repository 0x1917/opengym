#!/bin/sh
# Docker HEALTHCHECK. Healthy only if the SPA server answers AND the /api proxy
# chain reaches node, and, while MCP is on, the bundled MCP server answers too.
#
# The MCP server is probed directly on loopback, not through nginx: the site
# template proxies only the exact /mcp path, and its health route is
# /mcp/health. With MCP off the service idles on purpose (runtime/s6-mcp-run), so it
# is not probed and cannot make the container unhealthy.
wget --spider -q "http://127.0.0.1:${NGINX_PORT}/api/health" || exit 1

case "$(printf '%s' "${MCP:-}" | tr 'A-Z' 'a-z')" in
  1|true|yes|on)
    wget -qO- "http://127.0.0.1:${MCP_PORT}/mcp/health" 2>/dev/null | grep -q '"ok":true' || exit 1
    ;;
esac
exit 0
