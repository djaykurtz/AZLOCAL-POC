/*
 * Narrative script for the Azure Local capstone vision prototype.
 *
 * This file is the story. Edit it to change the presentation without touching the playback engine.
 *
 * fid: "proven"    -> the numbers shown came from a recorded run on the real POC cluster
 *      "story"     -> concept content for review, not yet demonstrated
 */

const ARCH_LAYERS = [
  {
    tag: 'Hardware',
    nodes: [
      { id: 'h1', name: 'AZL-NODE-01', meta: '31.5 GiB', detail: '10.10.1.187' },
      { id: 'h2', name: 'AZL-NODE-02', meta: '31.5 GiB', detail: '10.10.1.188' },
      { id: 'h4', name: 'AZL-NODE-04', meta: '31.5 GiB', detail: '10.10.1.190' },
      { id: 'h6', name: 'AZL-NODE-06', meta: 'infra host', detail: '10.10.1.192' }
    ]
  },
  {
    tag: 'Platform',
    nodes: [
      { id: 'azl', name: 'Azure Local', meta: '24H2 cluster', detail: 'AZL-CLUSTER-01' },
      { id: 'arc', name: 'Arc Resource Bridge', meta: 'control plane', detail: 'azl-cluster-01-cl' },
      { id: 's2d', name: 'Storage Spaces Direct', meta: '3-way mirror', detail: 'UserStorage 1-4' }
    ]
  },
  {
    tag: 'Delivery',
    nodes: [
      { id: 'src', name: 'Source', meta: 'git repository', detail: 'commit 8c41f2e' },
      { id: 'ci', name: 'GitHub Actions', meta: 'validate', detail: 'validate.yml' },
      { id: 'tf', name: 'Terraform', meta: 'plan and apply', detail: 'azlocal-disposable-vm' }
    ]
  },
  {
    tag: 'Runtime',
    nodes: [
      { id: 'vm', name: 'Appliance VM', meta: 'purpose-built image', detail: 'kiosk console' },
      { id: 'aks', name: 'AKS Arc', meta: 'v1.33.5', detail: 'azl-cluster-01-aks-01' },
      { id: 'wrk', name: 'Worker node', meta: 'Azure Linux', detail: 'Ready' },
      { id: 'tfvm', name: 'tf-poc-linux-01', meta: 'Terraform owned', detail: 'on AZL-NODE-04' }
    ]
  },
  {
    tag: 'Application',
    nodes: [
      { id: 'img', name: 'Container image', meta: 'versioned', detail: 'v1.4.0' },
      { id: 'dep', name: 'Deployment', meta: 'desired state', detail: 'azure-local-dashboard' },
      { id: 'svc', name: 'Service', meta: 'ClusterIP', detail: '10.30.1.58' },
      { id: 'p1', name: 'Pod', meta: 'replica 1', detail: '10.244.51.90' },
      { id: 'p2', name: 'Pod', meta: 'replica 2', detail: '10.244.51.91' },
      { id: 'p3', name: 'Pod', meta: 'replica 3', detail: '10.244.51.92' }
    ]
  }
];

