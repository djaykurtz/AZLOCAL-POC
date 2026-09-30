/*
 * Kubernetes track.
 *
 * Ordered roughly basic to pressed, because the basic cards are the pegs everything else hangs on.
 * Knowing what a node is makes the scheduler obvious. Not knowing it makes the scheduler magic.
 *
 * Fields: q, say, why, ours, src, and an optional diagram for machinery that is hard to hold in
 * words. Diagrams are plain monospace on purpose. No library, no dependency, and they survive
 * being viewed over a remote session, which fancier rendering does not.
 */

window.DECK = (window.DECK || []).concat([

  /* ---------- basic ---------- */

  {
    id: 'k8s-what', track: 'kubernetes', level: 'basic',
    q: 'What is Kubernetes, in one sentence?',
    say: [
      'A system that runs containers across a group of machines for you.',
      'You tell it what you want running. It decides where, keeps it that way, and replaces things that die.',
      'The general term is a container orchestrator. Kubernetes is the one that won.'
    ],
    why: 'The word orchestrator is the useful one. Docker runs a container on a machine. An orchestrator decides which machine, notices when the machine is gone, and does something about it.',
    ours: 'Ours is AKS enabled by Azure Arc, running on VMs that Azure Local created on our own hardware.',
    src: 'https://kubernetes.io/docs/concepts/overview/'
  },
  {
    id: 'k8s-cluster-node', track: 'kubernetes', level: 'basic',
    q: 'What is a cluster and what is a node?',
    say: [
      'A node is one machine, physical or virtual, that can run containers.',
      'A cluster is a set of nodes managed as one thing.',
      'Nodes split into control plane, which makes decisions, and workers, which run your workloads.'
    ],
    why: 'Everything else assumes this. A pod runs on a node, a scheduler picks a node, and losing a node is the failure the whole design is built around.',
    ours: 'One control plane node and one worker node, both Azure Linux, both VMs on the Azure Local cluster. One worker is the single biggest limitation in our setup.',
    src: 'https://kubernetes.io/docs/concepts/architecture/nodes/',
    diagram:
      'cluster\n' +
      '  control plane node        worker node\n' +
      '  +------------------+      +-------------------+\n' +
      '  | api server       |      | kubelet           |\n' +
      '  | etcd             |<---->| kube-proxy        |\n' +
      '  | scheduler        |      |  [pod] [pod]      |\n' +
      '  | controllers      |      |                   |\n' +
      '  +------------------+      +-------------------+\n' +
      '\n' +
      '  decisions live left. your workloads live right.'
  },
  {
    id: 'k8s-declarative', track: 'kubernetes', level: 'basic',
    q: 'What does declarative mean here?',
    say: [
      'You describe the end state you want, not the steps to get there.',
      'Imperative is create a pod. Declarative is there should be two pods.',
      'The difference matters after something goes wrong. A declaration is still true tomorrow, a command already ran.'
    ],
    why: 'This is why Kubernetes recovers from things nobody scripted. It is not replaying your commands, it is continuously comparing the world to your description.',
    ours: 'Our dashboard is a file that says two replicas. We never told it to make a replacement pod. It made one because the file still said two.',
    src: 'https://kubernetes.io/docs/concepts/overview/working-with-objects/'
  },
  {
    id: 'k8s-kubectl', track: 'kubernetes', level: 'basic',
    q: 'What is kubectl and what does it actually talk to?',
    say: [
      'The command line client. It talks to the API server over HTTPS and nothing else.',
      'It does not talk to nodes, or to pods, or to containers directly.',
      'A kubeconfig file tells it which cluster to reach and what credentials to present.'
    ],
    why: 'Worth saying because it explains a lot of failures. If kubectl cannot do something the question is usually about the API server, the network path to it, or your identity, rather than about the workload.',
    ours: 'Our user kubeconfig authenticated fine but had no Kubernetes permissions, so commands were rejected after login rather than at it. The admin kubeconfig worked.',
    src: 'https://kubernetes.io/docs/reference/kubectl/'
  },
  {
    id: 'k8s-manifest', track: 'kubernetes', level: 'basic',
    q: 'What is a manifest?',
    say: [
      'A YAML or JSON file describing an object you want to exist.',
      'Every object has apiVersion, kind, metadata and usually spec.',
      'kubectl apply sends it to the API server, which stores it as desired state.'
    ],
    why: 'Apply is the important verb. It is not run, it is register this as what should be true. The controllers act afterwards, on their own schedule.',
    ours: 'The dashboard is a set of manifests in the repo, applied with kubectl apply, which is why it can be rebuilt from source rather than reconstructed by hand.',
    src: 'https://kubernetes.io/docs/concepts/overview/working-with-objects/'
  },
  {
    id: 'k8s-labels', track: 'kubernetes', level: 'basic',
    q: 'What are labels and selectors, and why do they matter?',
    say: [
      'Labels are key value tags on objects. Selectors match them.',
      'Almost nothing in Kubernetes refers to another object by name. It matches by label.',
      'That is how a Service finds pods, and how a ReplicaSet knows which pods are its own.'
    ],
    why: 'Loose coupling by label is what makes replacement invisible. A new pod with the right label is instantly part of the Service, and nothing had to be reconfigured or told about it.',
    ours: 'Our Service selects on an app name label, which is why a replacement pod joined the endpoints automatically.',
    src: 'https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/'
  },
  {
    id: 'k8s-namespace-basic', track: 'kubernetes', level: 'basic',
    q: 'What is a namespace?',
    say: [
      'A way to divide one cluster into named groups of objects.',
      'Names only have to be unique inside a namespace.',
      'It is the usual boundary for permissions and quotas.'
    ],
    why: 'A namespace is not an isolation boundary on its own. It scopes names and gives RBAC something to attach to, but traffic crosses freely between namespaces unless you add NetworkPolicy.',
    ours: 'The dashboard lives in its own namespace and its permissions stop at that namespace.',
    src: 'https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/'
  },
  {
    id: 'k8s-desired-observed', track: 'kubernetes', level: 'basic',
    q: 'What do desired state and observed state mean?',
    say: [
      'Desired state is what you asked for, stored in etcd.',
      'Observed state is what is actually running right now.',
      'Controllers exist to close the gap between them, forever.'
    ],
    why: 'Every Kubernetes behaviour is this one loop wearing a different hat. Scaling, healing, rolling out and rolling back are all the same mechanism with a different desired state.',
    ours: 'Deleting a pod did not trigger a recovery routine. It changed observed state, and the loop did what it always does.',
    src: 'https://kubernetes.io/docs/concepts/architecture/controller/',
    diagram:
      '        desired            observed\n' +
      '        replicas: 2        1 pod running\n' +
      '            \\                  /\n' +
      '             \\                /\n' +
      '              v              v\n' +
      '            +------------------+\n' +
      '            |   controller     |  difference = 1 missing\n' +
      '            +------------------+\n' +
      '                     |\n' +
      '                     v  create one pod\n' +
      '\n' +
      '        and then it looks again. forever.'
  },

  /* ---------- foundation ---------- */

  {
    id: 'k8s-reconcile', track: 'kubernetes', level: 'foundation',
    q: 'What actually makes Kubernetes self-healing?',
    say: [
      'Controllers run a reconciliation loop. Compare desired state to observed state, act on the difference, repeat forever.',
      'A Deployment declares how many replicas you want. A controller creates or deletes pods until reality matches.',
      'Nothing detects a failure as a special case. A pod disappearing is just a difference to reconcile, exactly like you having asked for one more.'
    ],
    why: 'This is the idea everything else hangs off. Kubernetes is not a script that runs on an event, it is a set of loops driving toward a declared state. That is why deleting a pod and scaling up look identical to the system, and why it recovers from things nobody anticipated.',
    ours: 'We deleted a healthy pod on purpose. A replacement was Running with zero restarts and the Service went back to full endpoints, with no human action between the two commands.',
    src: 'https://kubernetes.io/docs/concepts/architecture/controller/'
  },
  {
    id: 'k8s-pod-why', track: 'kubernetes', level: 'foundation',
    q: 'Why does Kubernetes schedule pods rather than containers?',
    say: [
      'A pod is one or more containers that share a network namespace and can share storage.',
      'They are always placed together on one node and share an IP, so containers in a pod reach each other on localhost.',
      'It is the smallest thing Kubernetes will schedule. Most pods hold exactly one container.'
    ],
    why: 'The pod exists so tightly coupled helpers can be co-located without inventing a second scheduling concept. A log shipper or proxy sidecar has to be on the same machine and in the same network namespace as the thing it serves.',
    ours: 'Our dashboard pods are single container. Both replicas landed on the same worker node, because there is only one worker node.',
    src: 'https://kubernetes.io/docs/concepts/workloads/pods/'
  },
  {
    id: 'k8s-service', track: 'kubernetes', level: 'foundation',
    q: 'How does traffic find a pod when pods come and go?',
    say: [
      'A Service is a stable name and address in front of a changing set of pods.',
      'It selects pods by label, not by name or address, so a replacement pod joins automatically.',
      'The set of addresses behind it is an EndpointSlice, and only pods passing their readiness probe are in it.'
    ],
    why: 'Readiness is the important half. Membership is not about whether a pod exists, it is about whether it says it can serve. That is what lets a rolling update happen without dropping requests.',
    ours: 'Thirty in cluster requests through the Service reached both backends, 17 and 13. During scale and self heal the EndpointSlice followed the ready pods.',
    src: 'https://kubernetes.io/docs/concepts/services-networking/service/',
    diagram:
      '   client\n' +
      '     |\n' +
      '     v\n' +
      '  Service            stable name + ClusterIP\n' +
      '  selector: app=dash\n' +
      '     |\n' +
      '     v\n' +
      '  EndpointSlice      only READY pods are listed here\n' +
      '   +------+------+\n' +
      '   |             |\n' +
      '   v             v\n' +
      '  [pod A]      [pod B]        [pod C] not ready -> not listed\n' +
      '   ready        ready          starting up'
  },
  {
    id: 'k8s-what-breaks', track: 'kubernetes', level: 'foundation',
    q: 'What does Kubernetes not solve for you?',
    say: [
      'It does not make a single replica highly available. Two pods on one node still die with that node.',
      'It does not fix an application that loses data, ignores signals, or cannot start twice.',
      'It does not give you storage, load balancing or DNS by itself. Those come from the environment or an add on.'
    ],
    why: 'Worth having ready, because the honest limits are usually what a sceptical room is probing. Kubernetes moves the problem to a place where you can express what you want, it does not remove it.',
    ours: 'Both our pods run on one worker node, so the workload survives maintenance and would not survive losing that node. We say so on its own panel rather than waiting to be asked.',
    src: 'capstone/presentation-extras.md'
  },

  /* ---------- working ---------- */

  {
    id: 'k8s-deploy-rs', track: 'kubernetes', level: 'working',
    q: 'What is the difference between a Deployment, a ReplicaSet and a Pod?',
    say: [
      'A Pod is the running unit. A ReplicaSet keeps a set number of identical pods alive. A Deployment manages ReplicaSets over time.',
      'You almost always write a Deployment. It creates the ReplicaSet for you.',
      'The Deployment exists for version changes. Change the image and it creates a new ReplicaSet and shifts pods across, keeping the old one so it can roll back.'
    ],
    why: 'ReplicaSet answers how many. Deployment answers which version and how to get there. Separating them makes a rollout an object you can inspect and reverse, rather than an action that already happened.',
    ours: 'Our rollout restart moved both pods onto a new ReplicaSet, visible in the pod names changing while the Deployment name stayed the same.',
    src: 'https://kubernetes.io/docs/concepts/workloads/controllers/deployment/',
    diagram:
      '  Deployment  "2 replicas of v3"\n' +
      '      |\n' +
      '      +--> ReplicaSet v3   desired 2  --> [pod] [pod]\n' +
      '      |\n' +
      '      +--> ReplicaSet v2   desired 0      (kept, so rollback is instant)\n' +
      '      |\n' +
      '      +--> ReplicaSet v1   desired 0\n' +
      '\n' +
      '  rollback = set v2 back to 2 and v3 to 0. no rebuild.'
  },
  {
    id: 'k8s-probes', track: 'kubernetes', level: 'working',
    q: 'What is the difference between a liveness and a readiness probe?',
    say: [
      'Readiness controls traffic. Fail it and the pod leaves Service endpoints but keeps running.',
      'Liveness controls life. Fail it and the kubelet kills the container and restarts it.',
      'Startup probes hold the other two off while a slow application boots.'
    ],
    why: 'Getting these backwards is a classic outage. A liveness probe that is really a readiness check will restart healthy but busy pods under load, removing capacity exactly when you need it.',
    ours: 'The dashboard has health probes defined. We did not test probe failure behaviour specifically.',
    src: 'https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/'
  },
  {
    id: 'k8s-autoscale', track: 'kubernetes', level: 'working',
    q: 'What are the different kinds of autoscaling, and which did you do?',
    say: [
      'Horizontal Pod Autoscaler changes the replica count of a workload based on metrics.',
      'Cluster autoscaler changes the number of nodes when pods cannot be scheduled.',
      'Vertical Pod Autoscaler changes the CPU and memory requests of pods.',
      'They solve different problems and are often used together.'
    ],
    why: 'HPA needs a metrics source. Without Metrics Server there is no resource metrics API, so HPA has nothing to read and will not act. That is a missing component, not a missing feature.',
    ours: 'We proved manual scale, 2 to 3 and back to 2. We did not run HPA because Metrics Server was never installed. AKS Arc does support the cluster autoscaler.',
    src: 'https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/'
  },
  {
    id: 'k8s-svctypes', track: 'kubernetes', level: 'working',
    q: 'What are the Service types and how do you reach a workload from outside?',
    say: [
      'ClusterIP is the default and is reachable only inside the cluster.',
      'NodePort opens the same port on every node.',
      'LoadBalancer asks the environment for an external address, which requires something able to provide one.',
      'Ingress is a separate layer routing HTTP by host and path to Services.'
    ],
    why: 'LoadBalancer is not magic. In a cloud it calls the cloud provider. On hardware there is nothing to call unless you install something that hands out addresses, which is what MetalLB does.',
    ours: 'Ours is ClusterIP, proven internally. External needs MetalLB, which needs a provider registration we chose not to escalate.',
    src: 'https://kubernetes.io/docs/concepts/services-networking/service/'
  },
  {
    id: 'k8s-controlplane', track: 'kubernetes', level: 'working',
    q: 'What are the moving parts of a Kubernetes cluster?',
    say: [
      'The API server is the front door and the only component that talks to storage.',
      'etcd holds all cluster state.',
      'The scheduler decides which node a new pod goes on.',
      'Controller manager runs the reconciliation loops.',
      'On every node, the kubelet starts and watches containers, and kube-proxy handles Service routing.'
    ],
    why: 'Everything is mediated by the API server. Components do not talk to each other directly, they watch the API and act. That is why the system is extensible: a new controller is just another watcher.',
    ours: 'Ours is a managed AKS Arc cluster, so the control plane is a VM the platform created and manages for us.',
    src: 'https://kubernetes.io/docs/concepts/overview/components/',
    diagram:
      '            +-------------+\n' +
      '  kubectl ->|  api server |<- every component watches here\n' +
      '            +-------------+\n' +
      '              |   ^   ^  ^\n' +
      '       writes |   |   |  |\n' +
      '              v   |   |  |\n' +
      '           [etcd] |   |  +---- controller manager (loops)\n' +
      '                  |   +------- scheduler (picks nodes)\n' +
      '                  +----------- kubelet on each node\n' +
      '\n' +
      '  nothing talks to anything except the api server.'
  },
  {
    id: 'k8s-scheduler', track: 'kubernetes', level: 'working',
    q: 'How does the scheduler decide where a pod goes?',
    say: [
      'It filters nodes that cannot take the pod, then scores the ones that can and picks the best.',
      'Filters include resource requests, node selectors, taints and tolerations.',
      'Scoring prefers spreading workloads and nodes with more free room.',
      'You can influence it with affinity, anti affinity and topology spread constraints.'
    ],
    why: 'Requests are the thing that actually drives scheduling, not limits and not real usage. A pod with no requests is nearly free to schedule anywhere, which is how nodes end up overcommitted.',
    ours: 'Both our pods landed on the same node because there is only one worker. On a real cluster you would use anti affinity to force them apart.',
    src: 'https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/'
  },
  {
    id: 'k8s-requests-limits', track: 'kubernetes', level: 'working',
    q: 'What is the difference between a resource request and a limit?',
    say: [
      'A request is what the scheduler reserves for you. It decides placement.',
      'A limit is the ceiling enforced at runtime.',
      'Over the CPU limit a container is throttled. Over the memory limit it is killed, which shows as OOMKilled.'
    ],
    why: 'The asymmetry is the point. CPU is compressible so you get slowed down. Memory is not, so you get terminated. That is why a memory limit set too low looks like a mysterious restart loop.',
    ours: 'Not exercised here. Our workload is tiny and the cluster was never under pressure.',
    src: 'https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/'
  },
  {
    id: 'k8s-config-secret', track: 'kubernetes', level: 'working',
    q: 'How do you get configuration and secrets into a pod?',
    say: [
      'ConfigMap for non sensitive configuration, Secret for sensitive values.',
      'Both can be mounted as files or injected as environment variables.',
      'Secrets are base64 encoded, not encrypted, unless you turn on encryption at rest.'
    ],
    why: 'Base64 is encoding, not protection, and people assume otherwise. Anyone who can read the Secret object can read the value, which makes RBAC on Secrets the actual control.',
    ours: 'The dashboard page itself is delivered from a ConfigMap, which is why we could change the UI without building a new image.',
    src: 'https://kubernetes.io/docs/concepts/configuration/secret/'
  },
  {
    id: 'k8s-namespace-rbac', track: 'kubernetes', level: 'working',
    q: 'How is access controlled inside a cluster?',
    say: [
      'A Role grants verbs on resource types. A RoleBinding gives it to a subject in one namespace. ClusterRole and ClusterRoleBinding do the same cluster wide.',
      'Workloads authenticate as a ServiceAccount, which is what you bind permissions to.',
      'Kubernetes RBAC is separate from the cloud identity that got you to the cluster.'
    ],
    why: 'That last point catches people. Being an Azure owner does not make you a Kubernetes administrator. They are two authorisation systems in sequence, and you can pass the first and fail the second.',
    ours: 'We hit exactly this. Our user kubeconfig authenticated and then had no Kubernetes permissions. The dashboard itself is limited to get, list and watch in one namespace.',
    src: 'https://kubernetes.io/docs/reference/access-authn-authz/rbac/'
  },
  {
    id: 'k8s-troubleshoot', track: 'kubernetes', level: 'working',
    q: 'A pod is not running. How do you work out why?',
    say: [
      'kubectl get pod tells you the phase. Pending, ContainerCreating, CrashLoopBackOff, ImagePullBackOff each point somewhere different.',
      'kubectl describe pod shows the events, which is usually where the real answer is.',
      'kubectl logs shows what the container said, and logs --previous shows what it said before it last died.',
      'Pending is usually scheduling. ImagePull is registry or credentials. CrashLoop is the application.'
    ],
    why: 'Reading the phase before the logs saves time. Pending means it never started, so logs will be empty and the answer is in events. People often go to logs first and learn nothing.',
    ours: 'Our self heal run shows the normal happy path of that sequence, Pending then ContainerCreating then Running.',
    src: 'https://kubernetes.io/docs/tasks/debug/debug-application/'
  },

  /* ---------- pressed ---------- */

  {
    id: 'k8s-rolling', track: 'kubernetes', level: 'pressed',
    q: 'How does a rolling update avoid dropping requests, and when does it not?',
    say: [
      'maxSurge is how many extra pods it may create above the desired count. maxUnavailable is how many it may take away.',
      'They are percentages by default and floor to whole pods, so at small replica counts the effective value can be zero.',
      'With maxUnavailable at zero it must bring a new ready pod up before removing an old one.'
    ],
    why: 'The percentage flooring is what people miss. At two replicas, twenty five percent floors to zero, forcing a strictly additive rollout. That is a safe default that quietly stops being true at larger replica counts.',
    ours: 'We sampled ready endpoints every 250ms across 34 samples during a rollout. The minimum was 2, so it never dropped. One retiring pod exited Error because the workload ignores SIGTERM.',
    src: 'https://kubernetes.io/docs/concepts/workloads/controllers/deployment/',
    diagram:
      '  2 replicas, maxSurge 25% -> 0, maxUnavailable 25% -> 0\n' +
      '  both floor to zero, so it borrows one surge pod\n' +
      '\n' +
      '  start    [v1] [v1]\n' +
      '  step 1   [v1] [v1] [v2 starting]     surge to 3\n' +
      '  step 2   [v1] [v1] [v2 READY]        only now is it counted\n' +
      '  step 3   [v1]      [v2]   [v2 start] old one removed\n' +
      '  end           [v2] [v2]\n' +
      '\n' +
      '  ready endpoints never went below 2.'
  },
  {
    id: 'k8s-sigterm', track: 'kubernetes', level: 'pressed',
    q: 'What happens to in flight requests when Kubernetes stops a pod?',
    say: [
      'The pod is removed from Service endpoints and sent SIGTERM at roughly the same time.',
      'It then has a grace period, thirty seconds by default, to finish and exit.',
      'If it has not exited by then it gets SIGKILL and anything in flight is lost.'
    ],
    why: 'Endpoint removal and SIGTERM are not strictly ordered, so a well behaved application keeps serving briefly after being told to stop. One that ignores SIGTERM is killed at the end of the grace period, showing a non zero exit.',
    ours: 'A real defect worth owning. One retiring pod exited Error during our rollout because the container does not handle SIGTERM. It cost nothing here and would under load.',
    src: 'https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/'
  },
  {
    id: 'k8s-statefulset', track: 'kubernetes', level: 'pressed',
    q: 'When would you use a StatefulSet or a DaemonSet instead of a Deployment?',
    say: [
      'Deployment is for interchangeable replicas where nothing depends on which one is which.',
      'StatefulSet gives stable names, stable storage per pod, and ordered start and stop. Databases and anything with per instance identity.',
      'DaemonSet runs one pod per node. Agents, log collectors, monitoring.'
    ],
    why: 'The distinction is identity. A Deployment pod is disposable and anonymous. A StatefulSet pod is pod-0 and comes back as pod-0 with the same volume, which is what clustered software needs to rejoin correctly.',
    ours: 'We used a Deployment, correct for a stateless page. Nothing here needed StatefulSet or DaemonSet.',
    src: 'https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/'
  },
  {
    id: 'k8s-pdb', track: 'kubernetes', level: 'pressed',
    q: 'What stops a node drain from taking your whole application down?',
    say: [
      'A PodDisruptionBudget. It says how many pods of a set must stay available during voluntary disruption.',
      'Voluntary means drains and evictions. It does not protect against a node failing outright.',
      'Without one, draining a node can evict every replica at once if they are all on that node.'
    ],
    why: 'The voluntary distinction is the one to state. A PDB constrains the eviction API, so it protects you from your own maintenance, not from hardware. Nothing can protect against losing the only node you were running on.',
    ours: 'We do not have one, and we name it in the boundary panel as part of what a production pattern would need.',
    src: 'https://kubernetes.io/docs/concepts/workloads/pods/disruptions/'
  },
  {
    id: 'k8s-networkpolicy', track: 'kubernetes', level: 'pressed',
    q: 'By default, which pods can talk to which?',
    say: [
      'All of them. The default is a flat network where every pod can reach every other pod.',
      'NetworkPolicy restricts that, and it needs a CNI plugin that implements it.',
      'Policies are additive and default deny only starts once a policy selects a pod.'
    ],
    why: 'This surprises people who assume namespaces isolate. They do not. Until you write a policy, a compromised pod in one namespace has network reach to everything in the cluster.',
    ours: 'Not implemented. Our dashboard is read only against the API, but nothing constrains pod to pod traffic.',
    src: 'https://kubernetes.io/docs/concepts/services-networking/network-policies/'
  }
]);
