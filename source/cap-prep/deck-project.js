/*
 * Project track.
 *
 * Talking through what was actually built. Not defending it. The room asked somebody to go and
 * explore Azure Local, and this is the account of what that turned up.
 */

window.DECK = (window.DECK || []).concat([

  {
    id: 'pr-what', track: 'project', level: 'basic',
    q: 'In one sentence, what did this project do?',
    say: [
      'Took leftover lab hardware and built a working Azure Local cluster on it.',
      'Then ran real things on it: Windows and Linux VMs, Kubernetes, containers, and infrastructure as code.',
      'And watched what happened when pieces were taken away.'
    ],
    why: 'Lead with what was built, not with the caveats. The limits are worth saying and they are the second sentence, not the first.',
    ours: 'Four machines, one cluster, deployed in a single pass with all 54 steps reporting Success.',
    src: 'README.md'
  },
  {
    id: 'pr-scope', track: 'project', level: 'basic',
    q: 'What was in scope and what was not?',
    say: [
      'In scope: get a cluster up, run workloads on it, and demonstrate the recovery behaviour.',
      'Out of scope: production readiness, high availability guarantees, disaster recovery, performance benchmarking.',
      'It is a proof that the thing works and behaves sensibly, not a recommendation to run anything important on it yet.'
    ],
    why: 'Being clear about this up front makes everything after it easier to say, because you are no longer implying claims you would then have to walk back.',
    ours: 'The four node scope was a deliberate decision, written down at the time, not something that happened by accident.',
    src: 'decisions/0004-four-node-functional-poc-scope.md'
  },
  {
    id: 'pr-time', track: 'project', level: 'foundation',
    q: 'Why did it take two months?',
    say: [
      'The deployment itself took 2 hours 13 minutes. Everything before it was the work.',
      'Cabling, VLANs, firmware, storage controller mode, imaging, hardware validation, and requirements that were not settled at the start.',
      'Two of six machines never made it into the cluster, and an NVMe failed during the project.'
    ],
    why: 'The useful framing is that almost none of it was the product. The Azure Local part was the short part, and the long part was physical and organisational.',
    ours: 'Three of four machines had their storage ports wired to the wrong fabrics, which took three attempts and an adapter rename on every machine to resolve.',
    src: 'capstone/presentation-extras.md'
  },
  {
    id: 'pr-retries', track: 'project', level: 'foundation',
    q: 'Did the deployment go cleanly?',
    say: [
      'The final run went through in one pass, 54 of 54 steps Succeeded, in 2 hours 13 minutes.',
      'Getting to a state where that run could succeed took two months and several failed attempts.',
      'Be careful not to let the first sentence imply the second did not happen.'
    ],
    why: 'The precise claim is about the final run, not about the project. Both facts are good. Saying only the first one is what turns a true statement into a misleading one.',
    ours: 'Inside that successful run, the storage validation step alone took about 27 minutes.',
    src: 'capstone/presenter-brief.md'
  },
  {
    id: 'pr-drive', track: 'project', level: 'foundation',
    q: 'What happened with the drive?',
    say: [
      'An NVMe failed in a lab 200 miles away and the only symptom was a number in a health report.',
      'No outage, no data loss, nobody was paged. The pool stayed healthy and the workloads kept running.',
      'The platform then refused to let me reboot that node, four times, because a virtual disk was down a copy.'
    ],
    why: 'The refusal is the better half of the story. A system declining to trade redundancy for operator convenience, and being right, is more interesting than a disk failing.',
    ours: 'A repair job stuck at zero percent for ten days completed on its own after the node restarted.',
    src: 'docs/runbooks/node01-retired-nvme-recovery.md'
  },
  {
    id: 'pr-vmss', track: 'project', level: 'working',
    q: 'The brief asked for VM Scale Sets. What happened there?',
    say: [
      'The resource type does not exist on Azure Local, so there was nothing to deploy.',
      'The ask was really five things: repeatable build, application instance scale, worker capacity scale, update posture, and controlled rollout.',
      'Terraform covers repeatable build, Kubernetes replicas cover instance scale, live migration and Cluster-Aware Updating cover update posture.',
      'Node pool scale and pipeline grade image delivery are not done.'
    ],
    why: 'Answering the intent rather than the noun is more useful to whoever asked. They wanted a capability, and naming which parts are covered is a better answer than either yes or no.',
    ours: 'Marked as an architecture finding rather than met or deferred, because it is neither.',
    src: 'docs/planning/original-poc-acceptance-criteria.md'
  },
  {
    id: 'pr-availset', track: 'project', level: 'working',
    q: 'And Availability Sets?',
    say: [
      'Also not an Azure Local resource. Availability Sets and Zones are Azure region constructs.',
      'The intent was resiliency across fault and update domains.',
      'Update domain: we moved a running machine between hosts with a live workload on it, 16.7 seconds, no endpoint lost.',
      'Fault domain: we lost a node, virtual disks went degraded but stayed online, and repair started on its own.'
    ],
    why: 'This is one of the better findings, so it is worth taking time over. The equivalent is not a workaround. The cluster provides both behaviours natively without you declaring a grouping object at all.',
    ours: 'Both halves are cited with measurements rather than described.',
    src: 'docs/planning/azure-local-platform-boundary-research.md'
  },
  {
    id: 'pr-lb', track: 'project', level: 'working',
    q: 'Did you prove load balancing?',
    say: [
      'Inside the cluster yes. Thirty independent requests through the Service reached both ready pods, 17 and 13, and endpoint membership followed readiness during scale and recovery.',
      'Externally no. An external address needs MetalLB, which needs a subscription provider registration we chose not to escalate for a proof.',
      'A port forward would not have counted, because it pins to a single pod.'
    ],
    why: 'Mentioning why the weaker evidence would not have counted is worth doing, because it shows the result was designed rather than stumbled into.',
    ours: 'Recorded as met with a stated boundary rather than simply met.',
    src: 'docs/planning/kubernetes-terraform-integration-test-results.md'
  },
  {
    id: 'pr-dashboard', track: 'project', level: 'working',
    q: 'What is actually running on the cluster right now?',
    say: [
      'A two replica web page on AKS Arc that reports on the cluster it is running on.',
      'It reads the Kubernetes API read only, as a ServiceAccount limited to get, list and watch in its own namespace.',
      'It also pulls a live market quote, which is a simple way to show the workload has outbound connectivity from on premises hardware.'
    ],
    why: 'The stock quote is worth showing because the timestamp moves. It is a live fact rather than a screenshot of a claim.',
    ours: 'Two pods, zero restarts, ClusterIP Service, running for over two weeks.',
    src: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml'
  },
  {
    id: 'pr-notprod', track: 'project', level: 'working',
    q: 'Is this production ready?',
    say: [
      'No, and it was not scoped to be.',
      'One site, one rack, one power domain. No disaster recovery.',
      'Both dashboard pods run on a single worker node, so the application survives maintenance and would not survive losing that node.',
      'A production pattern needs a second worker, anti affinity, a disruption budget, and a workload that handles SIGTERM.'
    ],
    why: 'Naming the single worker node before anyone asks is worth doing. It is the most obvious gap and volunteering it is simply more useful than waiting.',
    ours: 'That boundary has its own panel in the deck rather than being left for questions.',
    src: 'capstone/presentation-extras.md'
  },
  {
    id: 'pr-learned', track: 'project', level: 'working',
    q: 'What surprised you?',
    say: [
      'How much of the two months was physical and organisational rather than technical.',
      'How strongly the platform protects data, to the point of refusing an administrator four times.',
      'How little happened when a drive died, which is the point but is not what you expect to feel.',
      'That the hardest bug was a naming problem that looked exactly like a cabling problem.'
    ],
    why: 'A genuine answer here is more interesting than a rehearsed one, and this is the question most likely to actually get asked in a friendly room.',
    ours: 'The adapter naming issue cost weeks and was fixed with a rename, not a recable.',
    src: 'docs/network/storage-switch-config.md'
  },
  {
    id: 'pr-next', track: 'project', level: 'working',
    q: 'What would you do next?',
    say: [
      'A private registry, because right now there is nowhere to push an image the cluster can pull.',
      'A second Kubernetes worker, which removes the single biggest limitation in one step.',
      'Metrics Server, which unlocks the autoscaling test we could not run.',
      'Remote Terraform state and a pipeline identity, so infrastructure as code can leave the laptop.'
    ],
    why: 'Having a short ordered list ready is useful, and the registry is first because several other ideas are blocked behind it.',
    ours: 'Disposable dev environments is the concrete proposal, and it needs the registry before it can happen.',
    src: 'capstone/presentation-extras.md'
  }
]);
