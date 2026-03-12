Agent Browser — sandbox installation

This folder contains a sandbox template to run an agent that automates web browsing (headless). Use this only in an isolated environment and with explicit whitelists.

Files:
- Dockerfile — headless browser + runtime
- docker-compose.yml — example to run isolated container
- run_test.sh — sample script to test agent actions (no secrets)

Security:
- Always run with minimal privileges and network egress filtering.
- Configure a domain whitelist and do not pass secrets into the container.