const SCENARIO = [
  {
    id: 'boot',
    title: 'Cold start',
    fid: 'story',
    exec: 'We start from nothing. <strong>Four servers in a lab rack</strong> and an empty screen. Everything you are about to see gets built in front of you.',
    prompt: 'power on the appliance',
    arch: [],
    hot: [],
    pods: 0,
    mods: [],
    detail: [
      { cap: 'The question', body: 'Can we run a modern cloud-native delivery stack on hardware we own, managed the same way we manage Azure?' },
      { cap: 'What follows', body: 'Eight stages. Each one adds a capability, shows the proof, and states the limit.' }
    ],
    stream: [
      { t: 200,  src: 'appliance', msg: 'firmware handoff, Secure Boot enabled', tone: 'info' },
      { t: 900,  src: 'appliance', msg: 'purpose-built image booting', tone: 'info' },
      { t: 1700, src: 'console',   msg: 'display attached, no workloads present', tone: 'info' }
    ],
    dwell: 1400
  },

  {
    id: 'platform',
    title: 'Your hardware, the Azure control plane',
    fid: 'proven',
    exec: 'Four physical servers became a <strong>single Azure-managed system</strong>. The hardware sits in our building. The management experience is Azure.',
    prompt: 'show me the platform',
    arch: ['h1', 'h2', 'h4', 'h6', 'azl', 'arc', 's2d'],
    hot: ['azl'],
    pods: 0,
    mods: [
      {
        id: 'm-cluster',
        title: 'Azure Local cluster',
        rows: [
          ['Instance', 'AZL-CLUSTER-01', ''],
          ['Nodes', '4 active', 'good'],
          ['Deployment', '54 of 54 steps', 'good'],
          ['Build time', '2h 13m', '']
        ]
      },
      {
        id: 'm-arc',
        title: 'Azure Arc',
        rows: [
          ['Resource bridge', 'Operational', 'good'],
          ['Custom location', 'azl-cluster-01-cl', ''],
          ['Region', 'southcentralus', ''],
          ['Storage', '3-way mirror', 'good']
        ]
      }
    ],
    detail: [
      { cap: 'What this proves', body: 'The Azure control plane extends to on-premises hardware. The same portal, CLI, RBAC, and templates apply to servers in our own rack.' },
      { cap: 'Boundary', body: 'This is a functional proof of concept on workstation-class hardware, not a certified production platform.' }
    ],
    stream: [
      { t: 200,  src: 'azure-local', msg: 'cluster AZL-CLUSTER-01 reachable', tone: 'ok' },
      { t: 800,  src: 'arc',         msg: 'resource bridge online', tone: 'ok' },
      { t: 1400, src: 'arc',         msg: 'custom location registered', tone: 'ok' },
      { t: 2000, src: 'storage',     msg: 'Storage Spaces Direct healthy', tone: 'ok' },
      { t: 2600, src: 'finding',     msg: 'node 01 has one retired NVMe path', tone: 'warn' }
    ],
    dwell: 1600
  },

  {
    id: 'appliance',
    title: 'A machine built for one purpose',
    fid: 'story',
    exec: 'We built a <strong>custom operating system image</strong> whose only job is to run this product, then deployed it as a virtual machine on the cluster. This console is running on it right now.',
    prompt: 'build and deploy the appliance image',
    arch: ['vm'],
    hot: ['vm'],
    pods: 0,
    mods: [
      {
        id: 'm-vm',
        title: 'Appliance image',
        rows: [
          ['Base', 'Linux cloud image', ''],
          ['Generation', 'Gen 2, Secure Boot', 'good'],
          ['Provisioning', 'cloud-init', ''],
          ['Role', 'kiosk console', 'info']
        ]
      }
    ],
    detail: [
      { cap: 'What this proves', body: 'Azure Local supports custom VM images from a prepared VHDX. We can ship an appliance, not just an application.' },
      { cap: 'Boundary', body: 'The image runs as a guest virtual machine. The Azure Local host operating system itself is the platform and is not modified.' }
    ],
    stream: [
      { t: 200,  src: 'image',      msg: 'cloud-init cleaned, VHDX captured', tone: 'info' },
      { t: 1000, src: 'azure-local', msg: 'gallery image created', tone: 'ok' },
      { t: 1700, src: 'azure-local', msg: 'VM placed and running', tone: 'ok' },
      { t: 2400, src: 'console',    msg: 'browser session attached to display', tone: 'ok' }
    ],
    dwell: 1500
  },

  {
    id: 'image',
    title: 'Software becomes a shippable unit',
    fid: 'story',
    exec: 'The application is packaged as a <strong>container image with an immutable version</strong>. What we test is exactly what we run, and we can prove which build is serving traffic.',
    prompt: 'build the application image',
    arch: ['src', 'img'],
    hot: ['img'],
    pods: 0,
    mods: [
      {
        id: 'm-img',
        title: 'Container image',
        rows: [
          ['Repository', 'azure-local-dashboard', ''],
          ['Tag', 'v1.4.0', 'info'],
          ['Digest', 'sha256:9f2c...41ab', ''],
          ['Build', 'reproducible', 'good']
        ]
      }
    ],
    detail: [
      { cap: 'What this proves', body: 'Every deployment is traceable to a specific source revision and image digest. Version drift becomes visible instead of invisible.' },
      { cap: 'Boundary', body: 'Where the build runs is still a design decision: a pipeline runner, or the cluster itself building its own image.' }
    ],
    stream: [
      { t: 200,  src: 'source', msg: 'commit 8c41f2e checked out', tone: 'info' },
      { t: 900,  src: 'build',  msg: 'layers assembled', tone: 'info' },
      { t: 1700, src: 'build',  msg: 'image tagged v1.4.0', tone: 'ok' },
      { t: 2300, src: 'registry', msg: 'digest published', tone: 'ok' }
    ],
    dwell: 1400
  },

  {
    id: 'kubernetes',
    title: 'Declare the outcome, not the steps',
    fid: 'proven',
    exec: 'We tell Kubernetes <strong>what we want running</strong>, not how to run it. It places the work, keeps it alive, and gives it a stable address that never changes.',
    prompt: 'deploy the application to kubernetes',
    arch: ['aks', 'wrk', 'dep', 'svc', 'p1', 'p2'],
    hot: ['dep'],
    pods: 2,
    mods: [
      {
        id: 'm-k8s',
        title: 'AKS enabled by Azure Arc',
        rows: [
          ['Cluster', 'azl-cluster-01-aks-01', ''],
          ['Kubernetes', 'v1.33.5', ''],
          ['Node OS', 'Azure Linux', ''],
          ['Status', 'Ready', 'good']
        ]
      },
      {
        id: 'm-dep',
        title: 'Workload',
        rows: [
          ['Deployment', 'azure-local-dashboard', ''],
          ['Desired', '2', ''],
          ['Ready', '2', 'good'],
          ['Restarts', '0', 'good']
        ]
      }
    ],
    detail: [
      { cap: 'What this proves', body: 'The same Kubernetes API and workload model used in the cloud runs on our own cluster, under Azure Arc management.' },
      { cap: 'Boundary', body: 'The application is reachable inside the cluster. An externally routable address requires a load balancer capability that is not enabled in this subscription.' }
    ],
    stream: [
      { t: 200,  src: 'kubectl',    msg: 'applied deployment and service', tone: 'info' },
      { t: 900,  src: 'scheduler',  msg: 'pod scheduled to worker node', tone: 'info' },
      { t: 1500, src: 'kubelet',    msg: 'image pulled, container started', tone: 'info' },
      { t: 2200, src: 'kubernetes', msg: 'deployment 2 of 2 ready', tone: 'ok' },
      { t: 2900, src: 'service',    msg: 'ClusterIP 10.30.1.58 assigned', tone: 'ok' }
    ],
    dwell: 1600
  },

  {
    id: 'scale',
    title: 'Capacity follows demand',
    fid: 'proven',
    exec: 'Traffic arrives and we add capacity in seconds. <strong>Ninety requests were distributed across three copies</strong> with no failures and no configuration change.',
    prompt: 'scale to handle more traffic',
    arch: ['p3'],
    hot: ['svc', 'p3'],
    pods: 3,
    mods: [
      {
        id: 'm-scale',
        title: 'Scale event',
        rows: [
          ['Replicas', '2 -> 3', 'info'],
          ['Time to ready', 'under 10s', 'good'],
          ['Endpoints', '3 of 3', 'good'],
          ['Restored to', '2', '']
        ]
      },
      {
        id: 'm-route',
        title: 'Traffic distribution',
        rows: [
          ['Requests', '90', ''],
          ['Successful', '90', 'good'],
          ['Failed', '0', 'good'],
          ['Per replica', '26 / 30 / 34', 'info']
        ]
      }
    ],
    detail: [
      { cap: 'What this proves', body: 'One stable address spreads real traffic across every healthy copy, and membership updates automatically as capacity changes.' },
      { cap: 'Boundary', body: 'This scale was operator initiated. Demand-driven automatic scaling requires the metrics component, which is a supported and documented addition.' }
    ],
    stream: [
      { t: 200,  src: 'kubectl',    msg: 'scale deployment to 3', tone: 'hot' },
      { t: 800,  src: 'kubernetes', msg: 'third replica created', tone: 'info' },
      { t: 1400, src: 'endpoints',  msg: 'membership updated to 3', tone: 'ok' },
      { t: 2000, src: 'load',       msg: 'sending 90 requests', tone: 'hot' },
      { t: 2900, src: 'result',     msg: '26 / 30 / 34 across replicas', tone: 'ok' },
      { t: 3500, src: 'result',     msg: '0 failures', tone: 'ok' }
    ],
    dwell: 1700
  },

  {
    id: 'heal',
    title: 'It repairs itself',
    fid: 'proven',
    exec: 'We deliberately destroy a running copy. <strong>Nobody is paged.</strong> The platform notices, replaces it, and restores service capacity on its own.',
    prompt: 'delete a running instance',
    arch: [],
    hot: ['dep', 'p2'],
    pods: 3,
    mods: [
      {
        id: 'm-heal',
        title: 'Failure and recovery',
        rows: [
          ['Instance removed', '1', 'warn'],
          ['Detected by', 'controller', ''],
          ['Replacement', 'automatic', 'good'],
          ['Human action', 'none', 'good']
        ]
      }
    ],
    detail: [
      { cap: 'What this proves', body: 'Desired state is enforced continuously. Recovery from instance loss is a platform behavior, not an operations procedure.' },
      { cap: 'Boundary', body: 'This demonstrates application instance recovery. Whole-host failure was tested separately through a controlled node reboot.' }
    ],
    stream: [
      { t: 200,  src: 'operator',   msg: 'deleted one running pod', tone: 'hot' },
      { t: 800,  src: 'endpoints',  msg: 'membership dropped to 2', tone: 'warn' },
      { t: 1400, src: 'kubernetes', msg: 'replacement pod created', tone: 'info' },
      { t: 2100, src: 'kubernetes', msg: 'replacement ready', tone: 'ok' },
      { t: 2700, src: 'endpoints',  msg: 'membership restored to 3', tone: 'ok' }
    ],
    dwell: 1600
  },

  {
    id: 'terraform',
    title: 'Infrastructure as reviewable code',
    fid: 'proven',
    exec: 'A server is created from <strong>code that was reviewed before it ran</strong>, and removed cleanly afterward. Infrastructure becomes a change you can approve, audit, and repeat.',
    prompt: 'provision a server from code',
    arch: ['tf', 'tfvm'],
    hot: ['tf', 'tfvm'],
    pods: 3,
    mods: [
      {
        id: 'm-tf',
        title: 'Terraform lifecycle',
        rows: [
          ['Plan', '3 add, 0 change, 0 destroy', 'info'],
          ['Created', 'tf-poc-linux-01', ''],
          ['Placement', 'AZL-NODE-04', ''],
          ['Cleanup', 'no objects remaining', 'good']
        ]
      }
    ],
    detail: [
      { cap: 'What this proves', body: 'Azure Local infrastructure can be described in code, previewed before it is applied, and destroyed back to a clean state.' },
      { cap: 'Boundary', body: 'The platform reported completion later than the virtual machine was actually running. Automation must handle that delay rather than assume it.' }
    ],
    stream: [
      { t: 200,  src: 'terraform', msg: 'plan: 3 to add, 0 to change, 0 to destroy', tone: 'hot' },
      { t: 1000, src: 'operator',  msg: 'plan reviewed and approved', tone: 'info' },
      { t: 1700, src: 'terraform', msg: 'creating machine, nic, and vm instance', tone: 'info' },
      { t: 2500, src: 'azure-local', msg: 'tf-poc-linux-01 running on node 04', tone: 'ok' },
      { t: 3200, src: 'finding',   msg: 'ARM status lagged runtime readiness', tone: 'warn' },
      { t: 3900, src: 'terraform', msg: 'destroy complete, state clean', tone: 'ok' }
    ],
    dwell: 1700
  },

  {
    id: 'system',
    title: 'One system, end to end',
    fid: 'story',
    exec: 'Source, pipeline, infrastructure, platform, and application are now <strong>a single connected path</strong>. Every layer on this screen was demonstrated on our own hardware.',
    prompt: 'show the full system',
    arch: ['ci'],
    hot: [],
    pods: 3,
    mods: [
      {
        id: 'm-ledger',
        title: 'Demonstrated',
        rows: [
          ['Azure Local platform', 'Proven', 'good'],
          ['Virtual machines', 'Proven', 'good'],
          ['Containers on Kubernetes', 'Proven', 'good'],
          ['Scale and self-healing', 'Proven', 'good'],
          ['Infrastructure as code', 'Proven', 'good']
        ]
      },
      {
        id: 'm-next',
        title: 'Next, with a decision',
        rows: [
          ['Demand-based autoscale', 'Available', 'info'],
          ['Pipeline-driven delivery', 'Available', 'info'],
          ['External load balancer', 'Needs approval', 'warn'],
          ['Production hardening', 'Not in scope', 'warn']
        ]
      }
    ],
    detail: [
      { cap: 'The takeaway', body: 'We proved that a full cloud-native delivery stack runs on hardware we own, under Azure management, with the same tools teams already use.' },
      { cap: 'What it is not', body: 'This is a proof of concept. It is not a supported production platform, and it does not carry availability, performance, or capacity guarantees.' },
      { cap: 'The ask', body: 'Decide whether this becomes a supported internal capability, and on what hardware.' }
    ],
    stream: [
      { t: 200,  src: 'ci',        msg: 'source validation workflow available', tone: 'info' },
      { t: 900,  src: 'system',    msg: 'all layers connected', tone: 'ok' },
      { t: 1600, src: 'system',    msg: 'evidence recorded for each stage', tone: 'ok' },
      { t: 2300, src: 'boundary',  msg: 'proof of concept, not production certified', tone: 'warn' }
    ],
    dwell: 2600
  }
];

