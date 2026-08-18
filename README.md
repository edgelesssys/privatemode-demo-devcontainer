# Privatemode Demo Dev Container

A demo development environment with the [Privatemode](https://www.privatemode.ai) proxy as a sidecar. It shows how to run AI coding agents with end-to-end encryption and is meant as a starting point to adapt, not as a hardened production setup. Open it in VS Code and you get:

- The **Privatemode proxy** running next to your dev container. It verifies the Privatemode backend via remote attestation and end-to-end encrypts all prompts and responses.
- An **OpenAI-compatible endpoint** at `http://privatemode-proxy:8080/v1`, preconfigured via `OPENAI_BASE_URL`.
- **Claude Code, opencode, and pi** installed and preconfigured to use Privatemode as their backend. No accounts or logins required.
- **Restricted network egress.** By default the container cannot reach the public internet at all. The agents work anyway because all AI traffic goes to the local proxy.

## Prerequisites

- Docker
- VS Code with the **Dev Containers** extension
- A Privatemode API key ([portal.privatemode.ai](https://portal.privatemode.ai))

## Setup

1. Put your API key in `.devcontainer/api-key` (the file's only content, no quotes, see `api-key.example`). It is gitignored and mounted into the proxy container as a secret.
2. Open the folder in VS Code.
3. Click **Reopen in Container** when prompted (or `F1` → *Dev Containers: Reopen in Container*).

The first start pulls two images and installs dependencies. Subsequent starts take seconds.

## Try it

In the VS Code terminal (inside the container):

```bash
# Verify the proxy is up and attestation succeeded
curl http://privatemode-proxy:8080/v1/models

# Start a coding agent (all backed by Privatemode, default model: kimi-latest)
claude
opencode
pi
```

All agents default to `kimi-latest`. To use `gpt-oss-120b` instead, run `/model gpt-oss-120b` in opencode and pi, or `claude --model gpt-oss-120b`.

## Network egress restriction

On every start, a firewall inside the container blocks all outbound internet traffic (default deny). The coding agents are unaffected because they only talk to the Privatemode proxy on the local container network. This limits what an agent, or any code it runs, can exfiltrate.

To let the container reach additional services directly, for example GitHub for `git push` or the npm registry for installing packages, add the domains to `.devcontainer/allowed-domains.txt` (commented examples included) and apply with:

```bash
sudo bash .devcontainer/init-firewall.sh
```

The firewall is adapted from the [Claude Code reference dev container](https://code.claude.com/docs/en/devcontainer#restrict-network-egress).

## How it works

Your code and prompts never leave this environment in plaintext. The proxy encrypts every request client-side and only talks to a backend whose integrity it has verified through remote attestation. Decryption happens inside hardware-isolated confidential VMs whose memory stays encrypted, inaccessible to the infrastructure provider and to Edgeless Systems.

## Notes

- The proxy container should be pinned by digest in production (see comment in `docker-compose.yml`).
- Proxy logs: `docker logs -f <project>-privatemode-proxy-1` (on the host).
- If the proxy fails with an "unmarshaling" error after a backend update, pull the latest proxy image and rebuild.
