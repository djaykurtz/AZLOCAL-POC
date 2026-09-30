/*
 * Commands, attached to cards by id.
 *
 * Kept separate from the card text on purpose. Commands are the part most likely to be wrong,
 * to drift, or to need adding to in bulk, and having them in one file means they can be reviewed
 * as a set rather than hunted through five deck files.
 *
 * Two fields per entry:
 *   cmds   what to run. A line starting with # renders as a comment rather than a command.
 *   help   the built in way to find these yourself. Every entry that has commands has this,
 *          because remembering flags is a losing game and knowing how to ask the tool is not.
 *
 * shell: 'ps' switches the prompt to PowerShell. Default is a posix shell.
 */

window.CMDS = {

  /* ---------------- kubernetes ---------------- */

  'k8s-kubectl': {
    cmds: [
      'kubectl config get-contexts        # which clusters do I know about',
      'kubectl config use-context <name>  # switch between them',
      'kubectl cluster-info               # is this thing reachable at all',
      'kubectl get nodes -o wide'
    ],
    help: [
      'kubectl --help                     # every top level verb',
      'kubectl get --help                 # flags for one verb, with examples',
      'kubectl api-resources              # every object type, and its short name'
    ]
  },
  'k8s-manifest': {
    cmds: [
      'kubectl apply -f dashboard.yaml    # register desired state',
      'kubectl apply -f ./manifests/      # a whole directory',
      'kubectl get deploy web -o yaml     # what the cluster actually stored',
      'kubectl diff -f dashboard.yaml     # what would change, before applying',
      'kubectl delete -f dashboard.yaml'
    ],
    help: [
      'kubectl explain deployment                    # what fields exist',
      'kubectl explain deployment.spec.strategy      # drill into any field',
      '# explain reads the live API schema, so it is never out of date'
    ]
  },
  'k8s-labels': {
    cmds: [
      'kubectl get pods --show-labels',
      'kubectl get pods -l app=dashboard          # select by label',
      'kubectl get pods -l \'env in (dev,test)\'',
      'kubectl label pod mypod tier=frontend'
    ],
    help: [
      'kubectl get --help                         # the -l and -o flags',
      'kubectl explain pod.metadata.labels'
    ]
  },
  'k8s-deploy-rs': {
    cmds: [
      'kubectl get deploy,rs,pods                 # all three layers at once',
      'kubectl rollout status deploy/web',
      'kubectl rollout history deploy/web',
      'kubectl rollout undo deploy/web            # back to the previous ReplicaSet'
    ],
    help: [
      'kubectl rollout --help',
      'kubectl explain deployment.spec.revisionHistoryLimit'
    ]
  },
  'k8s-service': {
    cmds: [
      'kubectl get svc',
      'kubectl get endpointslice                  # who is actually behind it',
      'kubectl describe svc web',
      'kubectl port-forward svc/web 8080:80       # reach it from your laptop'
    ],
    help: [
      'kubectl explain service.spec',
      'kubectl explain service.spec.type          # ClusterIP, NodePort, LoadBalancer'
    ]
  },
  'k8s-probes': {
    cmds: [
      'kubectl describe pod web-abc123            # probe results appear in Events',
      'kubectl get pod web-abc123 -o jsonpath=\'{.status.containerStatuses[0].ready}\''
    ],
    help: [
      'kubectl explain pod.spec.containers.readinessProbe',
      'kubectl explain pod.spec.containers.livenessProbe'
    ]
  },
  'k8s-troubleshoot': {
    cmds: [
      'kubectl get pods                           # start with the phase',
      'kubectl describe pod web-abc123            # Events is usually the answer',
      'kubectl logs web-abc123',
      'kubectl logs web-abc123 --previous         # what it said before it died',
      'kubectl logs -f deploy/web                 # follow',
      'kubectl exec -it web-abc123 -- sh          # look around inside',
      'kubectl get events --sort-by=.lastTimestamp'
    ],
    help: [
      'kubectl logs --help',
      'kubectl describe --help'
    ]
  },
  'k8s-rolling': {
    cmds: [
      'kubectl rollout restart deploy/web         # replace every pod, same image',
      'kubectl set image deploy/web web=myimage:v3',
      'kubectl rollout status deploy/web',
      'kubectl rollout undo deploy/web'
    ],
    help: [
      'kubectl explain deployment.spec.strategy.rollingUpdate',
      '# maxSurge and maxUnavailable are documented right there'
    ]
  },
  'k8s-autoscale': {
    cmds: [
      'kubectl scale deploy/web --replicas=3      # manual',
      'kubectl autoscale deploy/web --min=2 --max=5 --cpu-percent=70',
      'kubectl get hpa',
      'kubectl top pods                           # needs Metrics Server'
    ],
    help: [
      'kubectl autoscale --help',
      'kubectl explain horizontalpodautoscaler.spec'
    ]
  },
  'k8s-scheduler': {
    cmds: [
      'kubectl get pods -o wide                   # which node each pod landed on',
      'kubectl describe node moc-worker-01        # allocated vs allocatable',
      'kubectl describe pod web-abc123            # scheduling failures show here'
    ],
    help: [
      'kubectl explain pod.spec.affinity',
      'kubectl explain pod.spec.tolerations'
    ]
  },
  'k8s-requests-limits': {
    cmds: [
      'kubectl describe node moc-worker-01        # requests vs capacity',
      'kubectl top pods                           # actual usage',
      'kubectl get pod web-abc123 -o jsonpath=\'{.spec.containers[0].resources}\''
    ],
    help: [
      'kubectl explain pod.spec.containers.resources'
    ]
  },
  'k8s-config-secret': {
    cmds: [
      'kubectl create configmap app-cfg --from-file=./index.html',
      'kubectl create secret generic db --from-literal=password=hunter2',
      'kubectl get secret db -o jsonpath=\'{.data.password}\' | base64 -d',
      '# that last line is the point: base64 is encoding, not protection'
    ],
    help: [
      'kubectl create configmap --help',
      'kubectl explain secret'
    ]
  },
  'k8s-namespace-rbac': {
    cmds: [
      'kubectl auth can-i create deployments               # can I, here',
      'kubectl auth can-i delete pods --all-namespaces',
      'kubectl auth can-i list secrets --as=system:serviceaccount:app:reader',
      'kubectl get rolebinding,clusterrolebinding -A'
    ],
    help: [
      'kubectl auth can-i --help',
      '# can-i is the fastest way to answer why is this being denied'
    ]
  },
  'k8s-controlplane': {
    cmds: [
      'kubectl cluster-info',
      'kubectl get nodes -o wide',
      'kubectl get pods -n kube-system            # the control plane components',
      'kubectl version'
    ],
    help: [
      'kubectl cluster-info --help',
      'kubectl api-versions'
    ]
  },
  'k8s-pdb': {
    cmds: [
      'kubectl get pdb',
      'kubectl drain moc-worker-01 --ignore-daemonsets   # respects budgets',
      'kubectl uncordon moc-worker-01'
    ],
    help: [
      'kubectl drain --help',
      'kubectl explain poddisruptionbudget.spec'
    ]
  },

  /* ---------------- terraform ---------------- */

  'tf-workflow': {
    cmds: [
      'terraform init          # download providers, set up the backend',
      'terraform fmt           # tidy the files',
      'terraform validate      # is the config even valid',
      'terraform plan          # what would change',
      'terraform apply         # do it',
      'terraform destroy       # remove what terraform owns'
    ],
    help: [
      'terraform -help                # every subcommand',
      'terraform plan -help           # flags for one subcommand'
    ]
  },
  'tf-plan': {
    cmds: [
      'terraform plan -out=tfplan     # save the plan as a file',
      'terraform show tfplan          # read it back, human readable',
      'terraform show -json tfplan    # read it back, machine readable',
      'terraform apply tfplan         # apply exactly what was reviewed'
    ],
    help: [
      'terraform plan -help',
      '# applying a saved plan is what makes the review meaningful in a pipeline'
    ]
  },
  'tf-state': {
    cmds: [
      'terraform state list                    # everything terraform believes it owns',
      'terraform state show azurerm_resource_group.rg',
      'terraform state rm <address>            # forget it without destroying it',
      'terraform state mv <old> <new>          # after renaming a resource block'
    ],
    help: [
      'terraform state -help',
      '# state rm is how you release ownership. it does not touch the real object'
    ]
  },
  'tf-drift': {
    cmds: [
      'terraform plan -refresh-only    # what changed outside terraform',
      'terraform apply -refresh-only   # accept reality into state, change nothing'
    ],
    help: [
      'terraform plan -help',
      '# refresh-only is the honest way to look at drift before deciding'
    ]
  },
  'tf-vars': {
    cmds: [
      'terraform apply -var="location=southcentralus"',
      'terraform apply -var-file="dev.tfvars"',
      'terraform output',
      'terraform output -raw vm_id'
    ],
    help: [
      'terraform apply -help',
      'terraform output -help'
    ]
  },
  'tf-provider': {
    cmds: [
      'terraform init -upgrade    # pick up newer provider versions',
      'terraform providers        # what this config requires',
      'terraform version'
    ],
    help: [
      'terraform providers -help',
      '# the provider docs on the registry are the real reference for resource fields'
    ]
  },
  'tf-import': {
    cmds: [
      'terraform import azurerm_resource_group.rg /subscriptions/.../resourceGroups/my-rg',
      'terraform plan            # must come back with no changes',
      '# if the plan wants to change things, your config does not match reality yet'
    ],
    help: [
      'terraform import -help',
      '# every resource page in the provider docs ends with its import syntax'
    ]
  },
  'tf-backend': {
    cmds: [
      'terraform init -migrate-state    # move local state to a remote backend',
      'terraform init -reconfigure',
      'terraform force-unlock <lock-id> # only when a run died holding the lock'
    ],
    help: [
      'terraform init -help'
    ]
  },

  /* ---------------- docker ---------------- */

  'dk-commands': {
    cmds: [
      'docker run -d --name web -p 8080:80 nginx',
      'docker ps                 # running',
      'docker ps -a              # including stopped',
      'docker logs -f web',
      'docker exec -it web sh    # a shell inside a running container',
      'docker stop web && docker rm web',
      'docker images',
      'docker rmi nginx'
    ],
    help: [
      'docker --help             # every command',
      'docker run --help         # flags for one command',
      'docker inspect web        # everything the daemon knows about it'
    ]
  },
  'dk-image-container': {
    cmds: [
      'docker run --rm hello-world     # --rm deletes it when it exits',
      'docker ps -a                    # proof that it is gone',
      'docker images'
    ],
    help: [
      'docker run --help',
      'docker image --help'
    ]
  },
  'dk-dockerfile': {
    cmds: [
      'docker build -t myapp:1.0 .',
      'docker build -t myapp:1.0 -f Dockerfile.prod .',
      'docker history myapp:1.0        # the layers, and what each one cost'
    ],
    help: [
      'docker build --help',
      'docker history --help'
    ]
  },
  'dk-layers': {
    cmds: [
      'docker history myapp:1.0        # layer sizes, biggest offender first',
      'docker build --no-cache -t myapp:1.0 .',
      'docker system df                # what the cache is costing you',
      'docker builder prune'
    ],
    help: [
      'docker history --help',
      'docker system df --help'
    ]
  },
  'dk-tags': {
    cmds: [
      'docker pull mcr.microsoft.com/azure-cli:2.61.0',
      'docker tag myapp:1.0 myregistry.azurecr.io/myapp:1.0',
      'docker push myregistry.azurecr.io/myapp:1.0',
      'docker inspect --format=\'{{index .RepoDigests 0}}\' myapp:1.0   # the immutable digest'
    ],
    help: [
      'docker image --help',
      'docker login --help'
    ]
  },
  'dk-ports': {
    cmds: [
      'docker run -d -p 8080:80 nginx          # host 8080 -> container 80',
      'docker port web',
      'docker network ls',
      'docker network create appnet            # containers here resolve each other by name'
    ],
    help: [
      'docker run --help',
      'docker network --help'
    ]
  },
  'dk-persist': {
    cmds: [
      'docker volume create appdata',
      'docker run -v appdata:/var/lib/data myapp     # volume',
      'docker run -v /home/me/src:/src myapp         # bind mount',
      'docker volume ls',
      'docker volume inspect appdata'
    ],
    help: [
      'docker volume --help',
      'docker run --help'
    ]
  },
  'dk-restart': {
    cmds: [
      'docker run -d --restart unless-stopped myapp',
      'docker update --restart=always web       # change it on a running container',
      'docker inspect -f \'{{.HostConfig.RestartPolicy.Name}}\' web'
    ],
    help: [
      'docker run --help',
      'docker update --help'
    ]
  },
  'dk-compose': {
    cmds: [
      'docker compose up -d',
      'docker compose ps',
      'docker compose logs -f web',
      'docker compose down          # add -v to remove volumes too',
      'docker compose config        # the merged file, after variables'
    ],
    help: [
      'docker compose --help',
      'docker compose up --help'
    ]
  },
  'dk-logs': {
    cmds: [
      'docker logs web',
      'docker logs -f --tail 100 web',
      'docker logs --since 10m web'
    ],
    help: [
      'docker logs --help'
    ]
  },

  /* ---------------- azure local ---------------- */

  'al-cluster-vm': {
    shell: 'ps',
    cmds: [
      'Get-ClusterNode',
      'Get-ClusterGroup | Where-Object GroupType -eq VirtualMachine',
      'Start-ClusterGroup -Name rocky-docker-01',
      'Get-VM -Name rocky-docker-01        # run this ON the owner node, not through it'
    ],
    help: [
      'Get-Help Get-ClusterGroup -Full',
      'Get-Help Get-ClusterGroup -Examples      # usually the fastest way in',
      'Get-Command -Module FailoverClusters     # everything the module can do'
    ]
  },
  'al-s2d': {
    shell: 'ps',
    cmds: [
      'Get-StoragePool',
      'Get-PhysicalDisk | Select-Object FriendlyName, HealthStatus, Usage',
      'Get-VirtualDisk | Select-Object FriendlyName, HealthStatus, OperationalStatus',
      'Get-PhysicalDisk | Where-Object CanPool -eq $true'
    ],
    help: [
      'Get-Command -Module Storage',
      'Get-Help Get-VirtualDisk -Examples',
      'Get-VirtualDisk | Get-Member              # what properties actually exist'
    ]
  },
  'al-degraded': {
    shell: 'ps',
    cmds: [
      'Get-VirtualDisk | Where-Object HealthStatus -ne Healthy',
      'Get-StorageJob                            # repairs, and their progress',
      'Get-StorageSubSystem | Get-StorageHealthReport'
    ],
    help: [
      'Get-Help Get-StorageJob -Full',
      'Get-Command *StorageJob*'
    ]
  },
  'al-livemigrate': {
    shell: 'ps',
    cmds: [
      'Move-ClusterVirtualMachineRole -Name <vm> -Node AZL-NODE-04 -MigrationType Live',
      'Get-ClusterGroup -Name <vm> | Select-Object Name, OwnerNode, State'
    ],
    help: [
      'Get-Help Move-ClusterVirtualMachineRole -Full',
      'Get-Help Move-ClusterVirtualMachineRole -Parameter MigrationType'
    ]
  },
  'al-refusal': {
    shell: 'ps',
    cmds: [
      'Enable-StorageMaintenanceMode -InputObject <disk>',
      'Suspend-ClusterNode -Name AZL-NODE-01 -Drain',
      'Suspend-ClusterNode -Name AZL-NODE-01 -ForceDrain    # still refused, correctly',
      'Stop-ClusterNode -Name AZL-NODE-01                   # leave, rather than ask to pause'
    ],
    help: [
      'Get-Help Suspend-ClusterNode -Full',
      'Get-Command -Module FailoverClusters -Name *ClusterNode*'
    ]
  },
  'al-fabrics': {
    shell: 'ps',
    cmds: [
      'Get-NetAdapter | Where-Object Status -eq Up',
      'Get-NetAdapterAdvancedProperty -Name Port3',
      'Test-NetConnection -Source Port3 -ComputerName 10.40.1.185',
      'Get-NetIPConfiguration'
    ],
    help: [
      'Get-Command -Module NetAdapter',
      'Get-Help Test-NetConnection -Examples'
    ]
  },
  'al-arc': {
    cmds: [
      'az connectedmachine list -g rg-azlocal-poc-001 -o table',
      'az stack-hci cluster list -o table',
      'az customlocation list -o table'
    ],
    help: [
      'az connectedmachine --help',
      'az find "az connectedmachine"     # examples pulled from real usage',
      'az interactive                    # autocomplete and inline docs'
    ]
  },
  'al-updates': {
    shell: 'ps',
    cmds: [
      'Get-SolutionUpdateEnvironment      # what version am I on, is anything waiting',
      'Get-SolutionUpdate                 # the available updates and their state',
      'Invoke-SolutionUpdatePrecheck      # check readiness before committing',
      'Start-SolutionUpdate               # begin the node by node roll',
      'Get-SolutionUpdateRun              # watch it, step by step',
      '# Az.StackHCI also has Get-AzStackHciUpdate for the Azure side of the same thing'
    ],
    help: [
      'Get-Command -Module Microsoft.AzureStack.Lcm.PowerShell',
      'Get-Help Start-SolutionUpdate -Full',
      'Get-Help Get-SolutionUpdate -Examples'
    ]
  },

  'al-winupdate': {
    shell: 'ps',
    cmds: [
      'Get-ComputerInfo -Property OsBuildNumber, OsVersion',
      'Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5',
      'Get-StampInformation                    # the solution version the platform expects',
      '# do NOT run sconfig option 6, or wuauclt, or Install-WindowsUpdate here'
    ],
    help: [
      'Get-Help Get-StampInformation -Full',
      'Get-Command -Module Microsoft.AzureStack.Lcm.PowerShell'
    ]
  },

  'al-sconfig': {
    shell: 'ps',
    cmds: [
      'Get-ItemProperty \'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\' |',
      '  Select-Object ProductName, EditionID, DisplayVersion, CurrentBuild, UBR',
      'Get-Module -ListAvailable -Name SConfig      # generic Server Core module',
      'Get-Service wuauserv                         # Manual and Stopped, on purpose'
    ],
    help: [
      'Get-Help Get-Service -Examples',
      'Get-Command -Module Microsoft.ServerCore.SConfig'
    ]
  },

  'al-aks': {
    cmds: [
      'az aksarc list -g rg-azlocal-poc-001 -o table',
      'az aksarc get-credentials -g <rg> -n <cluster> --admin',
      'kubectl get nodes -o wide'
    ],
    help: [
      'az aksarc --help',
      'az aksarc create --help          # where the autoscaler flags are documented'
    ]
  }
};

// Attached rather than inlined, so the command set can be reviewed and extended in one place.
(function () {
  if (!window.DECK) return;
  Object.keys(window.CMDS).forEach(function (id) {
    var card = window.DECK.find(function (d) { return d.id === id; });
    if (!card) return;
    var entry = window.CMDS[id];
    card.cmds = entry.cmds;
    card.help = entry.help;
    card.shell = entry.shell || 'sh';
  });
})();
