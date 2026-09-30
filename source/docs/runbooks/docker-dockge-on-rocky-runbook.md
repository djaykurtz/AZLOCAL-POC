---
title: "Runbook: Docker + Dockge on a Rocky VM on Azure Local (with SSH-key access)"
domain: [containers]
layer: [application]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [docker, dockge, rocky-linux, guest-vm, compose]
updated: 2026-07-31
---

# Runbook: Docker + Dockge on a Rocky VM on Azure Local (with SSH-key access)

Audience: a human repeating this by hand. Builds on the custom-vm-image runbook (staging gallery images).
Result achieved 2026-07-30: Docker CE + Dockge running on Rocky Linux 10.2 on the cluster, reachable at
http://<vm-ip>:5001, and the VM is Arc-managed.

NOTE: every IP, hostname, pool range, resource group, and gallery-image name in this runbook is an
ENVIRONMENT-SPECIFIC EXAMPLE from our PoC. A fresh deployment will have its own values - substitute yours.
The procedure (sections 0-6) is generic; the "Result observed" section is a dated snapshot, not a spec.
Placeholders: <vm-ip> = the VM's private IP, <rg> = resource group, <vm> = VM name, <lnet> = logical network.

--------------------------------------------------------------------------------
## 0. Pick the right image (this matters)

Cloud images are tuned per-platform datasource. For a VM you will SSH into, use an Azure-tuned image so
first-boot provisioning (user + SSH key) works:
- Rocky: Rocky-10-Azure-Base (the *.vhdfixed.xz on download.rockylinux.org) - gallery image name rocky-azure.
- Ubuntu: the standard cloud image works too - gallery image name ubuntu-2404.
Any distro RUNS; only the automatic credential provisioning depends on the image being cloud-init-ready.

Stage it with the reusable script (handles .qcow2, .vhd, .vhdx, and .vhdfixed.xz):
    .\scripts\New-AzLocalGalleryImage.ps1 -Name rocky-azure -OsType Linux `
        -SourceUrl 'https://download.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-Azure-Base.latest.x86_64.vhdfixed.xz'

--------------------------------------------------------------------------------
## 1. SSH key - generate it CORRECTLY (the #1 gotcha)

    ssh-keygen -t ed25519 -f .\.creds\poc-vm-key -N '' -C poc-vm

CRITICAL: use  -N ''  (single-quote empty) for NO passphrase. Do NOT use  -N '""'  - in PowerShell that
sets the passphrase to the literal two characters "" , which then makes every non-interactive (BatchMode)
SSH fail with "Permission denied (publickey)" because the client cannot load the key.

Verify the key has NO passphrase (this must print the public key with NO prompt):
    ssh-keygen -y -f .\.creds\poc-vm-key

If it prompts for a passphrase, strip it while keeping the SAME keypair (so any already-injected public
keys stay valid):
    ssh-keygen -p -f .\.creds\poc-vm-key -P '<old>' -N ''

--------------------------------------------------------------------------------
## 2. Create the VM (SSH key + Arc agent), non-interactively

    .\scripts\New-AzLocalTestVm.ps1 -VmName rocky-docker-01 -ImageName rocky-azure `
        -SshKeyPath .\.creds\poc-vm-key.pub -EnableAgent

Why the script and not a raw az command:
- az stack-hci-vm create ALWAYS wants --admin-password (with no TTY it crashes "NoTTYException"), so the
  script generates a random break-glass password, stores it in Key Vault (kv-lab-secrets/poc-vm-admin),
  and passes --authentication-type all + the SSH key content + that password, with stdin closed.
- Keeping the secret handling INSIDE the script matters: a terminal command containing a literal
  --admin-password gets cancelled by the autopilot guard as "sensitive input required". A plain
  "& script.ps1 ..." invocation carries no secret and runs fine.

