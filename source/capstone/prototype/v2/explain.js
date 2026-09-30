/*
 * Click to explain.
 *
 * Not a modal. A modal centres itself, dims the room behind it, and puts an X in the corner, which
 * is the shape every one of these ends up being. This is a callout instead: anchored beside the
 * thing you clicked, joined to it by a stem, with the diagram left fully visible behind it. The
 * reference is a technical drawing annotation rather than a web dialog.
 *
 * Three fields per entry, in the order somebody actually needs them:
 *   what   the general definition, true anywhere, not just here
 *   role   what it does for the system it sits in
 *   here   what it specifically is in this build, with a real name or number
 *
 * The labels on the diagram are short because the diagram is not a glossary. This is the glossary.
 */

const EXPLAIN = (function () {
  'use strict';

  const INFO = {
    sw1: {
      what: 'A top of rack switch. Arista 7050, 100GbE.',
      role: 'Carries one of the two storage fabrics. Storage traffic between machines crosses a switch, and there are two so that losing one does not stop storage.',
      here: 'stor-sw-01, VLAN 711 tagged, priority flow control on priority 3. Every node Port3 lands here.'
    },
    sw2: {
      what: 'The second top of rack switch, identical model.',
      role: 'The other storage fabric. Deliberately separate from the first: different switch, different VLAN, no path between them.',
      here: 'stor-sw-02, VLAN 712 tagged. Every node Port4 lands here. Getting this wrong on three nodes cost weeks.'
    },
    machine: {
      what: 'One physical server. A Dell Precision 7960 Rack, which is a workstation chassis rather than a server SKU.',
      role: 'Contributes CPU, memory and drives to the cluster. Any of them can run any workload, because the storage is shared.',
      here: 'Four of the six made it in. 24 cores and 32 GB each, three NVMe, Secure Boot on, domain joined during deployment.'
    },
    h03: {
      what: 'The third machine. Identical hardware to the four that made it in, and it never joined.',
      role: 'It was inside the original four node scope. Node 06 took its place, and this one became the sealed spare.',
      here: 'Drives on the add-in carrier card enumerated behind Intel VMD as BusType RAID, which Storage Spaces Direct will not pool. Rather than rebuild it, node 03 was left sealed as the fallback donor: two Mellanox cards, right subsystem ID, never opened.'
    },
    h05: {
      what: 'The fifth machine. Deferred from the build at the start, then disqualified outright.',
      role: 'Worth more as a parts source than as a node, which is the only reason the cluster reached four.',
      here: 'Failed the NVMe check on drive count and type, so it was out. Its Mellanox card then fixed node 02, which had one adapter reading subsystem 000615B3 where every other port reads 008015B3, and validation refuses a mismatch. MAC 00-00-5E-00-53-03 moved into node 02 Port4.'
    },
    azl: {
      what: 'Azure Local. Microsoft platform for running Azure services on hardware you own.',
      role: 'Turns a set of machines into one system with pooled storage, and projects it into Azure so it can be managed like any other resource.',
      here: 'AZL-CLUSTER-01. Four nodes, deployed in a single pass, 54 of 54 steps completed with none failed, 2h 13m.'
    },
    arc: {
      what: 'The Arc Resource Bridge. A management virtual machine that runs on the cluster itself.',
      role: 'The bridge that lets Azure create and manage things down here. Without it, hardware in your building is invisible to every Azure tool.',
      here: 'Custom location azl-cluster-01-cl. Deploying it was step 40 of 54 and took about 64 minutes, the longest single step.'
    },
    s2d: {
      what: 'Storage Spaces Direct. Software defined storage built from the local drives in every machine.',
      role: 'Pools the drives into one surface every node can see, and keeps copies spread across machines so losing one loses no data.',
      here: 'SU1_Pool, twelve drives, three per machine. Three way mirror. A drive failed and the only consequence was a number in a report.'
    },
    aks: {
      what: 'AKS enabled by Azure Arc. Managed Kubernetes, with the control plane running here instead of in a region.',
      role: 'Schedules containers across worker nodes, replaces them when they fail, and keeps the declared number running.',
      here: 'azl-cluster-01-aks-01, v1.33.5. One control plane node and one worker, both Azure Linux, both clustered VMs on Azure Local.'
    },
    wrk: {
      what: 'A Kubernetes worker node. Here it is a virtual machine, not a physical one.',
      role: 'Runs the actual containers. The kubelet on it starts them and reports back to the control plane.',
      here: 'moc-worker-01. Both dashboard pods sit on it, because there is only one worker. That is the single biggest limitation in this build.'
    },
    tfvm: {
      what: 'A virtual machine that exists because a file says it should.',
      role: 'Infrastructure as code. The description is the source of truth, reviewable before anything is created and reversible afterwards.',
      here: 'tf-poc-linux-01. Terraform planned it, created it, we confirmed it running, then destroyed it and confirmed nothing was left behind.'
    },
    vm: {
      what: 'An ordinary Linux virtual machine on the cluster.',
      role: 'Somewhere to run containers without Kubernetes. Docker is not installed on the hosts themselves, it runs inside a guest.',
      here: 'rocky-docker-01, Rocky Linux 10.2, Arc managed. Currently on AZL-NODE-04 at 10.10.1.208.'
    },
    dep: {
      what: 'A Kubernetes Deployment. A statement of how many copies of something should be running.',
      role: 'A controller watches it and creates or deletes pods until reality matches. That is the whole of what people call self healing.',
      here: 'azure-local-dashboard, two replicas. We deleted a pod on purpose and it came back with nobody asking.'
    },
    svc: {
      what: 'A Kubernetes Service. A stable name and address in front of a changing set of pods.',
      role: 'Finds pods by label rather than by name, and only sends traffic to ones that report themselves ready. That is what lets pods be replaced without dropping requests.',
      here: 'ClusterIP 10.30.1.58 on port 80, forwarding to 8080. Internal only. An external address would need MetalLB.'
    },
    pod: {
      what: 'A pod. One or more containers that share a network namespace and get scheduled together.',
      role: 'The smallest thing Kubernetes will place on a node. Disposable and anonymous by design, which is what makes replacement invisible.',
      here: 'The dashboard runs two, each a single container serving a page that reports on the cluster it is running inside.'
    },
    dkr: {
      what: 'Docker CE. The container runtime, running inside a virtual machine.',
      role: 'Builds and runs containers on one machine. No scheduling, no healing across machines. When you need those, you are asking for an orchestrator.',
      here: 'Docker CE 29.x with Compose v5.3.1, inside rocky-docker-01. This is the answer to whether the platform is only useful with Kubernetes.'
    },
    dkg: {
      what: 'Dockge. A web front end for managing Docker Compose stacks.',
      role: 'Somewhere to see and control containers without the command line.',
      here: 'Port 5001. The VM was powered off for days, and when it was started again this came back on its own and answered with no manual step.'
    }
  };

  // Pods share one entry rather than three near identical ones. Named entries win, because the
  // two machines that never joined are the ones people will actually want to ask about.
  function infoFor(id) {
    if (!id) return null;
    if (INFO[id]) return INFO[id];
    if (id.charAt(0) === 'h' && id.length === 3) return INFO.machine;
    if (id.charAt(0) === 'p' && id.length === 2) return INFO.pod;
    return null;
  }

  let dom = null;
  let openOn = null;

  function el(id) { return document.getElementById(id); }

  function ready() {
    if (dom) return true;
    dom = {
      root: el('callout'),
      title: el('calloutTitle'),
      meta: el('calloutMeta'),
      what: el('calloutWhat'),
      role: el('calloutRole'),
      here: el('calloutHere')
    };
    return !!dom.root;
  }

  function hide() {
    if (!ready() || !openOn) return;
    dom.root.classList.remove('on');
    const prev = document.querySelector('.asked');
    if (prev) prev.classList.remove('asked');
    openOn = null;
    window.setTimeout(() => { if (!openOn) dom.root.hidden = true; }, 200);
  }

  function show(node) {
    if (!ready()) return;
    const info = infoFor(node.dataset.id);
    if (!info) return;

    if (openOn === node) { hide(); return; }

    const prev = document.querySelector('.asked');
    if (prev) prev.classList.remove('asked');
    node.classList.add('asked');
    openOn = node;

    // A fabric cell is the same machine after it shrinks into the strip, and carries only a label.
    const name = node.querySelector('.node-name') || node.querySelector('span:last-child');
    const meta = node.querySelector('.node-meta');
    dom.title.textContent = name ? name.textContent : node.dataset.id;
    dom.meta.textContent = meta ? meta.textContent : '';
    dom.what.textContent = info.what;
    dom.role.textContent = info.role;
    dom.here.textContent = info.here;

    dom.root.hidden = false;
    dom.root.classList.remove('flip');

    // Sit beside the node, not over it, and flip to the other side near the right edge.
    const r = window.FIT.rect(node);
    const w = 330;
    const gap = 18;
    const flip = r.right + gap + w > window.FIT.W - 16;
    const x = flip ? r.left - gap - w : r.right + gap;
    dom.root.style.left = Math.max(16, x) + 'px';
    if (flip) dom.root.classList.add('flip');

    // Measure after content is in, so a long entry is not pushed off the bottom. Reading
    // offsetHeight also flushes layout, which is what lets the transition run from its start
    // state without waiting on a frame callback.
    const h = dom.root.offsetHeight;
    let y = r.top + r.height / 2 - h / 2;
    y = Math.max(16, Math.min(y, window.FIT.H - h - 16));
    dom.root.style.top = y + 'px';

    dom.root.classList.add('on');
  }

  document.addEventListener('click', (e) => {
    if (!e.target.closest) return;
    const hit = e.target.closest('.node.on, #fabricCells .cell');
    if (hit) { show(hit); return; }
    if (!e.target.closest('#callout')) hide();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') hide();
  });

  // The diagram relayouts on every movement, so a callout left hanging would point at nothing.
  window.addEventListener('resize', hide);

  return { hide, has: (id) => !!infoFor(id) };
})();

window.EXPLAIN = EXPLAIN;