/*
 * Connections that form between architecture nodes, per stage.
 * Each entry is [from, to, kind].
 *
 * kind 'vine' -> organic. Curves, grows slowly, green. The living workload.
 * kind 'ice'  -> machine. Angular circuit routing, crystallizes fast, Azure blue.
 *                Control plane, automation, and infrastructure paths.
 */
const STAGE_LINKS = {
  boot: [],
  platform: [
    ['h1', 'azl', 'ice'], ['h2', 'azl', 'ice'], ['h4', 'azl', 'ice'], ['h6', 'azl', 'ice'],
    ['azl', 'arc', 'ice'], ['azl', 's2d', 'ice']
  ],
  appliance: [['arc', 'vm', 'ice']],
  image: [['src', 'img', 'vine']],
  kubernetes: [
    ['arc', 'aks', 'ice'], ['aks', 'wrk', 'ice'],
    ['img', 'dep', 'vine'], ['dep', 'p1', 'vine'], ['dep', 'p2', 'vine'], ['dep', 'svc', 'vine']
  ],
  scale: [['dep', 'p3', 'vine'], ['svc', 'p3', 'vine']],
  heal: [],
  terraform: [['src', 'tf', 'vine'], ['tf', 'tfvm', 'ice'], ['arc', 'tfvm', 'ice']],
  system: [['src', 'ci', 'vine'], ['ci', 'img', 'ice']]
};

