/*
 * Real artifacts from this repo, attached to cards by id.
 *
 * The what we did line was describing our work in the abstract. Installs two packages teaches
 * nothing. The actual file does, because you can see the shape of a real one and recognise it
 * again somewhere else. Everything here is copied from the repo, not written for the card.
 *
 *   file  the path, so it can be opened and checked
 *   body  the excerpt, trimmed to the part worth reading
 */

window.ARTIFACTS = {

  'dk-dockerfile': {
    file: 'tests/docker/smoke/Dockerfile',
    body:
      'FROM mcr.microsoft.com/cbl-mariner/base/core:2.0\n' +
      '\n' +
      'LABEL org.opencontainers.image.title="Azure Local POC smoke container"\n' +
      '\n' +
      'RUN tdnf install -y ca-certificates shadow-utils && tdnf clean all\n' +
      'RUN useradd --create-home --shell /sbin/nologin appuser\n' +
      'USER appuser\n' +
      '\n' +
      'CMD ["/bin/sh", "-c", "echo Azure Local POC smoke container ready && sleep 3600"]'
  },

  'dk-base-image': {
    file: 'tests/docker/smoke/Dockerfile',
    body:
      'FROM mcr.microsoft.com/cbl-mariner/base/core:2.0\n' +
      '\n' +
      '# mcr, not Docker Hub, so there is no pull rate limit\n' +
      '# core, not full, so the image carries as little as possible\n' +
      '# tdnf is the package manager, because Mariner is not Debian or Alpine'
  },

  'dk-security': {
    file: 'tests/docker/smoke/Dockerfile',
    body:
      'RUN tdnf install -y ca-certificates shadow-utils && tdnf clean all\n' +
      'RUN useradd --create-home --shell /sbin/nologin appuser\n' +
      'USER appuser\n' +
      '\n' +
      '# shadow-utils is only there so useradd exists\n' +
      '# nologin means the account cannot be used for a shell\n' +
      '# USER applies to every layer after it, and to the running container'
  },

  'k8s-manifest': {
    file: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml',
    body:
      'kind: Deployment\n' +
      'metadata:\n' +
      '  name: azure-local-dashboard\n' +
      'spec:\n' +
      '  replicas: 2\n' +
      '  selector:\n' +
      '    matchLabels:\n' +
      '      app.kubernetes.io/name: azure-local-dashboard\n' +
      '  template:\n' +
      '    metadata:\n' +
      '      labels:\n' +
      '        app.kubernetes.io/name: azure-local-dashboard   # must match the selector\n' +
      '    spec:\n' +
      '      serviceAccountName: azure-local-dashboard\n' +
      '      containers:\n' +
      '        - name: web\n' +
      '          image: mcr.microsoft.com/azure-cli:latest\n' +
      '          command: [python3, /dashboard/server.py]'
  },

  'k8s-labels': {
    file: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml',
    body:
      '# the Deployment finds its pods this way\n' +
      'spec.selector.matchLabels:\n' +
      '  app.kubernetes.io/name: azure-local-dashboard\n' +
      '\n' +
      '# the Service finds the same pods, independently, the same way\n' +
      'spec.selector:\n' +
      '  app.kubernetes.io/name: azure-local-dashboard\n' +
      '\n' +
      '# neither one names a pod. that is why a replacement just works.'
  },

  'k8s-service': {
    file: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml',
    body:
      'kind: Service\n' +
      'metadata:\n' +
      '  name: azure-local-dashboard\n' +
      'spec:\n' +
      '  type: ClusterIP                 # internal only. no external address.\n' +
      '  selector:\n' +
      '    app.kubernetes.io/name: azure-local-dashboard\n' +
      '  ports:\n' +
      '    - port: 80                    # what callers use\n' +
      '      targetPort: http            # the named port on the container, 8080\n' +
      '\n' +
      '# live: ClusterIP 10.30.1.58:80 -> containerPort 8080'
  },

  'k8s-probes': {
    file: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml',
    body:
      'readinessProbe:                   # controls traffic\n' +
      '  httpGet: { path: /healthz, port: http }\n' +
      '  initialDelaySeconds: 3\n' +
      '  periodSeconds: 5\n' +
      '\n' +
      'livenessProbe:                    # controls restarts\n' +
      '  httpGet: { path: /healthz, port: http }\n' +
      '  initialDelaySeconds: 10         # longer, so a slow start is not a kill\n' +
      '  periodSeconds: 10\n' +
      '\n' +
      '# same endpoint here, which is fine for something this small\n' +
      '# and is the thing you would separate in a real application'
  },

  'k8s-requests-limits': {
    file: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml',
    body:
      'resources:\n' +
      '  requests:                       # what the scheduler reserves\n' +
      '    cpu: 200m                     # 200 millicores, a fifth of one core\n' +
      '    memory: 128Mi\n' +
      '  limits:                         # the ceiling at runtime\n' +
      '    cpu: 500m                     # over this, throttled\n' +
      '    memory: 256Mi                 # over this, OOMKilled'
  },

  'k8s-namespace-rbac': {
    file: 'tests/kubernetes/azure-local-dashboard/00-namespace-and-rbac.yaml',
    body:
      'kind: Role                        # Role, not ClusterRole: one namespace only\n' +
      'metadata:\n' +
      '  name: dashboard-read-status\n' +
      '  namespace: azure-local-dashboard\n' +
      'rules:\n' +
      '  - apiGroups: [""]\n' +
      '    resources: ["pods", "services", "configmaps", "events"]\n' +
      '    verbs: ["get", "list", "watch"]     # no create, no update, no delete\n' +
      '  - apiGroups: ["discovery.k8s.io"]\n' +
      '    resources: ["endpointslices"]\n' +
      '    verbs: ["get", "list", "watch"]\n' +
      '  - apiGroups: ["apps"]\n' +
      '    resources: ["deployments", "replicasets"]\n' +
      '    verbs: ["get", "list", "watch"]'
  },

  'k8s-config-secret': {
    file: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml',
    body:
      '# the whole web page is a ConfigMap, mounted read only as files\n' +
      'volumeMounts:\n' +
      '  - name: dashboard-ui\n' +
      '    mountPath: /dashboard\n' +
      '    readOnly: true\n' +
      'volumes:\n' +
      '  - name: dashboard-ui\n' +
      '    configMap:\n' +
      '      name: azure-local-dashboard-ui\n' +
      '\n' +
      '# which is why the UI could change without building a new image'
  },

  'k8s-pod-why': {
    file: 'tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml',
    body:
      '# the pod tells the container about itself, through the downward API\n' +
      'env:\n' +
      '  - name: POD_NAME\n' +
      '    valueFrom: { fieldRef: { fieldPath: metadata.name } }\n' +
      '  - name: NODE_NAME\n' +
      '    valueFrom: { fieldRef: { fieldPath: spec.nodeName } }\n' +
      '\n' +
      '# this is how the page can say which replica answered you,\n' +
      '# and which node that replica is sitting on'
  },

  'tf-modules': {
    file: 'tests/terraform/azlocal-disposable-vm/main.tf',
    body:
      'module "disposable_vm" {\n' +
      '  source  = "Azure/avm-res-azurestackhci-virtualmachineinstance/azurerm"\n' +
      '  version = "2.1.1"              # pinned. not latest.\n' +
      '\n' +
      '  name                = var.vm_name\n' +
      '  resource_group_name = var.resource_group_name\n' +
      '  custom_location_id  = var.custom_location_id   # not a region\n' +
      '  image_id            = var.image_id\n' +
      '  logical_network_id  = var.logical_network_id\n' +
      '\n' +
      '  os_type        = "Linux"\n' +
      '  v_cpu_count    = var.v_cpu_count\n' +
      '  memory_mb      = var.memory_mb\n' +
      '  dynamic_memory = true\n' +
      '\n' +
      '  tags = {\n' +
      '    managedBy = "terraform"\n' +
      '    ownership = "terraform-only"   # so nobody imports the manual VMs by mistake\n' +
      '  }\n' +
      '}'
  },

  'tf-what': {
    file: 'tests/terraform/azlocal-disposable-vm/main.tf',
    body:
      '# the whole VM is this one module block, and three real resources come out of it:\n' +
      '#   Microsoft.HybridCompute/machines/tf-poc-linux-01\n' +
      '#   Microsoft.AzureStackHCI/networkInterfaces/tf-poc-linux-01-nic\n' +
      '#   Microsoft.AzureStackHCI/virtualMachineInstances/default\n' +
      '\n' +
      'custom_location_id = var.custom_location_id\n' +
      '\n' +
      '# that line is the whole trick. an Azure resource, targeted at our rack\n' +
      '# instead of at a region.'
  },

  'tf-vars': {
    file: 'tests/terraform/azlocal-disposable-vm/main.tf',
    body:
      '# nothing environment specific is written in the module call\n' +
      'name                = var.vm_name\n' +
      'resource_group_name = var.resource_group_name\n' +
      'location            = var.location\n' +
      'admin_username      = var.admin_username\n' +
      'admin_password      = var.admin_password    # marked sensitive in variables.tf\n' +
      '\n' +
      '# sensitive keeps it out of console output. it is still in state, in the clear.'
  },

  'al-aks': {
    file: 'live cluster, 2026-09-02',
    body:
      'NAME              STATUS   ROLES           VERSION\n' +
      'moc-control-plane-01   Ready    control-plane   v1.33.5\n' +
      'moc-worker-01          Ready    <none>          v1.33.5\n' +
      '\n' +
      '# both are Azure Linux 3.0, and both are clustered VMs on Azure Local.\n' +
      '# the worker is the one we live migrated between hosts.'
  },

  'al-s2d': {
    file: 'live cluster, 2026-09-02',
    body:
      'storage pool   SU1_Pool        Healthy / OK\n' +
      'physical disks 12              3 per machine across 4 machines\n' +
      'retired        1 x PM9A1 NVMe  Lost Communication, still in the report\n' +
      '\n' +
      '# the failed drive is still listed. it is retired, not forgotten,\n' +
      '# which is how you can see what happened weeks later.'
  },

  'al-updates': {
    file: 'azl-node-01, live, 2026-09-02',
    body:
      'PS> Get-SolutionUpdateEnvironment\n' +
      '\n' +
      'CurrentVersion : 12.2604.1003.1006\n' +
      'State          : UpdateAvailable\n' +
      'LastChecked    : 9/2/2026 10:42:42 AM\n' +
      '\n' +
      'PS> Get-SolutionUpdate\n' +
      '\n' +
      '2026.08 Cumulative Update | state=Ready | 12.2608.1003.9\n' +
      '\n' +
      'PS> Get-StampInformation\n' +
      '\n' +
      'StampVersion : 12.2604.1003.1006\n' +
      'OemVersion   : 2.1.0.0          # the Dell solution builder extension\n' +
      '\n' +
      '# one version number covers the OS, the agents, the drivers and the firmware.\n' +
      '# there is a real update waiting on this cluster right now.'
  },

  'pr-dashboard': {
    file: 'live cluster, 2026-09-02',
    body:
      '$ kubectl -n azure-local-dashboard exec deploy/azure-local-dashboard \\\n' +
      '    -- curl -s http://localhost:8080/api/quote\n' +
      '\n' +
      '{"symbol": "SPY", "price": 494.997, "currency": "USD",\n' +
      ' "previousClose": 501.02, "change": -6.02,\n' +
      ' "asOf": "2026-09-02T16:05:37Z"}\n' +
      '\n' +
      '# a pod on four second hand machines in a lab, reaching the internet.\n' +
      '# the timestamp moves, which is what makes it evidence rather than a claim.'
  }
};

(function () {
  if (!window.DECK) return;
  Object.keys(window.ARTIFACTS).forEach(function (id) {
    var card = window.DECK.find(function (d) { return d.id === id; });
    if (card) card.artifact = window.ARTIFACTS[id];
  });
})();
