/*
 * Azure Local track.
 *
 * Mostly sourced from this repo rather than vendor documentation, because these are the things the
 * project actually taught, including several that only became clear by getting them wrong first.
 */

window.DECK = (window.DECK || []).concat([

  /* ---------- basic ---------- */

  {
    id: 'al-what', track: 'azure-local', level: 'basic',
    q: 'What is Azure Local?',
    say: [
      'Microsoft hardware platform for running Azure services on your own servers, in your own building.',
      'It was called Azure Stack HCI before it was renamed.',
      'You get a cluster of machines with pooled storage, and you manage it from the Azure portal like any other resource.'
    ],
    why: 'The short version is Azure control plane, your hardware. The workloads run locally and the management, identity and inventory come from Azure.',
    ours: 'Four machines in a lab, one cluster, registered into an Azure subscription and visible in the portal.',
    src: 'README.md'
  },
  {
    id: 'al-why', track: 'azure-local', level: 'basic',
    q: 'Why would anyone run Azure Local instead of just using Azure?',
    say: [
      'The work has to be near something physical, like instruments or test equipment.',
      'Data cannot leave the building, for residency or egress reasons.',
      'The hardware is already bought and racked, and otherwise underused.',
      'You want Azure tooling and Azure identity without the workload leaving.'
    ],
    why: 'The honest pitch is not that it is cheaper or faster. It is that hardware you already own stops being a separate world with separate tooling.',
    ours: 'This was a proof that the platform works on leftover lab hardware, not a business case for any particular workload.',
    src: 'capstone/presentation-extras.md'
  },
  {
    id: 'al-s2d', track: 'azure-local', level: 'basic',
    q: 'What is Storage Spaces Direct?',
    say: [
      'It pools the local drives from every machine in the cluster into one software defined pool.',
      'Virtual disks are carved out of that pool and are visible to every node.',
      'Copies of data are spread across machines, so losing a machine does not lose the data.'
    ],
    why: 'This is what makes the cluster a cluster rather than four servers. Because storage is shared, a VM can run on any node, which is what live migration and failover depend on.',
    ours: 'Twelve drives, three per machine across four machines, in one pool called SU1_Pool.',
    src: 'https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-direct-overview',
    diagram:
      '   node 01     node 02     node 04     node 06\n' +
      '   [d][d][d]   [d][d][d]   [d][d][d]   [d][d][d]\n' +
      '      \\           |           |           /\n' +
      '       +----------+-----------+----------+\n' +
      '                       |\n' +
      '               one storage pool\n' +
      '                       |\n' +
      '          virtual disks, mirrored across nodes\n' +
      '                       |\n' +
      '        every node can see every virtual disk\n' +
      '        which is why a VM can run anywhere'
  },
  {
    id: 'al-cluster-vm', track: 'azure-local', level: 'basic',
    q: 'What is a clustered VM role?',
    say: [
      'A VM that the cluster owns rather than one node owning it.',
      'One node runs it at a time, and that node is called the owner.',
      'If the owner is lost, the cluster starts it on a survivor. If you want to move it deliberately, you migrate it.'
    ],
    why: 'This is the mechanism behind most of the resiliency story. You do not configure high availability per VM, you get it because the cluster is holding the VM rather than a single machine.',
    ours: 'Everything we ran is a clustered VM role. When we started the Docker VM it came up on a different node than the one that owned it while it was off.',
    src: 'docs/runbooks/ws2025-azure-local-demo-quickref.md'
  },
  {
    id: 'al-arc', track: 'azure-local', level: 'basic',
    q: 'What is Azure Arc?',
    say: [
      'A way to project things that are not in Azure into Azure, so they appear as ARM resources.',
      'An Arc enabled server is a machine anywhere with an agent, that shows up in the portal.',
      'Once it is a resource you can use Azure RBAC, policy, tags, inventory and extensions on it.'
    ],
    why: 'Arc is the bridge that makes the whole idea work. Without it, hardware in your building is invisible to every Azure tool. With it, it is just another resource with an id.',
    ours: 'Each server was registered with Arc before the cluster could be deployed. Nodes 03 and 05 are absent from that list because they never made it into the build.',
    src: 'docs/planning/original-poc-acceptance-criteria.md'
  },

  /* ---------- foundation ---------- */

  {
    id: 'al-stack', track: 'azure-local', level: 'foundation',
    q: 'Walk me up the stack. What sits on what?',
    say: [
      'Physical machines and two storage fabrics at the bottom.',
      'A failover cluster across them, with Storage Spaces Direct pooling the drives.',
      'The Arc Resource Bridge on top of that, which is itself a VM, projecting the cluster into Azure.',
      'A custom location, which is the thing Azure resources target.',
      'Then the workloads: Arc VMs and an AKS cluster, and containers inside those.'
    ],
    why: 'Being able to walk this in order is the single most useful thing to have straight, because almost every other question is somewhere on this ladder.',
    ours: 'Every layer of this exists in our lab and each one is a movement in the deck.',
    src: 'docs/POC-deployment-summary.md',
    diagram:
      '   containers            docker / kubernetes pods\n' +
      '        |\n' +
      '   workloads             Arc VMs, AKS cluster\n' +
      '        |\n' +
      '   custom location       what Azure resources target\n' +
      '        |\n' +
      '   Arc Resource Bridge   a VM that projects the cluster into ARM\n' +
      '        |\n' +
      '   failover cluster      + Storage Spaces Direct pool\n' +
      '        |\n' +
      '   four machines         two storage fabrics, one mgmt network\n' +
      '\n' +
      '   everything above the cluster line is software.\n' +
      '   everything below it is cables, and it took two months.'
  },
  {
    id: 'al-arb', track: 'azure-local', level: 'foundation',
    q: 'What is the Arc Resource Bridge and what is a custom location?',
    say: [
      'The resource bridge is a management VM running on the cluster that lets Azure create and manage things there.',
      'A custom location is the ARM target you point at. It names a place that is not an Azure region.',
      'When you create a VM or an AKS cluster on Azure Local, you give it the custom location instead of a region.'
    ],
    why: 'This is the trick that makes on premises resources look like Azure resources. The custom location is the address, the resource bridge is the thing that receives the instruction and acts on it locally.',
    ours: 'Deploying the resource bridge was step 40 of 54 and took about 64 minutes, the longest single step in the deployment.',
    src: 'docs/POC-deployment-summary.md'
  },
  {
    id: 'al-fabrics', track: 'azure-local', level: 'foundation',
    q: 'Why does a node have more than one network?',
    say: [
      'Management traffic, which is how you and Azure reach the machine.',
      'Storage traffic, which is how the nodes keep the shared pool in sync, and which is the heavy one.',
      'There are two separate storage fabrics on separate switches and VLANs, so losing one switch does not stop storage.',
      'Compute traffic for the workloads themselves.'
    ],
    why: 'The storage network is not a convenience. Every write may have to reach copies on other machines before it is acknowledged, so if that path is wrong or slow, everything above it is wrong or slow.',
    ours: 'This is where two months went. Three of four machines had their two storage ports cabled to the wrong fabrics.',
    src: 'docs/network/storage-switch-config.md'
  },
  {
    id: 'al-degraded', track: 'azure-local', level: 'foundation',
    q: 'What does degraded but online actually mean?',
    say: [
      'The data is still there and still being served, but it is holding fewer copies than it should.',
      'A three way mirror that loses one copy still has two. You can read and write, and you have less protection than you signed up for.',
      'Repair jobs start on their own to rebuild the missing copies.'
    ],
    why: 'Degraded is not down, and the distinction is the whole point of the design. It also explains why the platform gets protective, because a degraded volume is one more failure away from real loss.',
    ours: 'When a node left, six virtual disks went Degraded, all stayed Online, and three repair jobs started that nobody asked for.',
    src: 'docs/runbooks/node01-retired-nvme-recovery.md'
  },

  /* ---------- working ---------- */

  {
    id: 'al-deploy', track: 'azure-local', level: 'working',
    q: 'How does an Azure Local cluster actually get deployed?',
    say: [
      'Every server is imaged, put on the network, and registered with Arc first.',
      'You fill in a deployment definition covering identity, networking, storage and security.',
      'An orchestrator then runs the build as a long sequence of steps, creating the cluster, configuring the network, setting up storage, applying security, and deploying Arc.',
      'It is one operation you watch, not a set of commands you run.'
    ],
    why: 'The important part is that the network and Active Directory prerequisites are decided before it starts. The orchestrator validates them and will refuse rather than working around a wrong answer.',
    ours: '54 steps, 2 hours 13 minutes, all reporting Success on the run that worked. Getting to a state where that run could succeed took two months.',
    src: 'docs/POC-deployment-summary.md'
  },
  {
    id: 'al-livemigrate', track: 'azure-local', level: 'working',
    q: 'What happens during a live migration?',
    say: [
      'The VM keeps running while its memory is copied to the target node.',
      'The virtual disks are not copied, because they are on shared cluster storage that both nodes can already see.',
      'At the end, ownership switches and the VM continues on the new node.',
      'The pause is brief enough that a running workload does not notice.'
    ],
    why: 'Shared storage is why it is fast. The only thing that has to move is memory and device state, so the time depends on how much memory is changing, not on how big the disks are.',
    ours: 'We moved the VM hosting both Kubernetes pods to another node. 16.7 seconds, 34 API samples, the minimum ready endpoints stayed at 2, and the pods logged zero restarts.',
    src: 'docs/runbooks/ws2025-azure-local-demo-quickref.md'
  },
  {
    id: 'al-cau', track: 'azure-local', level: 'working',
    q: 'How do you patch the hosts without taking workloads down?',
    say: [
      'Cluster-Aware Updating does it one node at a time.',
      'For each node it moves the workloads off, patches, reboots, brings it back and waits for storage to resync, then moves to the next.',
      'It will not start on the next node until the cluster is healthy again.'
    ],
    why: 'This is the same mechanism as a Kubernetes rolling update, one layer down. Both work by making sure something else is serving before taking a thing away.',
    ours: 'Our live migration test is one node of that cycle done by hand, which is why we can say what the patching story looks like without having run a full update.',
    src: 'capstone/prototype/shared/runs.js'
  },
  {
    id: 'al-refusal', track: 'azure-local', level: 'working',
    q: 'The platform refused to let you reboot a node. Why?',
    say: [
      'A virtual disk was missing one of its copies, so the cluster was already down one level of protection.',
      'Pausing that node would have removed another, so it declined. Including the forced version.',
      'It has no way to know a lab from production, so it assumes the data matters.'
    ],
    why: 'A system refusing an operator is usually a good sign. It was protecting the data from a person who was certain he knew better, and it was right.',
    ours: 'Four refusals in one evening. The eventual fix was to leave the cluster deliberately rather than ask permission to pause, and a repair that had been stuck for ten days finished on its own after the restart.',
    src: 'docs/runbooks/node01-retired-nvme-recovery.md'
  },
  {
    id: 'al-vm-ops', track: 'azure-local', level: 'working',
    q: 'What can and cannot you do with a VM on Azure Local?',
    say: [
      'You can create, start, stop, resize, live migrate and manage them through Azure like other Arc VMs.',
      'You cannot clone or copy one. Microsoft documents that as unsupported and warns it can corrupt the VM.',
      'There is no VM Scale Set and no Availability Set. Those are Azure region constructs.'
    ],
    why: 'The no cloning rule is the one that surprises people, because it is the obvious way you would try to make a fleet by hand. The supported path to repeatable machines is images and infrastructure as code.',
    ours: 'This is why our answer to the scale set question is Terraform for repeatable build rather than a workaround that copies a machine.',
    src: 'docs/planning/azure-local-platform-boundary-research.md'
  },
  {
    id: 'al-aks', track: 'azure-local', level: 'working',
    q: 'What is AKS on Azure Local, and how is it different from AKS in the cloud?',
    say: [
      'It is managed Kubernetes where the control plane and nodes are VMs on your cluster instead of in a region.',
      'You create it against the custom location, and manage it through Azure.',
      'The nodes are real VMs you can see in the cluster, which is why one of them can be live migrated.',
      'Some things that come free in the cloud, like an external load balancer address, need extra components here.'
    ],
    why: 'The useful mental model is that AKS Arc is Kubernetes with the same API and a different floor. Everything above the node is identical. Everything below it is yours.',
    ours: 'One control plane node and one worker, both Azure Linux, both clustered VMs on Azure Local. Moving the worker between hosts is a thing you simply cannot do in the cloud.',
    src: 'docs/planning/azure-local-platform-boundary-research.md'
  },
  {
    id: 'al-identity', track: 'azure-local', level: 'working',
    q: 'What identity does an Azure Local deployment need?',
    say: [
      'It is domain joined, so it needs Active Directory prepared in advance with a dedicated organisational unit.',
      'A deployment account is created for lifecycle management and needs rights most service accounts would not get, including interactive logon.',
      'Separately, the Azure side needs specific roles on the subscription and resource group before anything can be registered.'
    ],
    why: 'Two identity systems at once is the thing to hold on to. The cluster is a Windows domain member and an Azure resource, and both sets of permissions have to be right before the deployment starts.',
    ours: 'Our nodes are domain joined to a lab domain, done as step 16 of the deployment. The interactive logon requirement is a documented deviation from normal policy, with the Microsoft citation recorded next to it.',
    src: 'docs/access/security-posture-and-boundaries.md'
  },

  /* ---------- deeper ---------- */

  {
    id: 'al-sconfig', track: 'azure-local', level: 'pressed',
    q: 'If updating breaks it, why does the setup tool offer to install updates at all?',
    say: [
      'Because that tool is not an Azure Local wizard. SConfig is the generic Windows Server Core configuration tool.',
      'The Azure Local OS is a Server Core edition, so it inherits SConfig unchanged, update option included.',
      'For an ordinary Server Core box, updating at setup is the correct thing to do. SConfig has no idea it is sitting on a node with a stricter contract.',
      'The platform does not run updates on its own. Windows Update is set to Manual and stopped. SConfig will happily start it.'
    ],
    why: 'It is not a dangerous option deliberately placed in a deployment flow. It is generic tooling meeting a platform that added a requirement the tooling predates. Worth recognising as a pattern, because anything inherited from the base OS is likely to be unaware of the platform on top of it.',
    ours: 'Node 01 reports ProductName Azure Stack HCI, EditionID ServerAzureStackHCICor, build 26100 UBR 32690. SConfig comes from Microsoft.ServerCore.SConfig and C:\\Windows\\System32\\sconfig.cmd, the same files as any Server Core install.',
    src: 'docs/decisions/0009-node01-iso-recipe-lcu-skew.md'
  },
  {
    id: 'al-recover-update', track: 'azure-local', level: 'pressed',
    q: 'If somebody does update a node by mistake, is it ruined?',
    say: [
      'No. It is a divergence to reconcile, not a destroyed machine.',
      'One route is backwards: uninstall the superseding rollups so the recipe updates are the current ones again.',
      'The other is forwards: point the bootstrap at a solution version that matches the patched build, which is what the TargetSolutionVersion parameter is for.',
      'Reimaging is always available and is sometimes simply faster than either.'
    ],
    why: 'The guidance is do not update because staying on the recipe is far cheaper than chasing alignment afterwards, not because recovery is impossible. Knowing both exits is the difference between a delay and a panic.',
    ours: 'We did all three across different nodes. Rollups were uninstalled to surface the recipe updates, one node needed the exact catalog MSU fetched by hand, and several nodes were reimaged for unrelated reasons anyway.',
    src: 'docs/decisions/0009-node01-iso-recipe-lcu-skew.md'
  },
  {
    id: 'al-rdma', track: 'azure-local', level: 'pressed',
    q: 'Why does the storage network use RDMA?',
    say: [
      'RDMA lets one machine read and write another machine memory without going through the CPU on either end.',
      'That matters because storage traffic in this design is constant and latency sensitive.',
      'It needs the network to be lossless, which is configured with priority flow control on both the adapters and the switches.'
    ],
    why: 'The lossless requirement is why the switch configuration is not optional. RDMA assumes packets are not dropped, so an ordinary best effort network turns it into something much worse than plain TCP.',
    ours: 'Network ATC applied the configuration and RDMA with priority flow control on priority 3 negotiated cleanly, at step 17 of the deployment.',
    src: 'docs/POC-deployment-summary.md'
  },
  {
    id: 'al-vlan-lesson', track: 'azure-local', level: 'pressed',
    q: 'What went wrong with the cabling, and how was it found?',
    say: [
      'Three of four machines had their two storage ports connected to the opposite fabrics from what the configuration assumed.',
      'Every east west storage connectivity test failed, in both directions, on both VLANs.',
      'It was found by capturing LLDP, which is how a switch announces itself, and mapping which port actually reached which switch.',
      'The cables were never wrong. Windows had enumerated the two ports on the card in the opposite order.'
    ],
    why: 'The good lesson is that the evidence pointed at the network and the cause was naming. The fix was renaming the adapters to match reality rather than recabling anything.',
    ours: 'After the rename, all six connectivity checks passed on all four machines and the deployment could proceed.',
    src: 'docs/network/storage-switch-config.md'
  },
  {
    id: 'al-storage-not-blob', track: 'azure-local', level: 'pressed',
    q: 'You have Storage Spaces Direct. Is that Azure Storage?',
    say: [
      'No. They are different layers with a similar sounding name.',
      'S2D is cluster block storage. It is the disk underneath the VMs and the Kubernetes nodes.',
      'Azure Blob, Queue and Table are service APIs reached through a storage account, and there is no storage account resource on Azure Local.',
      'Wanting Blob storage locally is an application decision: use the cloud service, use an emulator, or pick a local component.'
    ],
    why: 'Both halves of this are documented by Microsoft in their own words, which is what makes it a finding rather than an opinion. The original requirement combined the two layers.',
    ours: 'Marked as an architecture finding rather than a deferral, because the thing asked for does not exist to be deferred.',
    src: 'docs/planning/azure-local-platform-boundary-research.md'
  },
  {
    id: 'al-limits', track: 'azure-local', level: 'pressed',
    q: 'What are the real limits of what you built?',
    say: [
      'One site, one rack, one power domain. No disaster recovery story at all.',
      'Four nodes, so capacity is fixed. It cannot absorb a spike the way a region can.',
      'One Kubernetes worker node, so the container workload survives maintenance and not the loss of that node.',
      'Somebody has to own the physical estate. This project lost two machines before it started and a drive during it.'
    ],
    why: 'Worth being able to say plainly and without apology. A proof of concept that names its limits is more useful than one that implies it has none.',
    ours: 'All of these are written into the deck rather than left to be discovered.',
    src: 'capstone/presentation-extras.md'
  },
  {
    id: 'al-updates', track: 'azure-local', level: 'working',
    q: 'What is the update mechanism after setup? What patches the Windows underneath?',
    say: [
      'The platform is versioned as a whole. Operating system, drivers, firmware, agents and platform services move together as one validated solution version.',
      'You apply a solution update, and it rolls through the cluster one node at a time, draining and rebooting each, checking health before it moves on.',
      'Firmware and drivers arrive in the same bundle, through the hardware vendor solution builder extension.',
      'Guest VMs and containers are not covered by it. Those stay your problem, through Azure Update Manager or by rebuilding images.'
    ],
    why: 'The unit is a validated platform version rather than a set of individual patches you choose between. Microsoft tests the whole combination against certified hardware, and that is what makes an unattended node by node update safe enough to run without watching it.',
    ours: 'Node 01 reports solution version 12.2604.1003.1006 and state UpdateAvailable, with a 2026.08 Cumulative Update at 12.2608.1003.9 sitting Ready and unapplied. OemVersion 2.1.0.0 is the Dell extension. Installing hardware updates through it was step 36 of the original deployment, before the cluster ever carried a workload.',
    src: 'docs/POC-deployment-summary.md'
  },
  {
    id: 'al-winupdate', track: 'azure-local', level: 'working',
    q: 'Can you just run Windows Update on an Azure Local node?',
    say: [
      'Not during setup, no, and doing it breaks the deployment.',
      'A node has to match a signed OS image recipe. Public Windows Update, including SConfig option 6, pushes it past that point.',
      'The symptom is an image recipe validation failure during Arc bootstrap, complaining that the latest cumulative update does not match the recipe.',
      'The node still gets patched, just not by you and not then. After deployment the platform owns it, through the Azure Local solution channel.'
    ],
    why: 'The distinction is which mechanism, not whether to patch. Both are called an update. The public channel is a moving train of individual KBs, and a cumulative rollup supersedes the exact ones the recipe pins. The solution channel delivers a validated version instead, which is the only one this platform accepts.',
    ours: 'We learned this expensively. SConfig Install updates pushed nodes past the recipe and Arc bootstrap failed. Recovery meant uninstalling the superseding rollups to surface the recipe updates again, and on one node downloading the exact catalog MSU by hand. Some of the drift was not even deliberate: nodes were updating themselves in the background before anyone touched them.',
    src: 'docs/decisions/0009-node01-iso-recipe-lcu-skew.md'
  }
]);