--------------------------------------------------------------------------------
## 3. SSH in (non-interactive flags)

    $ip = az stack-hci-vm network nic show -g rg-azlocal-poc-001 --name rocky-docker-01-nic `
            --query "properties.ipConfigurations[0].properties.privateIpAddress" -o tsv
    ssh -i .\.creds\poc-vm-key -o StrictHostKeyChecking=accept-new -o BatchMode=yes azureuser@$ip

Gotchas:
- BatchMode=yes + accept-new stop SSH from ever halting on a password or host-key prompt.
- If you reuse a pool IP from a deleted VM you get "REMOTE HOST IDENTIFICATION HAS CHANGED". Clear it:
      ssh-keygen -R <ip>
- Provisioning runs on first boot; if login is refused right after create, wait ~1 min and retry (but if it
  keeps refusing, check the key passphrase per section 1 - that was the real cause here, not timing).

--------------------------------------------------------------------------------
## 4. Install Docker on Rocky 10 (the el10 workaround)

Docker CE has no el10 packages yet (Rocky 10 / RHEL 10 is new). The get.docker.com script fails with
"Unable to find a match: docker-ce". Use Docker's CentOS repo pinned to release 9 - the el9 packages install
cleanly on Rocky 10:
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo sed -i 's/$releasever/9/g' /etc/yum.repos.d/docker-ce.repo
    sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker azureuser    # log out/in for the group to take effect; until then use sudo docker
Verify:
    sudo docker --version ; sudo docker compose version ; sudo docker run --rm hello-world
(On Ubuntu this is just the standard get.docker.com or the docker apt repo - no el-version trick needed.)

--------------------------------------------------------------------------------
## 5. Deploy Dockge (the manager)

    sudo mkdir -p /opt/dockge /opt/stacks
    # /opt/dockge/compose.yaml:
    #   services:
    #     dockge:
    #       image: louislam/dockge:1
    #       restart: unless-stopped
    #       ports: ["5001:5001"]
    #       volumes:
    #         - /var/run/docker.sock:/var/run/docker.sock
    #         - ./data:/app/data
    #         - /opt/stacks:/opt/stacks
    #       environment: [ DOCKGE_STACKS_DIR=/opt/stacks ]
    cd /opt/dockge && sudo docker compose up -d
    sudo docker compose ps                       # expect: healthy
    curl -o /dev/null -w "%{http_code}\n" http://localhost:5001/    # expect 200

The Rocky-Azure image has no firewalld, so there is no host firewall to open. Docker publishes 5001 on
0.0.0.0, so from another host on the mgmt subnet: browse http://<vm-ip>:5001 (page title "Dockge").

--------------------------------------------------------------------------------
## 6. The three management tiers (what you end up with)

- Dockge (container-native): http://<vm-ip>:5001 - stacks, logs, console.
- SSH / docker CLI: ssh in, run docker/compose directly.
- Azure Arc (Azure-native, host level): the VM is an Arc-enabled server (guest agent Connected). Verify:
      az resource show -g <rg> -n <vm> `
        --resource-type Microsoft.HybridCompute/machines --query properties.status -o tsv    # Connected
  From Azure you then get Run Command, VM extensions (e.g. Azure Monitor / Container Insights), Machine
  Configuration, and Update Manager. (Per-container start/stop stays in Dockge/CLI; Arc manages the host.)

--------------------------------------------------------------------------------
## 7. Result observed (snapshot, our PoC - values are ours, not canonical)

- Host: rocky-docker-01, image rocky-azure (Rocky Linux 10.2), Gen2/Secure Boot. Its IP is whatever the
  tenant pool hands out (was 10.10.1.242 on 2026-07-30, moved to 10.10.1.208 after the 2026-07-31
  network migration - point being, the IP is not fixed and yours will differ).
- Docker CE 29.x + Compose v5.3.1 (el9 packages on el10).
- Dockge healthy, http 200 locally and from the DevBox.
- Arc: HybridCompute machine Connected, Azure Connected Machine Agent 1.66.
- Ubuntu 24.04 also created as an isolation test - SSH works there too.

--------------------------------------------------------------------------------
## 8. Notes / follow-ups

- Size the tenant logical-network IP pool for the number of VMs you expect; only use IPs reserved in
  DNS/IPAM (see resource-migration-deletion-protocol.md and the IP-allocation rule).
- To store a "docker golden image" (Docker+Dockge baked in): stop + deprovision the VM (cloud-init clean,
  waagent -deprovision), then az stack-hci-vm image create --source-vm <vm>. This briefly stops the running
  Dockge host, so do it deliberately.
- Teardown (order matters, see the migration runbook): az stack-hci-vm delete --name <vm> -g <rg> --yes ;
  then the NIC ; then the lnet if unused.

