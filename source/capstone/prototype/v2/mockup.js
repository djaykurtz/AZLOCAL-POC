/*
 * Mockup v2 engine.
 *
 * Demonstrates the design decisions rather than the full narrative. Six movements are enough to
 * show the arc from dense monochrome to five kinds, the fabric morph, and the healing sequence.
 */

const KINDS = [
  { id: 'net',     name: 'Networking',    css: 'var(--k-net)' },
  { id: 'storage', name: 'Storage',       css: 'var(--k-storage)' },
  { id: 'control', name: 'Control plane', css: 'var(--k-control)' },
  { id: 'orch',    name: 'Orchestration', css: 'var(--k-orch)' },
  { id: 'work',    name: 'Workload',      css: 'var(--k-work)' }
];

const MACHINES = ['01', '02', '03', '04', '05', '06'];

const MACHINE_IP = {
  '01': '10.10.1.187', '02': '10.10.1.188', '03': '10.10.1.189',
  '04': '10.10.1.190', '05': '10.10.1.191', '06': '10.10.1.192'
};

/* Averaged across nodes 01 and 04, measured 2026-09-08 with sppsvc freshly restarted so a leaking
   licensing service is not counted as platform. The Kubernetes band is the AKS control plane VM,
   which is infrastructure rather than workload: it has to exist before anything of yours can run.
   Ordered as the pathways light in the rail, on top of the Windows substrate they all sit on.
   Every figure here is measured. The only liberty is a minimum band width in CSS so the smallest
   band stays visible, and its true size is printed in the key. */
const MEMORY = {
  totalMB: 32298,
  bands: [
    { name: 'Windows and security', mb: 5205, css: 'var(--ink-dim)' },
    { name: 'Network fabric', mb: 249, css: 'var(--k-net)' },
    { name: 'Storage Spaces Direct', mb: 1927, css: 'var(--k-storage)' },
    { name: 'Azure Local, Arc, Hyper-V', mb: 3352, css: 'var(--k-control)' },
    { name: 'Azure Kubernetes', mb: 8192, css: 'var(--k-orch)' }
  ]
};

const LAYERS = [
  {
    tag: 'Fabric',
    id: 'switches',
    nodes: [
      { id: 'sw1', name: '7050SW1', meta: 'Arista 7050', detail: 'stor-sw-01\nVLAN 711, PFC pri 3' },
      { id: 'sw2', name: '7050SW2', meta: 'Arista 7050', detail: 'stor-sw-02\nVLAN 712, PFC pri 3' }
    ]
  },
  {
    tag: 'Machines',
    id: 'machines',
    nodes: MACHINES.map((n) => ({
      id: 'h' + n,
      name: 'AZL-NODE-' + n,
      meta: 'Precision 7960 Rack',
      detail: MACHINE_IP[n] + '\n32 GB, 1 OS NVMe, 3 storage NVMe'
    }))
  },
  {
    tag: 'Platform',
    id: 'platform',
    nodes: [
      { id: 'azl', name: 'Azure Local', meta: '24H2 cluster', detail: 'AZL-CLUSTER-01' },
      { id: 'arc', name: 'Arc bridge', meta: 'control plane', detail: 'azl-cluster-01-cl' },
      { id: 's2d', name: 'Storage Spaces Direct', meta: '3-way mirror', detail: '6 virtual disks' }
    ]
  },
  {
    tag: 'Runtime',
    id: 'runtime',
    nodes: [
      { id: 'aks', name: 'AKS Arc', meta: 'v1.33.5', detail: 'azl-cluster-01-aks-01' },
      { id: 'wrk', name: 'Worker node', meta: 'Azure Linux', detail: 'Ready' },
      { id: 'tfvm', name: 'Declared VM', meta: 'written in code', detail: 'tf-poc-linux-01\ncreated, then removed' },
      { id: 'vm',  name: 'Container host', meta: 'Rocky Linux 10.2', detail: 'Arc managed' }
    ]
  },
  {
    tag: 'Application',
    id: 'application',
    nodes: [
      { id: 'dep', name: 'Deployment', meta: 'desired state', detail: 'azure-local-dashboard' },
      { id: 'svc', name: 'Service', meta: 'ClusterIP', detail: '10.30.1.58' },
      { id: 'p1',  name: 'Pod', meta: 'replica 1', detail: 'dashboard-m94q2' },
      { id: 'p2',  name: 'Pod', meta: 'replica 2', detail: 'dashboard-zgnwp' },
      { id: 'p3',  name: 'Pod', meta: 'replica 3', detail: 'dashboard-72jvt' },
      { id: 'dkr', name: 'Docker CE', meta: '29.x', detail: 'Compose v5.3.1' },
      { id: 'dkg', name: 'Dockge', meta: 'container', detail: 'port 5001, http 200' }
    ]
  }
];

// Full mesh between the machines, which is why the opening is dense and monochrome.
function mesh(ids, kind) {
  const out = [];
  for (let i = 0; i < ids.length; i += 1) {
    for (let j = i + 1; j < ids.length; j += 1) out.push({ a: ids[i], b: ids[j], kind });
  }
  return out;
}

const ALL6 = MACHINES.map((n) => 'h' + n);
const ACTIVE4 = ['h01', 'h02', 'h04', 'h06'];
const SWITCHES = ['sw1', 'sw2'];

// The demotion is staged. Switches reach the margin a movement before the machines do, because
// the fabric is something the network becomes first and the servers join afterwards.
const FABRIC_NET = SWITCHES;
const FABRIC_ALL = SWITCHES.concat(ACTIVE4);

// Machines do not talk to each other directly. Every storage path runs through a switch,
// so the opening topology is machines to SW1 and SW2 rather than a machine to machine mesh.
function viaSwitches(ids) {
  const out = [];
  ids.forEach((id) => {
    out.push({ a: id, b: 'sw1', kind: 'net' });
    out.push({ a: id, b: 'sw2', kind: 'net' });
  });
  return out;
}