/* Links to re-energize without redrawing, for stages that exercise existing paths. */
const STAGE_PULSES = {
  heal: [['dep', 'p2'], ['dep', 'p1']],
  scale: [['dep', 'p1'], ['dep', 'p2']],
  system: [['arc', 'aks'], ['dep', 'svc'], ['tf', 'tfvm']]
};

/*
 * Pacing. Real operations are slow, so the storyboard should not imply they are instant.
 * Every scripted time is multiplied by this before playback.
 */
const PACE = 2.4;

/*
 * The product frame is a constrained lattice. Every slot exists from the first frame, locked and empty,
 * so the audience can see the shape of the finished system before any of it is real.
 * Stages unlock slots in place. The whole is visibly assembled from bounded parts.
 *
 * span     -> columns consumed in the 4 column grid
 * minH     -> reserved height so the lattice does not reflow when a slot fills
 */
const FRAME_SLOTS = [
  { id: 'w-shell',  name: 'console.shell',            span: 2, minH: 78 },
  { id: 'w-hello',  name: 'app.identity',             span: 2, minH: 112 },
  { id: 'w-tiles',  name: 'workload.state',           span: 2, minH: 104 },
  { id: 'w-bars',   name: 'traffic.distribution',     span: 2, minH: 132 },
  { id: 'w-health', name: 'resilience.monitor',       span: 2, minH: 116 },
  { id: 'w-infra',  name: 'infrastructure.inventory', span: 2, minH: 116 },
  { id: 'w-map',    name: 'system.map',               span: 4, minH: 96 }
];

