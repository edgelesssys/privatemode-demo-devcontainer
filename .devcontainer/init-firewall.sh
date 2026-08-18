#!/usr/bin/env bash
# Default-deny egress firewall for the app container.
#
# All AI traffic goes to the Privatemode proxy sidecar on the local
# compose network, so the container needs no public internet access.
# To reach additional services directly (e.g. github.com), add domains
# to allowed-domains.txt and re-run this script (or restart).
#
# Adapted from the Claude Code reference dev container:
# https://github.com/anthropics/claude-code/tree/main/.devcontainer
#
# Runs as root via postStartCommand (requires NET_ADMIN and NET_RAW,
# granted in docker-compose.yml).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST="${SCRIPT_DIR}/allowed-domains.txt"

# Start from a clean slate
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F
iptables -X
ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains hash:net

# Loopback (also covers Docker's embedded DNS resolver at 127.0.0.11)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# DNS lookups and responses to established connections
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Local container networks (this is where the Privatemode proxy lives)
for subnet in $(ip -4 -o addr show scope global | awk '{print $4}'); do
  iptables -A OUTPUT -d "${subnet}" -j ACCEPT
  iptables -A INPUT -s "${subnet}" -j ACCEPT
done

# User-extendable allowlist: resolve each domain and permit its IPs.
# Note: domains behind fast-rotating CDN IPs may need a re-run later.
if [[ -f "${ALLOWLIST}" ]]; then
  while IFS= read -r line; do
    domain="${line%%#*}"
    domain="$(echo "${domain}" | tr -d '[:space:]')"
    [[ -z "${domain}" ]] && continue
    ips="$(dig +short A "${domain}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"
    if [[ -z "${ips}" ]]; then
      echo "WARNING: could not resolve ${domain}, skipping" >&2
      continue
    fi
    for ip in ${ips}; do
      ipset add allowed-domains "${ip}" -exist
    done
    echo "Allowed: ${domain} (${ips//$'\n'/, })"
  done < "${ALLOWLIST}"
fi
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Default deny for everything else
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# No IPv6 egress (rules above are IPv4-only, don't leave a v6 bypass)
if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -F 2>/dev/null || true
  ip6tables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
  ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
  ip6tables -P INPUT DROP 2>/dev/null || true
  ip6tables -P FORWARD DROP 2>/dev/null || true
  ip6tables -P OUTPUT DROP 2>/dev/null || true
fi

# Verify: the public internet must NOT be reachable
if curl -s -m 3 https://example.com >/dev/null 2>&1; then
  echo "ERROR: firewall verification failed, example.com is reachable" >&2
  exit 1
fi
echo "Egress firewall active: public internet blocked except allowed domains."
