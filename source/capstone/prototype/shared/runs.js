/*
 * What we ran, shared.
 *
 * This is the command layer under the visual. The diagram shows how the pieces of Azure Local fit
 * together and how the Docker, Terraform and Kubernetes lifecycle moves through them. This file
 * holds what was actually typed at each point, what came back, and how long it really took.
 *
 * It is a record of what was attempted and what happened, not an argument. Some of these runs
 * failed, and those are as useful to show as the ones that worked.
 *
 * Two consumers read this file:
 *   - v2, which binds a run to the movement it belongs to and replays it in place
 *   - the standalone player, which lists every run and replays any of them
 *
 * `stage` is the binding key. It is the zero based index of the v2 movement this run belongs to,
 * or null when it does not sit inside the arc. The unbound ones are deliberate: the drive failure
 * and the two runs around it were never part of the plan, and they are reachable from the
 * standalone player when a question goes deeper than a movement does.
 *
 * `what` is one plain sentence describing what happened, for the list view.
 *
 * Timings in `t` are milliseconds into the replay, already compressed from the real run. `real`
 * carries the true wall time so the gap can be stated rather than hidden.
 */

window.RUNS = [
  {
    id: 'alive',
    kind: 'control',
    status: 'ok',
    live: true,
    stage: 10,
    where: 'any time',
    what: 'This cluster is running right now, while we are talking.',
    host: 'devbox -> azl-cluster-01-aks-01',
    real: 'not timed',
    cmd: 'kubectl get nodes -o wide\nkubectl get pods',
    lines: [
      { t: 300,  s: 'NAME            STATUS   ROLES    AGE   VERSION' },
      { t: 700,  s: 'moc-worker-01   Ready    <none>   25d   v1.33.5', tone: 'good' },
      { t: 1500, s: 'NAME              READY   STATUS    RESTARTS   AGE' },
      { t: 1900, s: 'dashboard-72jvt   1/1     Running   0          9d', tone: 'good' },
      { t: 2300, s: 'dashboard-m94q2   1/1     Running   0          9d', tone: 'good' },
      { t: 3000, s: 'Everything else in this list was recorded. This one does not have to be.', tone: 'note' }
    ]
  },

  {
    id: 'drivedied',
    kind: 'storage',
    status: 'ok',
    stage: null,
    where: 'resilience',
    what: 'A drive died in a lab 200 miles away and the only consequence was a number in a health report.',
    host: 'AZL-NODE-01',
    real: 'noticed 10 days later',
    cmd: 'Get-PhysicalDisk | Where-Object HealthStatus -ne Healthy',
    lines: [
      { t: 300,  s: 'PM9A1 NVMe Samsung 512GB   Warning   Lost Communication   Retired', tone: 'bad' },
      { t: 1200, s: 'Cluster nodes           all four Up', tone: 'good' },
      { t: 1700, s: 'Storage pool SU1_Pool   Healthy / OK', tone: 'good' },
      { t: 2200, s: 'Workloads               uninterrupted', tone: 'good' },
      { t: 3100, s: 'No outage. No data loss. Nobody was paged.', tone: 'note' },
      { t: 3900, s: 'This is the part nobody demos, because nothing happens.', tone: 'note' }
    ]
  },

  {
    id: 'refused',
    kind: 'control',
    status: 'fail',
    stage: null,
    where: 'resilience',
    what: 'The platform refused to let me reboot my own machine. Four times. It was right every time.',
    host: 'AZL-CLUSTER-01',
    real: 'one evening',
    cmd: 'Enable-StorageMaintenanceMode\nSuspend-ClusterNode -Drain\nSuspend-ClusterNode -ForceDrain',
    lines: [
      { t: 400,  s: 'Currently unsafe to perform the operation', tone: 'bad' },
      { t: 1300, s: 'A clustered space is in a degraded condition and the requested', tone: 'bad' },
      { t: 1500, s: 'action cannot be completed at this time', tone: 'bad' },
      { t: 2400, s: 'ForceDrain: refused', tone: 'bad' },
      { t: 3300, s: 'One virtual disk was missing one of its three copies.', tone: 'warn' },
      { t: 4100, s: 'It would not trade any more redundancy to make my life easier.', tone: 'note' },
      { t: 5000, s: 'There is no lab override. It cannot tell disposable from irreplaceable,', tone: 'note' },
      { t: 5600, s: 'so it assumes the worst. That refusal is the product.', tone: 'note' }
    ]
  },

  {
    id: 'deadlock',
    kind: 'storage',
    status: 'ok',
    stage: null,
    where: 'resilience',
    what: 'The reboot did not fix the drive. It fixed the thing the drive broke.',
    host: 'AZL-NODE-01',
    real: '3m 04s to reboot',
    cmd: 'Stop-ClusterNode; Restart-Computer -Force',
    lines: [
      { t: 400,  s: 'The deadlock: repair suspended -> volume degraded -> pause refused', tone: 'warn' },
      { t: 900,  s: '-> cannot reboot -> repair stays suspended', tone: 'warn' },
      { t: 1900, s: 'Left the cluster deliberately instead of asking permission to pause.' },
      { t: 2700, s: 'PCI bus 180   Error   x2      still dead', tone: 'bad' },
      { t: 3400, s: 'UserStorage_2-Repair   Completed   100%', tone: 'good' },
      { t: 3900, s: 'UserStorage_2          Healthy / OK', tone: 'good' },
      { t: 4400, s: 'All four nodes Up. All workloads Online throughout.', tone: 'good' },
      { t: 5300, s: 'A repair stuck at zero for ten days finished on its own after a restart.', tone: 'note' },
      { t: 6000, s: 'The hardware is still broken. The system is not.', tone: 'note' }
    ]
  },

  {
    id: 'rollingupdate',
    kind: 'orch',
    status: 'ok',
    stage: null,
    where: '2026-09-01',
    what: 'Every instance of a running workload was replaced without the service losing an endpoint.',
    host: 'devbox -> azl-cluster-01-aks-01',
    real: '22s',
    cmd: 'kubectl rollout restart deployment/azure-local-dashboard\nkubectl rollout status deployment/azure-local-dashboard',
    lines: [
      { t: 200,  s: 'before: 2/2 ready, endpoints 10.244.51.90, 10.244.51.91' },
      { t: 700,  s: 'strategy: RollingUpdate maxSurge 25%, maxUnavailable 25%' },
      { t: 1300, s: 'at 2 replicas that floors to maxUnavailable 0. Nothing may go down first.', tone: 'note' },
      { t: 2100, s: 'deployment.apps/azure-local-dashboard restarted' },
      { t: 2900, s: 'Waiting... 1 out of 2 new replicas have been updated...' },
      { t: 3900, s: 'Waiting... 1 old replicas are pending termination...' },
      { t: 4800, s: 'deployment "azure-local-dashboard" successfully rolled out', tone: 'good' },
      { t: 5600, s: 'sampled ready endpoints 34 times over 22s, every 250ms' },
      { t: 6400, s: 'minimum ready endpoints observed: 2. It never dropped.', tone: 'good' },
      { t: 7200, s: 'after: 2/2 ready, new pods k7ztz and mlxnk on a new ReplicaSet', tone: 'good' },
      { t: 8100, s: 'one retiring pod exited Error. The workload ignores SIGTERM.', tone: 'bad' },
      { t: 9000, s: 'That is the patching story. Replace everything, stay answerable.', tone: 'note' },
      { t: 9800, s: 'Both pods sit on one worker node, so this survives updates, not hardware.', tone: 'note' }
    ]
  },

  {
    id: 'livemigrate',
    kind: 'storage',
    status: 'ok',
    stage: 7,
    where: '2026-09-01',
    what: 'The machine under a running workload moved to another host, and Kubernetes never noticed.',
    host: 'azl-node-01 -> azl-node-04',
    real: '16.7s',
    cmd: 'Move-ClusterVirtualMachineRole -Name <aks-worker> -Node AZL-NODE-04 -MigrationType Live',
    lines: [
      { t: 200,   s: 'worker VM hosting both dashboard pods: owned by AZL-NODE-01' },
      { t: 900,   s: 'that is the node whose NVMe failed and was retired', tone: 'note' },
      { t: 1700,  s: 'probing the Kubernetes API every ~650ms, endpoints and node Ready' },
      { t: 2500,  s: 'live migration started' },
      { t: 3200,  s: 'ready endpoints  2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2' },
      { t: 3900,  s: 'node Ready       T T T T T T T T T T T T T T T T T' },
      { t: 4600,  key: 'mig', wait: true, s: 'waiting for the move to return...' },
      { t: 8400,  key: 'mig', pop: true, s: 'migration returned after 16.7s !', tone: 'good' },
      { t: 9500,  s: 'now owned by AZL-NODE-04. 34 samples, minimum ready endpoints 2.', tone: 'good' },
      { t: 10300, s: 'pods still 0 restarts. The containers never moved. The floor did.', tone: 'good' },
      { t: 11200, s: 'ICMP is filtered from the devbox, so this is what the orchestrator saw.', tone: 'note' },
      { t: 12000, s: 'This is what Cluster-Aware Updating does to every node in turn.', tone: 'note' }
    ]
  },

  {
    id: 'crossed',
    kind: 'net',
    status: 'fail',
    stage: 0,
    where: 'movement 00',
    what: 'Three of the four machines had their two storage ports wired to the wrong fabrics.',
    host: 'AZL-NODE-01',
    real: 'not timed',
    cmd: 'pktmon filter add LLDP --ethertype 0x88CC\npktmon start --capture --pkt-size 256',
    lines: [
      { t: 400,  s: 'Packet Monitor started. Filter: LLDP (0x88CC).' },
      { t: 1400, s: 'node01  Port3 -> 7050SW2 / vlan 712', tone: 'bad' },
      { t: 1900, s: 'node02  Port3 -> 7050SW1 / vlan 711', tone: 'good' },
      { t: 2400, s: 'node04  Port3 -> 7050SW2 / vlan 712', tone: 'bad' },
      { t: 2900, s: 'node06  Port3 -> 7050SW2 / vlan 712', tone: 'bad' },
      { t: 3900, s: 'AzureLocal_Network_Test_StorageConnections_ConnectivityCheck' },
      { t: 4500, s: '0 of 6 reachable. All four machines. Both directions. Both VLANs.', tone: 'bad' },
      { t: 5400, s: 'Every machine could see a switch. No machine could see the right one.', tone: 'note' }
    ]
  },

  {
    id: 'fabrics',
    kind: 'net',
    status: 'ok',
    stage: 0,
    where: 'movement 00',
    what: 'After renaming the adapters, both storage fabrics forwarded tagged traffic on every machine.',
    host: 'AZL-NODE-01',
    real: 'not timed',
    gap: [
      'Ignore Windows defaults and give NICs MAC-based labels . . . FIXED!',
      'Default VLAN removed and SW2 properly trunked . . . FIXED!'
    ],
    cmd: 'Rename-NetAdapter -Name Port4 -NewName Port3\nTest-NetConnection -Source Port3 -ComputerName 10.40.1.185',
    lines: [
      { t: 300,  s: 'Port3 -> 7050SW1 / vlan 711  on all four machines' },
      { t: 900,  s: 'Port4 -> 7050SW2 / vlan 712  on all four machines' },
      { t: 2000, s: '6 of 6 reachable. Both fabrics forwarding tagged.', tone: 'good' },
      { t: 2900, s: 'RDMA negotiated. PFC priority 3 no-drop confirmed end to end.', tone: 'good' }
    ]
  },

  {
    id: 'deploy',
    kind: 'control',
    status: 'ok',
    stage: 2,
    where: 'movement 02',
    what: 'The cluster deployed in a single pass, with all 54 steps reporting Success.',
    host: 'AZL-CLUSTER-01',
    real: '2h 13m',
    cmd: 'Enterprise Cloud Engine, 54 steps',
    lines: [
      { t: 300,   s: 'step 03 of 54   Resolve requirement                      Success   about 27m' },
      { t: 800,   s: 'step 13 of 54   Validate network settings for servers    Success' },
      { t: 1300,  s: 'step 16 of 54   Create the cluster                       Success   about 15m' },
      { t: 1800,  s: 'step 17 of 54   Configure networking                     Success   about  6m' },
      { t: 2400,  key: 's22', wait: true, s: 'step 22 of 54   Config storage (Storage Spaces)          ...' },
      { t: 6900,  key: 's22', pop: true, s: 'step 22 of 54   Config storage (Storage Spaces)          Success !' },
      { t: 9000,  pop: true, s: '                Hardware Validation complete !!', tone: 'good' },
      { t: 11500, s: 'step 24 of 54   Encrypt cluster shared volumes           Success' },
      { t: 12000, s: 'step 33 of 54   Cluster the deployment orchestrator      Success' },
      { t: 12500, s: 'step 35 of 54   Apply security policies                  Success   about  6m' },
      { t: 13000, s: 'step 36 of 54   Install hardware updates via SBE         Success' },
      { t: 13500, s: 'step 40 of 54   Deploy Arc infrastructure                Success   about 64m' },
      { t: 14000, s: 'step 44 of 54   Migrate deployment orchestrator          Success' },
      { t: 14500, s: 'step 46 of 54   Set up trusted launch for VMs            Success   about  6m' },
      { t: 15000, s: 'step 52 of 54   Finalize security                        Success   about 10m' },
      { t: 15800, s: 'provisioningState: Succeeded', tone: 'good' },
      { t: 16600, s: '54 of 54 steps completed. None failed.', tone: 'good' },
      { t: 17600, s: '... and with those tasks done, a stack of leftover hardware is finally a minimum viable landscape for an Azure Local Proof of Concept.', tone: 'note' }
    ]
  },

  {
    id: 'aks',
    kind: 'orch',
    status: 'ok',
    stage: 3,
    where: 'movement 03',
    what: 'A managed Kubernetes cluster was created on top of the Azure Local cluster, not beside it.',
    host: 'devbox -> azl-cluster-01-cl',
    real: 'not timed',
    cmd: 'az aksarc create --name azl-cluster-01-aks-01 --custom-location azl-cluster-01-cl\nkubectl get nodes -o wide',
    lines: [
      { t: 300,   key: 'prov', wait: true, s: 'provisioningState: Creating...' },
      { t: 4400,  key: 'prov', pop: true, s: 'provisioningState: Succeeded !', tone: 'good' },
      { t: 5600,  s: 'kubernetesVersion: v1.33.5' },
      { t: 6400,  s: 'NAME              STATUS   ROLES           VERSION' },
      { t: 7000,  s: 'moc-control-plane-01   Ready    control-plane   v1.33.5', tone: 'good' },
      { t: 7600,  s: 'moc-worker-01          Ready    <none>          v1.33.5', tone: 'good' },
      { t: 8500,  s: 'Azure Linux 3.0. Neither machine existed before the command.', tone: 'note' }
    ]
  },

  {
    id: 'served',
    kind: 'work',
    status: 'ok',
    stage: 4,
    where: 'movement 04',
    what: 'A workload was applied from a file, came up behind one address, and requests reached more than one replica.',
    host: 'azl-cluster-01-aks-01',
    real: 'not timed',
    cmd: 'kubectl apply -f dashboard.yaml\nkubectl scale deployment/azure-local-dashboard --replicas=3\nthirty in-cluster requests through the Service',
    lines: [
      { t: 300,  s: 'deployment.apps/azure-local-dashboard created', tone: 'good' },
      { t: 800,  s: 'service/azure-local-dashboard created', tone: 'good' },
      { t: 1400, key: 'rdy', wait: true, s: 'deployment  0/2 ready...' },
      { t: 3800, key: 'rdy', s: 'deployment  2/2 ready, 2 available', tone: 'good' },
      { t: 4400, s: 'dashboard-m94q2   Running   0 restarts' },
      { t: 4900, s: 'dashboard-zgnwp   Running   0 restarts' },
      { t: 5700, s: 'Service ClusterIP 10.30.1.58:80, forwarding to targetPort 8080.', tone: 'note' },
      { t: 7000, key: 'sc', wait: true, s: 'scaling to 3 replicas...' },
      { t: 9000, key: 'sc', s: 'deployment  3/3 ready. dashboard-72jvt Running, 0 restarts', tone: 'good' },
      { t: 9900, s: '30 in-cluster requests through the Service:' },
      { t: 10600, key: 'eps', pop: true, s: '  m94q2 answered 17,   72jvt answered 13 !', tone: 'good' },
      { t: 11600, s: 'One address, more than one pod behind it, chosen by the Service.', tone: 'note' }
    ]
  },

  {
    id: 'podheal',
    kind: 'orch',
    status: 'ok',
    stage: 8,
    where: 'movement 08',
    what: 'A healthy pod was deleted on purpose and the deployment put itself back.',
    host: 'azl-cluster-01-aks-01',
    real: 'not timed',
    cmd: 'kubectl delete pod dashboard-zgnwp\nkubectl get pods -w',
    lines: [
      { t: 300,   s: 'three replicas running: m94q2, zgnwp and 72jvt' },
      { t: 1200,  s: 'pod "dashboard-zgnwp" deleted', tone: 'warn' },
      { t: 1900,  s: 'deployment  2/3 ready', tone: 'warn' },
      { t: 2600,  key: 'p', wait: true, s: 'dashboard-kjdrh   Pending...' },
      { t: 4300,  key: 'p', wait: true, s: 'dashboard-kjdrh   ContainerCreating...' },
      { t: 6300,  key: 'p', pop: true, s: 'dashboard-kjdrh   Running   0 restarts !', tone: 'good' },
      { t: 7400,  s: 'deployment  3/3 ready.  EndpointSlice: 3 ready', tone: 'good' },
      { t: 8300,  s: 'No human touched this between the two commands.', tone: 'note' }
    ]
  },

  {
    id: 'terraform',
    kind: 'control',
    status: 'ok',
    stage: 5,
    where: 'movement 05',
    what: 'A virtual machine was created from a file, then removed by that same file.',
    host: 'devbox',
    real: 'not timed',
    cmd: 'terraform plan\nterraform apply\nterraform destroy',
    lines: [
      { t: 300,  s: 'Plan: 3 to add, 0 to change, 0 to destroy.' },
      { t: 900,  s: '  + Microsoft.HybridCompute/machines/tf-poc-linux-01' },
      { t: 1300, s: '  + Microsoft.AzureStackHCI/networkInterfaces/tf-poc-linux-01-nic' },
      { t: 1700, s: '  + Microsoft.AzureStackHCI/virtualMachineInstances/default' },
      { t: 2400, key: 'ap', wait: true, s: 'Still creating...' },
      { t: 5400, key: 'ap', pop: true, s: 'Apply complete. 3 added, 0 changed, 0 destroyed.', tone: 'good' },
      { t: 6500, s: 'Clustered VM Online on AZL-NODE-04' },
      { t: 7100, s: 'Hyper-V: Running, Operating normally', tone: 'good' },
      { t: 8100, s: 'Destroy complete. VM extension, VM, NIC and Arc machine removed.' },
      { t: 8900, s: 'terraform plan -destroy  ->  No objects need to be destroyed.', tone: 'good' },
      { t: 9800, s: 'It was reviewable before it existed and reversible after.', tone: 'note' }
    ]
  },

  {
    id: 'docker',
    kind: 'work',
    status: 'ok',
    stage: 6,
    where: 'movement 06',
    what: 'Ordinary containers run here, with no Kubernetes involved at all.',
    host: 'rocky-10.2 guest',
    real: 'not timed',
    cmd: 'sudo docker run --rm hello-world\ncd /opt/dockge && sudo docker compose up -d',
    lines: [
      { t: 300,  s: 'Hello from Docker!' },
      { t: 800,  s: 'This message shows that your installation appears to be working correctly.', tone: 'good' },
      { t: 1700, s: 'Docker CE 29.x   Compose v5.3.1' },
      { t: 2300, key: 'up', wait: true, s: 'Container dockge   Starting...' },
      { t: 4600, key: 'up', s: 'Container dockge   Started', tone: 'good' },
      { t: 5300, s: 'curl -o /dev/null -w "%{http_code}" http://<vm-ip>:5001/' },
      { t: 6000, key: 'code', wait: true, s: '...' },
      { t: 7600, key: 'code', pop: true, s: '200', tone: 'good' },
      { t: 8600, s: 'Answered from the DevBox too, not just from localhost.', tone: 'note' }
    ]
  },

  {
    id: 'heal',
    kind: 'storage',
    status: 'ok',
    stage: 8,
    where: 'movement 08',
    what: 'A machine left the cluster and the storage stayed online, degraded but serving.',
    host: 'AZL-CLUSTER-01',
    real: 'not timed',
    cmd: 'Get-ClusterNode; Get-StoragePool; Get-StorageJob',
    lines: [
      { t: 300,  s: 'AZL-NODE-01   Up' },
      { t: 800,  s: 'AZL-NODE-02   Up' },
      { t: 1300, s: 'AZL-NODE-04   Down', tone: 'bad' },
      { t: 1800, s: 'AZL-NODE-06   Up' },
      { t: 2600, s: 'HealthStatus: Warning', tone: 'warn' },
      { t: 3200, s: '6 virtual disks Degraded, all still Online', tone: 'warn' },
      { t: 3900, key: 'rep', wait: true, s: 'checking for repair jobs...' },
      { t: 6200, key: 'rep', pop: true, s: '3 repair jobs Running. Nobody started them.', tone: 'good' },
      { t: 7300, s: 'Degraded is not the same as down. That distinction is the whole point.', tone: 'note' }
    ]
  }
];

// Runs that belong to a given v2 movement, in the order they were authored.
window.runsForStage = function (index) {
  return window.RUNS.filter(function (r) { return r.stage === index; });
};