const STAGES = [
  {
    title: 'Six machines, two switches',
    builtSub: 'and none of it visible to Azure yet',
    sub: 'Before anything is built, the only relationship that exists is whether a machine can reach a switch. Many paths, every one of them the same type.',
    fid: 'proven',
    kind: 'net',
    kinds: 1,
    activeNodes: ['h01'],
    detailNodes: true,
    show: ALL6.concat(['sw1', 'sw2']),
    edges: viaSwitches(ALL6),
    elapsed: '',
    // The whole pre-cluster network thread lives here, problem through fix. The intro tells this as
    // a story and stops at the outcome; this is the commands behind it.
    groups: [
      {
        name: 'Storage fabric east-west check', kind: 'net', status: 'fail', dur: '2m 10s',
        cmd: 'Test-NetConnection -Source Port3 -ComputerName 10.40.1.185',
        out: '0 of 6 on all four nodes, both directions, both VLANs.\nEvery link up at 100 Gbps the whole time.'
      },
      {
        name: 'Map each port to its switch over LLDP', kind: 'net', status: 'fail', dur: '45s',
        cmd: 'pktmon filter add LLDP --ethertype 0x88CC; pktmon start --capture',
        out: 'node01 Port3 -> sw2 / vlan 712   REVERSED\nnode02 Port3 -> sw1 / vlan 711   correct\nnode04 Port3 -> sw2 / vlan 712   REVERSED\nnode06 Port3 -> sw2 / vlan 712   REVERSED'
      },
      {
        name: 'Rename by MAC, then test again', kind: 'net', status: 'ok', dur: '38s',
        cmd: 'Rename-NetAdapter -Name <by MAC> -NewName Port3',
        out: 'Network ATC binds a VLAN to an adapter NAME.\nA reversed name tagged 711 onto the port wired to sw2,\nsplitting the fabric across two switches with no path\nbetween them. No recabling: renamed by MAC instead.\nsw2 was also in access mode, dropping tagged frames.'
      }
    ]
  },

  {
    title: 'Four nodes define the cluster',
    builtSub: 'the first thing Azure was ever told',
    sub: 'Two systems could not meet the strict requirements. One became an emergency spare, the other a parts bin. The final four clear the Azure Local hardware validator, 25 checks with no critical failures.',
    fid: 'proven',
    kind: 'storage',
    kinds: 2,
    activeNodes: ['h01'],
    detailNodes: true,
    inFabric: FABRIC_NET,
    show: ALL6.concat(SWITCHES),
    out: ['h03', 'h05'],
    edges: viaSwitches(ACTIVE4).concat(mesh(ACTIVE4, 'storage')),
    elapsed: '',
    // No groups. This movement's cutaway is the portal kind, so groups would never render, and the
    // network fix they used to hold now lives on movement 00 where the problem is stated.
    groups: []
  },

  {
    title: 'The nodes become fabric',
    builtSub: 'the hardware struggles were real',
    mem: true,
    sub: 'Individual servers become one pooled surface. A substrate in the margin but also a flexible workspace. Deployment: 54 of 54 steps completed, none failed, in 2h 13m.',
    fid: 'proven',
    kind: 'control',
    kinds: 3,
    activeNodes: ['azl'],
    inFabric: FABRIC_ALL,
    show: ACTIVE4.concat(['azl', 'arc', 's2d']),
    edges: [
      { a: 'h01', b: 'azl', kind: 'control' }, { a: 'h02', b: 'azl', kind: 'control' },
      { a: 'h04', b: 'azl', kind: 'control' }, { a: 'h06', b: 'azl', kind: 'control' },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'h01', b: 's2d', kind: 'storage' }, { a: 'h02', b: 's2d', kind: 'storage' },
      { a: 'h04', b: 's2d', kind: 'storage' }, { a: 'h06', b: 's2d', kind: 'storage' }
    ],
    elapsed: '',
    groups: [
      {
        name: 'Create cluster', kind: 'control', status: 'ok', dur: 'about 15m',
        cmd: 'ECE step 16 of 54',
        out: 'Four machines clustered. AZL-CLUSTER-01 online.',
        meter: { done: 16, total: 54, label: 'step 16 of 54' }
      },
      {
        name: 'Configure networking', kind: 'net', status: 'ok', dur: 'about 6m',
        cmd: 'ECE step 17 of 54',
        out: 'Network ATC applied. RDMA and PFC priority 3 clean.',
        meter: { done: 17, total: 54, label: 'step 17 of 54' }
      },
      {
        name: 'Deploy Arc infrastructure', kind: 'control', status: 'ok', dur: 'about 64m',
        cmd: 'ECE step 40 of 54',
        out: 'Arc resource bridge operational.\nCustom location azl-cluster-01-cl registered.',
        meter: { done: 40, total: 54, label: 'step 40 of 54' }
      },
      {
        name: 'Cluster the deployment orchestrator', kind: 'control', status: 'ok', dur: 'steps 33, 44',
        cmd: 'ECE step 33 of 54, then step 44',
        out: 'The installer moves onto the cluster it just built,\nso the cluster can service itself afterwards.',
        meter: { done: 44, total: 54, label: 'step 44 of 54' }
      },
      {
        name: 'Set up trusted launch for VMs', kind: 'control', status: 'ok', dur: 'about 6m',
        cmd: 'ECE step 46 of 54, with MAA either side',
        out: 'Secure Boot and a virtual TPM for future guests,\nand an attestation provider to vouch for them.',
        meter: { done: 46, total: 54, label: 'step 46 of 54' }
      }
    ]
  },

  {
    title: 'Scheduling arrives',
    builtSub: 'kubernetes placed on the cluster, not beside it',
    sub: 'Everything before this was foundation. Building on top of the control plane, Azure Kubernetes Service schedules WHAT runs WHERE and HOW.',
    fid: 'proven',
    kind: 'orch',
    kinds: 4,
    activeNodes: ['aks'],
    inFabric: FABRIC_ALL,
    busy: ['04'],
    show: ACTIVE4.concat(['azl', 'arc', 's2d', 'aks', 'wrk']),
    edges: [
      { a: 'h01', b: 'azl', kind: 'control' }, { a: 'h02', b: 'azl', kind: 'control' },
      { a: 'h04', b: 'azl', kind: 'control' }, { a: 'h06', b: 'azl', kind: 'control' },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'arc', b: 'aks', kind: 'orch' }, { a: 'aks', b: 'wrk', kind: 'orch' },
      { a: 'h04', b: 'wrk', kind: 'orch' }, { a: 's2d', b: 'wrk', kind: 'storage' }
    ],
    elapsed: 'AKS Arc reached Succeeded.',
    groups: [
      {
        name: 'Provision AKS on Azure Local', kind: 'orch', status: 'ok', dur: '',
        cmd: 'az aksarc create --name azl-cluster-01-aks-01 --custom-location azl-cluster-01-cl',
        out: 'provisioningState: Succeeded\nkubernetesVersion: v1.33.5'
      },
      {
        name: 'Confirm node registration', kind: 'orch', status: 'ok', dur: '',
        cmd: 'kubectl get nodes -o wide',
        out: 'NAME                  STATUS   ROLES           VERSION\nmoc-control-plane-01   Ready    control-plane   v1.33.5\nmoc-worker-01          Ready    <none>          v1.33.5'
      }
    ]
  },

  {
    title: 'Payload is served',
    builtSub: 'one file, three replicas, one address',
    sub: 'The fifth pathway only appears once traffic is real. One address in front of a changing set of pods, and requests land on more than one of them.',
    fid: 'proven',
    kind: 'work',
    kinds: 5,
    activeNodes: ['svc'],
    inFabric: FABRIC_ALL,
    busy: ['02', '04', '06'],
    show: ACTIVE4.concat(['azl', 'arc', 's2d', 'aks', 'wrk', 'dep', 'svc', 'p1', 'p2', 'p3']),
    edges: [
      { a: 'h01', b: 'azl', kind: 'control' }, { a: 'h04', b: 'azl', kind: 'control' },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'arc', b: 'aks', kind: 'orch' }, { a: 'aks', b: 'wrk', kind: 'orch' },
      { a: 'wrk', b: 'dep', kind: 'orch' }, { a: 'dep', b: 'p1', kind: 'orch' },
      { a: 'dep', b: 'p2', kind: 'orch' }, { a: 'dep', b: 'p3', kind: 'orch' },
      { a: 'svc', b: 'p1', kind: 'work' }, { a: 'svc', b: 'p2', kind: 'work' },
      { a: 'svc', b: 'p3', kind: 'work' },
      { a: 's2d', b: 'wrk', kind: 'storage' }
    ],
    elapsed: 'Every step passed.',
    groups: [
      {
        name: 'Apply the deployment', kind: 'orch', status: 'ok', dur: '',
        cmd: 'kubectl apply -f dashboard.yaml',
        out: 'deployment.apps/azure-local-dashboard created\nservice/azure-local-dashboard created'
      },
      {
        name: 'Two replicas ready, two endpoints', kind: 'work', status: 'ok', dur: '',
        cmd: 'kubectl get deploy,pods,endpointslice',
        out: 'deployment  2/2 ready, 2 available\ndashboard-m94q2   Running   0 restarts\ndashboard-zgnwp   Running   0 restarts\nEndpointSlice: 2 ready'
      },
      {
        name: 'Scale to three replicas', kind: 'orch', status: 'ok', dur: '',
        cmd: 'kubectl scale deployment/azure-local-dashboard --replicas=3',
        out: 'deployment 3/3 ready\ndashboard-72jvt   Running   0 restarts\nEndpointSlice: 3 ready'
      },
      {
        name: 'Traffic reaches more than one replica', kind: 'work', status: 'ok', dur: '',
        cmd: 'thirty requests to azure-local-dashboard.azure-local-dashboard.svc.cluster.local/api/work',
        out: 'm94q2 answered 17\n72jvt answered 13\nIn cluster, through the Service, not through a port-forward.'
      }
    ]
  },

  {
    title: 'Infrastructure as code',
    builtSub: 'created and destroyed from one definition',
    sub: 'The same virtual machine, created and later destroyed from a single Terraform definition. Nothing was clicked, and the file is the record of what exists.',
    fid: 'proven',
    kind: 'control',
    kinds: 5,
    activeNodes: ['tfvm'],
    inFabric: FABRIC_ALL,
    busy: ['04'],
    show: ACTIVE4.concat(['azl', 'arc', 's2d', 'aks', 'wrk', 'dep', 'svc', 'p1', 'p2', 'tfvm']),
    edges: [
      { a: 'h01', b: 'azl', kind: 'control' }, { a: 'h04', b: 'azl', kind: 'control' },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'arc', b: 'aks', kind: 'orch' }, { a: 'aks', b: 'wrk', kind: 'orch' },
      { a: 'wrk', b: 'dep', kind: 'orch' }, { a: 'dep', b: 'p1', kind: 'orch' },
      { a: 'dep', b: 'p2', kind: 'orch' },
      { a: 'svc', b: 'p1', kind: 'work' }, { a: 'svc', b: 'p2', kind: 'work' },
      { a: 's2d', b: 'wrk', kind: 'storage' },
      { a: 'arc', b: 'tfvm', kind: 'control' }, { a: 'h04', b: 'tfvm', kind: 'control' },
      { a: 's2d', b: 'tfvm', kind: 'storage' }
    ],
    elapsed: 'human operated lifecycle',
    groups: [
      {
        name: 'Read the change before making it', kind: 'control', status: 'ok', dur: '',
        cmd: 'terraform plan',
        out: 'Plan: 3 to add, 0 to change, 0 to destroy.\n  Microsoft.HybridCompute/machines/tf-poc-linux-01\n  Microsoft.AzureStackHCI/networkInterfaces/tf-poc-linux-01-nic\n  Microsoft.AzureStackHCI/virtualMachineInstances/default'
      },
      {
        name: 'Apply, and only that', kind: 'control', status: 'ok', dur: '',
        cmd: 'terraform apply',
        out: 'Apply complete. 3 added, 0 changed, 0 destroyed.\nClustered VM Online on AZL-NODE-04\nHyper-V: Running, Operating normally'
      },
      {
        name: 'Give it back', kind: 'control', status: 'ok', dur: '',
        cmd: 'terraform destroy; terraform plan -destroy',
        out: 'VM extension, clustered VM, NIC and Arc machine removed.\nNo objects need to be destroyed.\nOnly a read-only resource group data source remains in state.'
      }
    ]
  },

  {
    title: 'Kubernetes is optional',
    builtSub: 'no orchestrator anywhere near this one',
    sub: 'Inside that virtual machine, the ordinary container workflow works exactly as it does anywhere else. This is the answer to whether the platform is only useful if you have adopted Kubernetes.',
    fid: 'proven',
    kind: 'work',
    kinds: 5,
    activeNodes: ['dkg'],
    inFabric: FABRIC_ALL,
    busy: ['04'],
    show: ACTIVE4.concat(['azl', 'arc', 's2d', 'aks', 'wrk', 'dep', 'svc', 'p1', 'p2', 'vm', 'dkr', 'dkg']),
    edges: [
      { a: 'h01', b: 'azl', kind: 'control' }, { a: 'h04', b: 'azl', kind: 'control' },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'arc', b: 'aks', kind: 'orch' }, { a: 'aks', b: 'wrk', kind: 'orch' },
      { a: 'wrk', b: 'dep', kind: 'orch' }, { a: 'dep', b: 'p1', kind: 'orch' },
      { a: 'dep', b: 'p2', kind: 'orch' },
      { a: 'svc', b: 'p1', kind: 'work' }, { a: 'svc', b: 'p2', kind: 'work' },
      { a: 's2d', b: 'wrk', kind: 'storage' },
      { a: 'arc', b: 'vm', kind: 'control' }, { a: 'h04', b: 'vm', kind: 'control' },
      { a: 's2d', b: 'vm', kind: 'storage' },
      { a: 'vm', b: 'dkr', kind: 'work' }, { a: 'dkr', b: 'dkg', kind: 'work' }
    ],
    elapsed: 'Docker on the cluster',
    groups: [
      {
        name: 'The most boring possible proof', kind: 'work', status: 'ok', dur: '',
        cmd: 'sudo docker run --rm hello-world',
        out: 'Hello from Docker!\nThis message shows that your installation appears to be working correctly.'
      },
      {
        name: 'Bring up a real compose stack', kind: 'work', status: 'ok', dur: '',
        cmd: 'cd /opt/dockge && sudo docker compose up -d',
        out: 'Docker CE 29.x, Compose v5.3.1\ndockge  Started'
      },
      {
        name: 'Reachable from outside the machine', kind: 'work', status: 'ok', dur: '',
        cmd: 'curl -o /dev/null -w "%{http_code}\\n" http://<vm-ip>:5001/',
        out: '200\nAnswered from the DevBox as well, not just localhost.'
      }
    ]
  },

  {
    title: 'A machine moves, and nothing notices',
    builtSub: 'the floor moved, the workload did not',
    sub: 'A running machine changed hosts underneath a live workload. Everything above the machine layer stayed lit, and the work could not tell the difference.',
    fid: 'proven',
    kind: 'control',
    kinds: 5,
    activeNodes: ['azl'],
    inFabric: FABRIC_ALL,
    busy: ['01', '04'],
    show: ACTIVE4.concat(['azl', 'arc', 's2d', 'aks', 'wrk', 'dep', 'svc', 'p1', 'p2', 'vm', 'dkr', 'dkg']),
    edges: [
      { a: 'h01', b: 'azl', kind: 'control' },
      { a: 'h04', b: 'azl', kind: 'control' },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'arc', b: 'aks', kind: 'orch' }, { a: 'aks', b: 'wrk', kind: 'orch' },
      { a: 'wrk', b: 'dep', kind: 'orch' }, { a: 'dep', b: 'p1', kind: 'orch' },
      { a: 'dep', b: 'p2', kind: 'orch' },
      { a: 'svc', b: 'p1', kind: 'work' }, { a: 'svc', b: 'p2', kind: 'work' },
      { a: 's2d', b: 'wrk', kind: 'storage' },
      { a: 'arc', b: 'vm', kind: 'control' }, { a: 'h04', b: 'vm', kind: 'control' },
      { a: 's2d', b: 'vm', kind: 'storage' },
      { a: 'vm', b: 'dkr', kind: 'work' }, { a: 'dkr', b: 'dkg', kind: 'work' }
    ],
    elapsed: '16.7s to move the machine.',
    groups: [
      {
        name: 'Where the workload was running', kind: 'control', status: 'ok', dur: '0s',
        cmd: 'Get-ClusterGroup | Where-Object GroupType -eq VirtualMachine',
        out: 'AZL-NODE-01   Online   aks worker, both dashboard pods\nAZL-NODE-02   Online   aks control plane\nazl-node-06   Online   arc resource bridge\n\nThe worker sits on node 01, which is the node whose NVMe failed.'
      },
      {
        name: 'Patch the application, without dropping it', kind: 'orch', status: 'ok', dur: '22s',
        cmd: 'kubectl rollout restart deployment/azure-local-dashboard',
        out: 'RollingUpdate, maxUnavailable 25%, which floors to 0 at two replicas.\nKubernetes may not remove a pod before its replacement is ready.\n\n34 samples over 22s. Minimum ready endpoints: 2.\nBoth pods replaced onto a new ReplicaSet.'
      },
      {
        name: 'Patch the host, without dropping the application', kind: 'control', status: 'ok', dur: '16.7s',
        cmd: 'Move-ClusterVirtualMachineRole -Name <aks-worker> -Node AZL-NODE-04 -MigrationType Live',
        out: 'ready endpoints  2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2\nnode Ready       T T T T T T T T T T T T T T T T T\n\nOwner moved 01 -> 04, then back. Pods: 0 restarts.\nThis is what Cluster-Aware Updating does to every node in turn.'
      },
      {
        name: 'What this does not prove', kind: 'work', status: 'run', dur: 'BOUNDARY',
        cmd: 'kubectl get pods -o wide',
        out: 'Both pods run on the same worker node, because there is only one.\nThis survives maintenance. It does not survive losing that node.\n\nA production pattern needs a second worker, anti-affinity, a disruption\nbudget, and a workload that handles SIGTERM. One retiring pod exited Error.'
      }
    ]
  },

  {
    title: 'A machine leaves, and the fabric heals',
    builtSub: 'the same behaviour at two levels',
    sub: 'A pod is destroyed on purpose and a machine is lost for real. Both are put back by a controller that nobody asked.',
    fid: 'proven',
    kind: 'storage',
    kinds: 5,
    activeNodes: ['s2d'],
    inFabric: FABRIC_ALL,
    down: ['01'],
    repairing: ['01'],
    busy: ['02', '06'],
    show: ACTIVE4.concat(['azl', 'arc', 's2d', 'aks', 'wrk', 'dep', 'svc', 'p1', 'p2', 'p3', 'vm', 'dkr', 'dkg']),
    edges: [
      { a: 'h04', b: 'azl', kind: 'control' },
      { a: 'h01', b: 'azl', kind: 'control', failed: true },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'arc', b: 'aks', kind: 'orch' }, { a: 'aks', b: 'wrk', kind: 'orch' },
      { a: 'wrk', b: 'dep', kind: 'orch' }, { a: 'dep', b: 'p1', kind: 'orch' },
      { a: 'dep', b: 'p2', kind: 'orch' }, { a: 'dep', b: 'p3', kind: 'orch' },
      { a: 'svc', b: 'p1', kind: 'work' }, { a: 'svc', b: 'p2', kind: 'work' },
      { a: 'svc', b: 'p3', kind: 'work' },
      { a: 's2d', b: 'wrk', kind: 'storage' },
      // The container stack stays lit. A clustered VM role recovers on a survivor, which is a
      // proven mechanism here, so the link to the lost host breaks and the machine does not.
      { a: 'arc', b: 'vm', kind: 'control' }, { a: 'h01', b: 'vm', kind: 'control', failed: true },
      { a: 's2d', b: 'vm', kind: 'storage' },
      { a: 'vm', b: 'dkr', kind: 'work' }, { a: 'dkr', b: 'dkg', kind: 'work' }
    ],
    elapsed: 'Both recovered without intervention. Playback compressed.',
    groups: [
      {
        name: 'Delete a healthy pod on purpose', kind: 'orch', status: 'fail', dur: '',
        cmd: 'kubectl delete pod dashboard-zgnwp',
        out: 'pod "dashboard-zgnwp" deleted\ndeployment 2/3 ready'
      },
      {
        name: 'Nobody was asked to fix it', kind: 'orch', status: 'ok', dur: '',
        cmd: 'kubectl get pods -w',
        out: 'dashboard-kjdrh   Running   0 restarts\ndeployment back to 3/3 ready\nEndpointSlice: 3 ready'
      },
      {
        name: 'Node leaves the cluster', kind: 'control', status: 'fail', dur: '0s',
        cmd: 'Get-ClusterNode | Select-Object Name, State',
        out: 'AZL-NODE-01   Down\nAZL-NODE-02   Up\nAZL-NODE-04   Up\nAZL-NODE-06   Up'
      },
      {
        name: 'Pool degrades and repair starts on its own', kind: 'storage', status: 'run', dur: 'about 26m',
        cmd: 'Get-StoragePool; Get-StorageJob',
        out: 'HealthStatus: Warning, virtual disks Warning but still Online\nws2025-core-01 recovered on azl-node-02, guest agent Connected\nNode rejoined after about 26 minutes, all six disks back to Healthy',
        meter: { done: 6, total: 6, label: '6 of 6 virtual disks Healthy' }
      },
      {
        name: 'Was the workload still serving?', kind: 'work', status: 'run', dur: 'UNVERIFIED',
        cmd: 'this claim needs checking before it is made out loud',
        out: 'The node failure test and the AKS workload were separate pieces of work.\nWhether the dashboard was even deployed during the node outage is not\nrecorded anywhere. Do not assert workload continuity until it is.'
      },
      {
        name: 'Neither Azure resource exists here', kind: 'orch', status: 'run', dur: 'ARCHITECTURE',
        cmd: 'az vm availability-set create   |   az vmss create',
        out: 'Both are Azure regional constructs, and neither is a deployment target\non Azure Local. A scale set needs a VNet subnet, a Marketplace image\nreference, a managed disk type and an Azure VM SKU. This platform has\nlogical networks, its own gallery and storage paths on S2D. It also\nforbids cloning a VM outright, which is the one mechanic a scale set is.\n\nThe resource is missing. The outcome is not. Identical instances from\none model, spread across hosts, replaced without losing an endpoint,\nis a Kubernetes Deployment, and the last two movements were it working.\nShape the workload as a Deployment instead of a fleet of VMs and the\ncapability is already on this cluster.'
      }
    ]
  },

  {
    title: 'How much Azure, how much Local?',
    builtSub: 'the honest split, counted rather than claimed',
    sub: 'Everything above was built here and managed from there. This is the line between the two, with real counts on both sides.',
    fid: 'proven',
    kind: 'control',
    kinds: 5,
    show: [],
    edges: [],
    groups: [],
    elapsed: '',
    split: {
      note: 'The left column was declared once and applied by Azure. The right column is a state that had to be reached by hand, one machine at a time, and then held there.',
      cols: [
        {
          cap: 'Azure sees this.',
          stat: '53 items in Resource Group',
          items: [
            'Six Arc enabled servers, two never joined',
            'Four Azure Edge agents on every node',
            'The cluster, the Arc bridge, the custom location',
            'Four storage paths and two logical networks',
            'Six VM images and two virtual machines',
            'Azure Monitor and Defender on rocky-docker-01',
            'The AKS cluster, a key vault, and Log Analytics'
          ]
        },
        {
          cap: 'Azure does not see this.',
          stat: 'Meeting compliance by perfecting the configuration',
          items: [
            'Twelve NVMe, three per machine, three way mirror',
            'Storage presented as plain NVMe, no VMD, no RAID',
            'Carrier slot bifurcated per drive',
            'Port3 to sw1 on 711, Port4 to sw2 on 712',
            'Priority flow control on priority 3, both fabrics',
            'Secure Boot on in User mode, factory keys',
            'Vendor drivers on every adapter, none inbox'
          ]
        }
      ]
    }
  },

  {
    title: 'What was proven',
    builtSub: 'and where this would be worth pointing next',
    sub: 'Every pathway on screen was walked end to end on real hardware. Nothing here is a rendering of an intention.',
    fid: 'proven',
    kind: 'work',
    kinds: 5,
    activeNodes: [],
    inFabric: FABRIC_ALL,
    show: ACTIVE4.concat(['azl', 'arc', 's2d', 'aks', 'wrk', 'vm', 'dep', 'svc', 'p1', 'p2', 'dkr', 'dkg']),
    edges: [
      { a: 'h01', b: 'azl', kind: 'control' }, { a: 'h04', b: 'azl', kind: 'control' },
      { a: 'azl', b: 'arc', kind: 'control' }, { a: 'azl', b: 's2d', kind: 'storage' },
      { a: 'arc', b: 'aks', kind: 'orch' }, { a: 'aks', b: 'wrk', kind: 'orch' },
      { a: 'wrk', b: 'dep', kind: 'orch' }, { a: 'dep', b: 'p1', kind: 'orch' },
      { a: 'dep', b: 'p2', kind: 'orch' },
      { a: 'svc', b: 'p1', kind: 'work' }, { a: 'svc', b: 'p2', kind: 'work' },
      { a: 's2d', b: 'wrk', kind: 'storage' },
      { a: 'arc', b: 'vm', kind: 'control' }, { a: 's2d', b: 'vm', kind: 'storage' },
      { a: 'vm', b: 'dkr', kind: 'work' }, { a: 'dkr', b: 'dkg', kind: 'work' }
    ],
    elapsed: 'a long physical build, then one clean deployment',
    groups: [
      {
        name: 'The platform', kind: 'control', status: 'ok', dur: '2h 13m',
        cmd: 'four machines to a managed cluster',
        out: '54 of 54 deployment steps completed. None failed.\nStorage Spaces Direct, Arc resource bridge, custom location.'
      },
      {
        name: 'Two ways to run a workload', kind: 'work', status: 'ok', dur: 'both',
        cmd: 'Kubernetes, and an ordinary virtual machine',
        out: 'AKS Arc v1.33.5 serving a dashboard, scaled and self-healed.\nDocker CE 29.x and Compose in a Rocky Linux VM, reachable off-box.'
      },
      {
        name: 'Infrastructure that can be read and reversed', kind: 'control', status: 'ok', dur: 'proven',
        cmd: 'terraform plan, apply, destroy',
        out: 'A virtual machine created from a file and removed by the same file.\nFinal plan reported nothing left to destroy.'
      },
      {
        name: 'It survived losing a machine', kind: 'storage', status: 'ok', dur: '2026-08-13',
        cmd: 'a node left the cluster',
        out: 'Pool went Warning. Virtual disks degraded but stayed Online.\nRepair started unprompted. Three way mirror tolerates one node.\nThe node rejoined after about 26 minutes, all six disks Healthy.'
      },
      {
        name: 'It survived being maintained', kind: 'control', status: 'ok', dur: '2026-09-01',
        cmd: 'rolling update, then live migration',
        out: 'Every pod replaced without the Service losing an endpoint.\nThe host under the workload moved to another machine in 16.7s.\nMinimum ready endpoints across both: 2. Pods: 0 restarts.'
      },
      {
        name: 'What this was not', kind: 'net', status: 'fail', dur: 'honest',
        cmd: 'the caveats, stated out loud',
        out: 'Workstation class hardware, not certified for Azure Local.\nTwo of six machines never made the cluster.\nEvery node runs 32 GB, the bare minimum, with nothing spare.\nOne NVMe in machine 01 failed and was retired. It was a spare, capacity was unaffected.\nStorage networking took a rebuild and a rename to get right.\nNo CI pipeline has ever run. EMU blocks GitHub hosted runners.\nNo private registry. Images come from Microsoft Container Registry.\nNo pod anti-affinity and no disruption budget on the dashboard.\nThere is no cluster witness. Four nodes survive one loss, not two.'
      }
    ]
  },

  // Not a movement, so it carries no number, no proof badge and no sub-slide. It sits after the
  // deck rather than inside it, and the numbered count deliberately stops before it.
  {
    title: 'Engineering Credits',
    unnumbered: true,
    sub: '',
    kinds: 5,
    show: [],
    inFabric: [],
    edges: [],
    elapsed: '',
    credits: [
      {
        cap: 'Crafted By',
        lead: true,
        names: [{ n: 'The project engineer' }]
      },
      {
        cap: 'Technology Stack',
        lines: [
          'Built to be modular and tunable.',
          'Web Animations API for the reveals, CSS custom properties and keyframes for the rest.',
          'Git and Visual Studio Code with GitHub Copilot.'
        ]
      },
      {
        cap: 'Design inspiration',
        lines: [
          'Pierre-Louis Labonne\'s web portfolio. A detailed and active entry, tactile modules beyond a continuous page. Progressive reveal amassing interconnected systems.',
          'Layout themes from "Evreghen Command Center". Focused and technical with a splash of color, a dark shell with compact operational density.'
        ]
      },
      { cap: 'Special thanks to', names: ['Colleagues who supported the work'] },
      { cap: 'In-depth network troubleshooting from', names: ['Network engineering colleagues'] }
    ]
  }
];