/*
 * Boot readiness gate.
 *
 * This is not decoration. The counter exists to cover real backend cold start: identity resolution,
 * control-plane reachability, the first Kubernetes read, evidence load, and opening the event stream.
 * Progress advances as each check resolves, so a slow environment simply takes longer instead of
 * dropping the operator into a half-populated console.
 *
 * In the real build, replace `ms` with the actual awaited call named in `real`.
 * `weight` is the share of the progress bar each check owns, and the weights total 100.
 */
const BOOT_TASKS = [
  { id: 'identity', weight: 10, ms: [260, 380],
    label: 'resolve operator identity',
    real: 'GET /api/session -> signed-in identity and role scope' },

  { id: 'arm', weight: 14, ms: [420, 720],
    label: 'reach Azure control plane',
    real: 'GET /api/azure/health -> ARM reachability and Arc bridge state' },

  { id: 'cluster', weight: 16, ms: [380, 640],
    label: 'read Azure Local cluster health',
    real: 'GET /api/cluster -> nodes, storage pool, custom location' },

  { id: 'k8s', weight: 18, ms: [340, 580],
    label: 'open read-only Kubernetes session',
    real: 'GET /api/kubernetes/state -> deployment, endpoints, pods' },

  { id: 'evidence', weight: 14, ms: [200, 340],
    label: 'load recorded evidence',
    real: 'GET /api/evidence -> sanitized run artifacts' },

  { id: 'stream', weight: 14, ms: [300, 540],
    label: 'attach live event stream',
    real: 'SSE /api/stream -> Kubernetes events and pipeline updates' },

  { id: 'frame', weight: 14, ms: [260, 440],
    label: 'hydrate console modules',
    real: 'client mounts modules for capabilities that reported ready' }
];

