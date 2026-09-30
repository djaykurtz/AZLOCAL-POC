---
title: "Runbook: Azure Local resource migration + deletion protocol"
domain: [platform]
layer: [arc]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [deletion-order, migration, logical-network, nic, safety-protocol]
updated: 2026-07-31
---

# Runbook: Azure Local resource migration + deletion protocol

Written 2026-07-31 after a messy tenant-network migration (bulk-deleted right after elevating, mis-diagnosed
a role gap). This captures the disciplined way to delete/migrate Arc VM resources so it goes clean.

The two hard rules that would have avoided the mess:
1. After PIM elevation, WAIT before delete/create - the RP needs time to honor the role.
2. Operate ONE resource at a time and verify between - never bulk-run a long delete script.

--------------------------------------------------------------------------------
## 1. Elevate, then WAIT (do not operate immediately)

    .\scripts\Invoke-PocPimElevation.ps1        # Azure Stack HCI Administrator + UAA (sufficient)

Then wait ~2-3 minutes before any az stack-hci-vm delete/create. The Microsoft.AzureStackHCI resource
provider lags behind the PIM activation, so operations right after elevating fail with a TRANSIENT error:

    (AuthorizationFailed) ... does not have authorization to perform action
    'Microsoft.AzureStackHCI/.../delete' ... or the scope is invalid.
    If access was recently granted, please refresh your credentials.

This is propagation lag, NOT a real permission gap. Do NOT:
- add Contributor to the elevation (the two default roles cover VM create AND delete),
- refresh the token / re-login (does not help),
- keep hammering.
Just wait and retry the SAME single operation - it succeeds once the RP catches up.

Confirm the roles are active if unsure:
    az role assignment list --assignee <your-oid> --scope /subscriptions/<sub> --query "[].roleDefinitionName" -o tsv

--------------------------------------------------------------------------------
## 2. Deletion ORDER for an Arc VM (matters)

An Arc VM has bound child/associated resources. Delete in this order, verifying each step:

  1. VM instance:   az stack-hci-vm delete --name <vm> -g <rg> --yes
  2. its NIC:       az stack-hci-vm network nic delete --name <vm>-nic -g <rg> --yes
  3. the lnet:      az stack-hci-vm network lnet delete --name <lnet> -g <rg> --yes   (only once no NIC uses it)

The message "Before deleting the NIC(s), you must either detach them from their associated resources or ...
delete them" means the NIC is still BOUND to the VM until the VM delete fully settles. So:
- delete the VM,
- verify it is gone (az stack-hci-vm list),
- THEN delete the NIC (it may still hit the transient window above - wait and retry the single NIC),
- an lnet cannot be deleted while any NIC references it.

--------------------------------------------------------------------------------
## 3. One at a time, verify between (no bulk scripts)

Do not run a loop that deletes many resources back to back right after elevating - the first ones may fail
on propagation and you cannot tell what actually happened. Instead:

    # delete one
    az stack-hci-vm delete --name <vm> -g <rg> --yes
    # verify
    az stack-hci-vm list -g <rg> --query "[].name" -o tsv
    # next...

Check inventory before and after each destructive step:
    az stack-hci-vm list        -g <rg> --query "[].name" -o tsv
    az stack-hci-vm network nic  list -g <rg> --query "[].{nic:name,ip:properties.ipConfigurations[0].properties.privateIpAddress}" -o table
    az stack-hci-vm network lnet list -g <rg> --query "[].name" -o tsv

--------------------------------------------------------------------------------
## 4. IP / network migration specifics

- Only ever place VMs on IPs the user has RESERVED in DNS/IPAM (see the IP-allocation rule). Do not
  self-allocate addresses on the shared static subnet.
- A VM's static IP cannot be changed after creation, so "moving" a VM to a new IP = rebuild:
    1. build the new logical network on the reserved pool first,
    2. delete the old VM(s)/NIC(s)/lnet per section 2,
    3. recreate the VM on the new lnet (New-AzLocalTestVm.ps1) - it takes the first free pool IP,
    4. reinstall the workload (scripted; see the docker/dockge runbook).
- Reusing a pool IP from a deleted VM leaves a stale SSH host key: clear with ssh-keygen -R <ip>.
- Record the new owned scope in memory/docs after any block change.

--------------------------------------------------------------------------------
## 5. What "done" looks like (verify)

- Old IPs released: they no longer appear in the NIC list.
- New lnet Succeeded with the expected pool (used/available counts sane).
- Rebuilt VM Running on the expected IP, workload back up, Arc guest agent Connected:
    az resource show -g <rg> -n <vm> --resource-type Microsoft.HybridCompute/machines --query properties.status -o tsv   # Connected

--------------------------------------------------------------------------------
## Reference: the 2026-07-31 migration (what this fixes)

Moved the tenant network off the borrowed .240-.243 onto the owned .208-.219 reservation. Deleted 4 VMs +
NICs + the old lnet, created the new lnet, rebuilt the Docker/Dockge host on .208. It worked, but the first
passes failed because I bulk-ran deletes ~1 min after elevating (propagation lag) and briefly mis-read it as
a Contributor role gap. Following sections 1-3 above avoids both.