const M = (function () {
  'use strict';

  const el = (id) => document.getElementById(id);
  const state = { stage: 0 };

  const dom = {
    rail: el('rail'), legend: el('legend'), layers: el('layers'), wires: el('wires'),
    memstick: el('memstick'),
    canvas: el('canvas'), field: el('field'), fabric: el('fabric'), fabricCells: el('fabricCells'),
    log: el('log'), stageNum: el('stageNum'), stageTitle: el('stageTitle'),
    stageSub: el('stageSub'), stageFid: el('stageFid'),
    statStage: el('statStage'), stageElapsed: el('stageElapsed')
  };

  const kindCss = (id) => (KINDS.find((k) => k.id === id) || KINDS[0]).css;

  function buildStatic() {
    KINDS.forEach((k) => {
      const li = document.createElement('li');
      li.dataset.kind = k.id;
      li.style.color = k.css;
      li.innerHTML = '<i></i><span></span>';
      li.querySelector('span').textContent = k.name;
      dom.legend.appendChild(li);
    });

    STAGES.forEach((s, i) => {
      const li = document.createElement('li');
      li.className = 'rail-item' + (s.unnumbered ? ' rail-aside' : '');
      if (!s.unnumbered) li.classList.add('built');
      li.innerHTML = '<span class="rail-num">' +
        (s.unnumbered ? '' : String(i).padStart(2, '0')) +
        '</span><span class="rail-name"></span>';
      li.querySelector('.rail-name').textContent = s.title;
      li.addEventListener('click', () => go(i));
      dom.rail.appendChild(li);
    });

    const total = el('statTotal');
    if (total) total.textContent = String(STAGES.filter((s) => !s.unnumbered).length - 1);

    LAYERS.forEach((layer) => {
      const row = document.createElement('div');
      row.className = 'layer';
      row.dataset.layer = layer.id;
      const tag = document.createElement('span');
      tag.className = 'layer-tag';
      tag.textContent = layer.tag;
      const holder = document.createElement('div');
      holder.className = 'layer-row';
      layer.nodes.forEach((n) => {
        const box = document.createElement('div');
        box.className = 'node';
        box.dataset.id = n.id;
        box.innerHTML =
          '<span class="node-name"></span><span class="node-meta"></span><span class="node-detail"></span>';
        box.querySelector('.node-name').textContent = n.name;
        box.querySelector('.node-meta').textContent = n.meta;
        box.querySelector('.node-detail').textContent = n.detail;
        holder.appendChild(box);
      });
      row.appendChild(tag);
      row.appendChild(holder);
      dom.layers.appendChild(row);
    });

    FABRIC_ALL.forEach((id) => {
      const c = document.createElement('div');
      c.className = 'cell';
      c.dataset.id = id;
      c.innerHTML = '<span class="cell-led"></span><span></span>';
      c.querySelector('span:last-child').textContent =
        id.indexOf('sw') === 0 ? id.toUpperCase().replace('SW', '7050SW') : 'AZLOCAL-' + id.slice(1);
      dom.fabricCells.appendChild(c);
    });
  }

  // Sits in the empty band under the diagram on one movement only. Bands are sized against the
  // used total and the strip is sized against the stick, so the fill can stop part way through a
  // chip instead of rounding to the nearest one.
  function drawMemory(stage) {
    const box = dom.memstick;
    box.hidden = !stage.mem;
    // Leaving the movement arms it again, so coming back replays the fill.
    if (!stage.mem) { box.dataset.filled = ''; return; }

    const used = MEMORY.bands.reduce((s, b) => s + b.mb, 0);
    const gb = (mb) => (mb / 1024).toFixed(1);

    if (!box.dataset.built) {
      const CHIPS = 8;
      const usedPct = (used / MEMORY.totalMB) * 100;

      // The smallest band is under one percent of the stick, which is a few pixels. Give every band
      // a floor and take the difference off the others in proportion, so the shape stays honest at
      // this scale. True sizes are printed in the key.
      const FLOOR = 1.9;
      const raw = MEMORY.bands.map((b) => (b.mb / MEMORY.totalMB) * 100);
      const lifted = raw.map((p) => Math.max(p, FLOOR));
      const debt = lifted.reduce((s, p) => s + p, 0) - usedPct;
      const slack = raw.reduce((s, p, i) => s + (p > FLOOR ? p - FLOOR : 0), 0);
      const shown = raw.map((p, i) => p > FLOOR ? lifted[i] - debt * ((p - FLOOR) / slack) : FLOOR);

      // One gradient across the whole stick. Each chip shows its own eighth of it, so colour runs
      // continuously through the row while the gaps stay real gaps.
      let at = 0;
      const stops = MEMORY.bands.map((b, i) => {
        const from = at; at += shown[i];
        return b.css + ' ' + from.toFixed(3) + '% ' + at.toFixed(3) + '%';
      });
      stops.push('#262d26 ' + at.toFixed(3) + '% 100%');
      const grad = 'linear-gradient(90deg,' + stops.join(',') + ')';

      const chips = [];
      for (let i = 0; i < CHIPS; i++) {
        const span = 100 / CHIPS;
        const local = Math.max(0, Math.min(1, (usedPct - i * span) / span));
        chips.push(
          '<span class="mem-chip"><i class="mem-mask" style="--w:' +
          ((1 - local) * 100).toFixed(3) +
          '%;transition-delay:' + (2000 + i * 260) + 'ms"></i></span>');
      }

      const key = MEMORY.bands.map((b) =>
        '<li><i style="--c:' + b.css + ';background:' + b.css + '"></i><span>' + b.name +
        '</span><b>' + gb(b.mb) + ' GB</b></li>').join('') +
        '<li class="mem-open"><i></i><span>Left for workloads</span><b>' +
        gb(MEMORY.totalMB - used) + ' GB</b></li>';

      box.innerHTML =
        '<p class="mem-cap">An average node spends ' + gb(used) + ' GB of ' +
        Math.round(MEMORY.totalMB / 1024) + ' GB memory, before any meaningful workload.</p>' +
        '<div class="mem-main">' +
          '<div class="mem-dimm">' +
            '<div class="mem-pcb">' +
              '<i class="mem-glow" style="--g:' + grad + ';transition-delay:' +
                (2000 + (CHIPS - 1) * 260 + 900) + 'ms"></i>' +
              '<div class="mem-chips" style="--g:' + grad + '">' + chips.join('') + '</div>' +
            '</div>' +
            '<div class="mem-pins"></div>' +
          '</div>' +
          '<ul class="mem-key">' + key + '</ul>' +
        '</div>';
      box.dataset.built = '1';
    }

    // Only animate on arrival. Re-rendering for any other reason, a resize for instance, must not
    // empty the chips and start the hold again.
    if (box.dataset.filled === '1') return;

    // A transition delay applies to the reset as much as to the run, so setting the start value and
    // forcing a reflow does nothing on a return visit: the reset is itself a delayed transition and
    // never lands, leaving the stick already full. Take the transitions off to seed the start state.
    const masks = box.querySelectorAll('.mem-mask');
    const glow = box.querySelector('.mem-glow');
    box.classList.add('arming');
    masks.forEach((m) => { m.style.width = '100%'; });
    if (glow) glow.style.opacity = '0';
    void box.offsetWidth;
    box.classList.remove('arming');
    masks.forEach((m) => { m.style.width = m.style.getPropertyValue('--w'); });
    if (glow) glow.style.opacity = '';
    box.dataset.filled = '1';
  }

  // A closing frame rather than a movement, so it replaces the layer diagram instead of adding to it.
  function drawSplit(stage) {
    const old = dom.canvas.querySelector('.split');
    if (old) old.remove();
    dom.layers.hidden = !!(stage.split || stage.credits);
    if (!stage.split) return;

    const wrap = document.createElement('div');
    wrap.className = 'split';
    stage.split.cols.forEach((col, i) => {
      const sec = document.createElement('section');
      sec.className = 'split-col';
      sec.style.setProperty('--i', String(i));
      sec.innerHTML =
        '<p class="split-stat"></p><p class="split-cap"></p><ul class="split-list"></ul>';
      sec.querySelector('.split-cap').textContent = col.cap;
      sec.querySelector('.split-stat').textContent = col.stat;
      const ul = sec.querySelector('.split-list');
      col.items.forEach((t) => {
        const li = document.createElement('li');
        li.textContent = t;
        ul.appendChild(li);
      });
      wrap.appendChild(sec);
    });
    if (stage.split.note) {
      const n = document.createElement('p');
      n.className = 'split-note';
      n.textContent = stage.split.note;
      wrap.appendChild(n);
    }
    dom.canvas.appendChild(wrap);
  }

  function drawCredits(stage) {
    const old = dom.canvas.querySelector('.creds');
    if (old) old.remove();
    if (!stage.credits) return;

    const wrap = document.createElement('div');
    wrap.className = 'creds';
    stage.credits.forEach((block, i) => {
      const sec = document.createElement('section');
      sec.className = 'creds-block';
      sec.style.setProperty('--i', String(i));
      const cap = document.createElement('p');
      cap.className = 'creds-cap';
      cap.textContent = block.cap;
      sec.appendChild(cap);
      (block.names || []).forEach((entry) => {
        const name = typeof entry === 'string' ? { n: entry } : entry;
        const p = document.createElement('p');
        p.className = 'creds-name' + (block.lead ? ' lead' : '');
        p.innerHTML = '<span></span><span class="creds-email"></span>';
        p.children[0].textContent = name.n;
        p.children[1].textContent = name.email || '';
        sec.appendChild(p);
      });
      (block.lines || []).forEach((t) => {
        const p = document.createElement('p');
        p.className = 'creds-line';
        p.textContent = t;
        sec.appendChild(p);
      });
      wrap.appendChild(sec);
    });
    dom.canvas.appendChild(wrap);
  }

  function anchor(id) {    if (!dom.fabric.hidden) {
      const cell = dom.fabricCells.querySelector('.cell[data-id="' + id + '"]');
      if (cell && cell.style.display !== 'none') return cell;
    }
    return dom.layers.querySelector('.node[data-id="' + id + '"]');
  }

  // Direction is not meaningful for an edge, so normalise the pair before comparing movements.
  function edgeKey(e) {
    return [e.a, e.b].sort().join('>') + ':' + e.kind;
  }

  // What this movement added that the previous one did not have.
  function freshEdges(i) {
    const set = {};
    if (i <= 0) return set;
    const prev = {};
    (STAGES[i - 1].edges || []).forEach((e) => { prev[edgeKey(e)] = true; });
    const all = STAGES[i].edges || [];
    let n = 0;
    all.forEach((e) => {
      const k = edgeKey(e);
      if (!prev[k]) { set[k] = true; n += 1; }
    });
    // If every edge is new the picture was replaced rather than extended, and marking all of it
    // says nothing. Movement 02 does exactly that when the fabric forms.
    return n === all.length ? {} : set;
  }

  function drawWires(stage) {
    dom.wires.innerHTML = '';
    const fresh = freshEdges(state.stage);
    const box = window.FIT.rect(dom.field);
    stage.edges.forEach((e) => {
      const a = anchor(e.a);
      const b = anchor(e.b);
      if (!a || !b || a.offsetParent === null || b.offsetParent === null) return;
      const ra = window.FIT.rect(a);
      const rb = window.FIT.rect(b);
      const x1 = ra.left + ra.width / 2 - box.left;
      const y1 = ra.top + ra.height / 2 - box.top;
      const x2 = rb.left + rb.width / 2 - box.left;
      const y2 = rb.top + rb.height / 2 - box.top;

      const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');

      // Peers on the same row would draw as a straight line hidden behind the boxes, so a mesh
      // between them has to bow out to be seen at all. Alternate the bow to spread the bundle.
      if (Math.abs(y2 - y1) < 24) {
        const span = Math.abs(x2 - x1);
        const dir = (stage.edges.indexOf(e) % 2) ? 1 : -1;
        const lift = dir * Math.min(96, 26 + span * 0.22);
        const my = (y1 + y2) / 2 + lift;
        p.setAttribute('d', 'M' + x1 + ',' + y1 + ' Q' + ((x1 + x2) / 2) + ',' + my + ' ' + x2 + ',' + y2);
      } else {
        const my = (y1 + y2) / 2;
        p.setAttribute('d', 'M' + x1 + ',' + y1 + ' C' + x1 + ',' + my + ' ' + x2 + ',' + my + ' ' + x2 + ',' + y2);
      }

      // Three tiers. Same-kind edges rest at mid so the current event still stands out
      // from a field of its own colour, which is what the monochrome opening needs.
      const hot = (stage.activeNodes || []).indexOf(e.a) !== -1 || (stage.activeNodes || []).indexOf(e.b) !== -1;
      let tier = 'rest-other';
      if (e.failed) tier = 'failed';
      else if (e.kind === stage.kind && hot) tier = 'active';
      else if (e.kind === stage.kind) tier = 'rest-same';

      p.setAttribute('class', 'wire ' + tier);
      p.style.stroke = kindCss(e.kind);
      p.style.color = kindCss(e.kind);
      dom.wires.appendChild(p);

      // Connections grow rather than appear, so the system reads as knitting together.
      const len = p.getTotalLength();
      p.style.setProperty('--len', len);
      p.style.strokeDasharray = len;
      p.classList.add('grow');

      // Light travels the active lines. Motion carries status; hue stays the kind.
      if (tier === 'active') {
        const q = p.cloneNode();
        q.setAttribute('class', 'pulse');
        q.style.stroke = kindCss(e.kind);
        q.style.setProperty('--len', len);
        q.style.strokeDasharray = (len * 0.16) + ' ' + len;
        q.style.animationDelay = (Math.random() * 1.2).toFixed(2) + 's';
        dom.wires.appendChild(q);
      }

      // Anything this movement introduced breathes, as an overlay rather than on the wire itself,
      // so it cannot fight the grow animation or the tier opacities.
      if (fresh[edgeKey(e)]) {
        const f = p.cloneNode();
        f.setAttribute('class', 'wire-new');
        f.style.stroke = kindCss(e.kind);
        f.style.color = kindCss(e.kind);
        f.style.strokeDasharray = 'none';
        f.style.strokeDashoffset = '0';
        f.style.animationDelay = (Math.random() * 1.8).toFixed(2) + 's';
        dom.wires.appendChild(f);
      }
    });
  }

  function render() {
    const stage = STAGES[state.stage];

    dom.stageNum.textContent = stage.unnumbered ? '' : 'Movement ' + String(state.stage).padStart(2, '0');
    dom.stageTitle.textContent = stage.title;
    dom.stageSub.textContent = stage.sub;
    // Provenance is stated in the closing movement, so the per-frame stamp only added noise.
    dom.stageFid.textContent = '';
    dom.stageFid.hidden = true;
    dom.statStage.textContent = stage.unnumbered ? '-' : String(state.stage);
    // Reads as the next sentence of the subtitle, so it needs a capital and a full stop.
    const el = stage.elapsed || '';
    dom.stageElapsed.textContent = el
      ? el.charAt(0).toUpperCase() + el.slice(1) + (/[.!?]$/.test(el) ? '' : '.')
      : '';

    Array.from(dom.rail.children).forEach((li, i) => {
      li.classList.toggle('on', i === state.stage);
      li.classList.toggle('done', i < state.stage);
    });

    Array.from(dom.legend.children).forEach((li, i) => li.classList.toggle('on', i < stage.kinds));

    const inFabric = stage.inFabric || [];
    dom.fabric.hidden = !inFabric.length;

    drawMemory(stage);

    dom.layers.querySelectorAll('.node').forEach((n) => {
      const id = n.dataset.id;
      n.classList.toggle('on', stage.show.indexOf(id) !== -1);
      n.classList.toggle('detail', !!stage.detailNodes);
      n.classList.toggle('out', (stage.out || []).indexOf(id) !== -1);
    });

    // A row goes away once everything still live in it has moved to the margin, or once nothing
    // in it is on at all. Machines that fell out do not keep the row alive.
    dom.layers.querySelectorAll('.layer').forEach((row) => {
      const live = Array.from(row.querySelectorAll('.node.on'));
      const demoted = live.length && live.every((n) => inFabric.indexOf(n.dataset.id) !== -1);
      row.hidden = demoted || !live.length;
    });

    dom.fabricCells.querySelectorAll('.cell').forEach((c) => {
      const num = c.dataset.id.slice(1);
      c.style.display = inFabric.indexOf(c.dataset.id) !== -1 ? '' : 'none';
      c.classList.toggle('busy', (stage.busy || []).indexOf(num) !== -1);
      c.classList.toggle('down', (stage.down || []).indexOf(num) !== -1);
      c.classList.toggle('repairing', (stage.repairing || []).indexOf(num) !== -1 && (stage.down || []).indexOf(num) === -1);
    });

    // stage.groups is still the source for the cutaway's right pane. Only the rendering moved.
    drawSplit(stage);
    drawCredits(stage);

    if (window.CRIT) window.CRIT.show(state.stage);

    // Draw now so the frame is correct even when the window is not focused, since a hidden tab
    // never fires requestAnimationFrame. The second pass corrects for any late layout.
    drawWires(stage);
    window.requestAnimationFrame(() => drawWires(stage));
  }

  function go(i) {
    state.stage = Math.max(0, Math.min(i, STAGES.length - 1));
    if (window.BUILT && window.BUILT.isOpen()) window.BUILT.hide();
    // Nothing sits underneath the credits, so the gear drops rather than waiting to be shifted.
    if (window.BUILT && STAGES[state.stage].unnumbered) window.BUILT.setArmed(false);
    render();
  }

  buildStatic();

  // Motes carry the colour of the kinds that are online, weighted toward the newest one,
  // so ambient activity reports the arc without ever asserting a fact.
  const motes = el('motes');
  window.setInterval(() => {
    const stage = STAGES[state.stage];
    const live = KINDS.slice(0, stage.kinds);
    if (!live.length || document.hidden) return;
    // The credits have no diagram to compete with, so the ambient layer doubles and carries the frame.
    const burst = stage.unnumbered ? 2 : 1;
    for (let k = 0; k < burst; k += 1) {
      const pick = Math.random() < 0.45 ? live[live.length - 1] : live[Math.floor(Math.random() * live.length)];
      const m = document.createElement('div');
      m.className = 'mote';
      m.style.color = pick.css;
      m.style.left = (Math.random() * 100).toFixed(2) + '%';
      m.style.top = (72 + Math.random() * 26).toFixed(2) + '%';
      m.style.setProperty('--dx', (Math.random() * 90 - 45).toFixed(0) + 'px');
      m.style.setProperty('--dur', (11 + Math.random() * 9).toFixed(1) + 's');
      m.style.setProperty('--peak', (0.28 + Math.random() * 0.4).toFixed(2));
      motes.appendChild(m);
      window.setTimeout(() => m.remove(), 21000);
    }
  }, 340);

  // Next is not always advance. BUILT gets first refusal so it can stop on a sub-slide.
  function next() {
    if (window.BUILT && window.BUILT.interceptNext(state.stage)) return;
    go(state.stage + 1);
  }

  el('btnNext').addEventListener('click', next);
  el('btnBack').addEventListener('click', () => go(state.stage - 1));
  el('btnReset').addEventListener('click', () => go(0));

  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT') return;
    if (e.key === 'ArrowRight') next();
    if (e.key === 'ArrowLeft') go(state.stage - 1);
  });

  let rt = null;
  window.addEventListener('resize', () => {
    window.clearTimeout(rt);
    rt = window.setTimeout(() => drawWires(STAGES[state.stage]), 150);
  });

  render();
  return {
    go, render,
    stage: () => state.stage,
    count: () => STAGES.length,
    stageData: (i) => STAGES[i]
  };
})();

window.M = M;