/*
 * Elapsed time for the work each stage represents.
 *
 * kind: 'measured'  -> taken from a recorded run in the project record
 *       'none'      -> we never timed this, and the prototype says so
 *
 * Only two durations in this project were actually measured end to end. Everything else is left
 * explicitly untimed rather than invented.
 */
const STAGE_ELAPSED = {
  boot:       { value: 'not measured', kind: 'none' },
  platform:   { value: '2h 13m, measured', kind: 'measured' },
  appliance:  { value: 'not measured', kind: 'none' },
  image:      { value: 'not measured', kind: 'none' },
  kubernetes: { value: 'not measured', kind: 'none' },
  scale:      { value: 'not measured', kind: 'none' },
  heal:       { value: 'not measured', kind: 'none' },
  terraform:  { value: 'not measured', kind: 'none' },
  system:     { value: 'about 2 months of project time', kind: 'measured' }
};

/*
 * Applied examples. What this capability is actually for, beyond the demo building itself.
 * Written for an internal engineering and lab audience.
 */
const STAGE_USES = {
  boot: [
    { label: 'The point', text: 'Hardware you already own, operated with the tools your teams already know.' }
  ],
  platform: [
    { label: 'Lab and bench infrastructure', text: 'Run validation environments locally while keeping Azure governance, identity, and policy.' },
    { label: 'Data that cannot leave', text: 'Workloads bound by residency, latency, or classification stay on site.' },
    { label: 'Remote and branch compute', text: 'Sites managed centrally from Azure without a local virtualization team.' }
  ],
  appliance: [
    { label: 'Purpose-built stations', text: 'Locked, reproducible consoles for lab benches and operator positions.' },
    { label: 'Rebuild instead of repair', text: 'A broken station is reimaged from the known-good image in minutes.' }
  ],
  image: [
    { label: 'Identical tooling everywhere', text: 'Engineers and automation run the same versions instead of drifting per machine.' },
    { label: 'Traceable builds', text: 'Any running instance points back to an exact source revision.' }
  ],
  kubernetes: [
    { label: 'Internal applications', text: 'Dashboards, APIs, and line-of-business tools hosted on local hardware.' },
    { label: 'Test harnesses', text: 'Long-running validation and data collection services that must stay up.' },
    { label: 'Edge data handling', text: 'Collect, filter, and forward locally instead of shipping everything upstream.' }
  ],
  scale: [
    { label: 'Burst validation', text: 'Add capacity for a regression sweep, then return it when the run finishes.' },
    { label: 'Uneven demand', text: 'Absorb campaign spikes without permanently sizing for the peak.' }
  ],
  heal: [
    { label: 'Unattended sites', text: 'Overnight and remote workloads recover without waking anyone.' },
    { label: 'Lower operational load', text: 'Routine instance failure stops being a ticket and becomes a platform event.' }
  ],
  terraform: [
    { label: 'Repeatable site build-out', text: 'Stand up the next lab or site from reviewed code instead of memory.' },
    { label: 'Auditable change', text: 'Every infrastructure change is proposed, reviewed, and recorded before it runs.' },
    { label: 'Disposable environments', text: 'Create a test environment, use it, and remove it cleanly.' }
  ],
  system: [
    { label: 'A reusable pattern', text: 'This stack becomes a template other teams can adopt for their own sites.' },
    { label: 'Onboarding', text: 'New engineers learn the platform by walking the same path this console shows.' }
  ]
};

/*
 * The product builds itself. Each stage hot-loads modules into the live frame and bumps its version,
 * so the page visibly becomes the thing the stages are describing.
 *
 * kind selects the renderer in app.js.
 */
const STAGE_WIDGETS = {
  appliance: {
    version: 'v0.1',
    modules: [
      { id: 'w-shell', kind: 'shell', title: 'console.shell',
        note: 'Frame mounted. No capability loaded yet.' }
    ]
  },
  image: {
    version: 'v0.2',
    modules: [
      { id: 'w-hello', kind: 'hello', title: 'app.identity',
        heading: 'Azure Local Console',
        sub: 'served from a versioned container image',
        meta: [['build', 'v1.4.0'], ['request', 'a91f-2c07']] }
    ]
  },
  kubernetes: {
    version: 'v0.3',
    modules: [
      { id: 'w-tiles', kind: 'tiles', title: 'workload.state',
        tiles: [['Replicas', '2'], ['Endpoints', '2'], ['Restarts', '0']] }
    ]
  },
  scale: {
    version: 'v0.4',
    modules: [
      { id: 'w-bars', kind: 'bars', title: 'traffic.distribution',
        bars: [['pod-72jvt', 26], ['pod-m94q2', 30], ['pod-np6jx', 34]],
        foot: '90 requests, 0 failures' }
    ]
  },
  heal: {
    version: 'v0.5',
    modules: [
      { id: 'w-health', kind: 'health', title: 'resilience.monitor',
        pills: [['self-healing', 'active', 'good'], ['last recovery', 'automatic', 'good'],
                ['operator action', 'none', 'good']] }
    ]
  },
  terraform: {
    version: 'v0.6',
    modules: [
      { id: 'w-infra', kind: 'infra', title: 'infrastructure.inventory',
        rows: [['tf-poc-linux-01', 'created then destroyed'], ['declared in', 'version control'],
               ['drift', 'none at cleanup']] }
    ]
  },
  system: {
    version: 'v1.0',
    modules: [
      { id: 'w-map', kind: 'map', title: 'system.map',
        chain: ['source', 'pipeline', 'infra', 'platform', 'app'],
        foot: 'every layer demonstrated on local hardware' }
    ]
  }
};
