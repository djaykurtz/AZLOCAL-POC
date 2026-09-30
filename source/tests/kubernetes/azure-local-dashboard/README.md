# Azure Local dashboard workload scaffold

This folder prepares the Kubernetes-only prerequisites for the future read-only Azure Local dashboard.

Apply the namespace and RBAC first:

```powershell
$env:KUBECONFIG = "$PWD\out\kube\azl-cluster-01-aks-01-admin.config"
$env:Path = "$PWD\out\tools;$env:Path"
kubectl apply -f tests/kubernetes/azure-local-dashboard/00-namespace-and-rbac.yaml
kubectl apply -f tests/kubernetes/azure-local-dashboard/10-fixture-configmap.yaml
```

The ServiceAccount can only read workload state in its own namespace. It has no Kubernetes write permission.

`inventory.json` is fixture data for the first dashboard UI. Replace it with an Azure Reader-only backend only after a dedicated workload identity or equivalent least-privilege Azure authentication method is selected.

Do not mount the administrator kubeconfig or use a developer PIM credential in the workload.

Apply the first two-replica dashboard UI workload:

```powershell
kubectl apply -f tests/kubernetes/azure-local-dashboard/20-dashboard-ui.yaml
kubectl -n azure-local-dashboard rollout status deployment/azure-local-dashboard
kubectl -n azure-local-dashboard get deployment,pods,service -o wide
```

The first workload uses a ConfigMap-mounted Python web server in a Microsoft-maintained Azure CLI container
image. It displays a server-side market-data query (SPY) and the serving pod identity from the Kubernetes
Downward API. This avoids a new registry or custom build pipeline while keeping the deployment self-contained.
Market data is informational and may be delayed or temporarily unavailable. The service is reachable through
its ClusterIP inside the cluster and will move to `LoadBalancer` only after MetalLB is configured.

The page refreshes its quote, serving-pod, and bounded-work panels every 10 seconds. Each refresh invokes a
small CPU-bound endpoint in the serving replica. Requests are `200m` CPU and limits are `500m` CPU per replica,
which is enough to show live request distribution and Kubernetes resource accounting without treating the
constrained single-worker POC cluster as a load-test environment.

## Kubernetes Lab

The page includes a read-only Kubernetes Lab panel. It reads the dashboard namespace's Deployment, ReplicaSets,
pods, Service EndpointSlices, and relevant Events through the workload ServiceAccount. The controls can refresh
state, issue one bounded work request, or issue one bounded request per second for 10 seconds. They cannot scale,
restart, create, patch, or delete Kubernetes resources.

## Under-the-hood preview

The page includes a live flow canvas as a miniature of the planned capstone learning environment. It combines
read-only live Kubernetes state with explicitly labeled recorded evidence:

```text
Source validation (planned workflow)
-> Terraform lifecycle (verified POC evidence)
-> AKS worker (live pod placement)
-> ClusterIP Service (live EndpointSlices)
-> Kubernetes pods (live desired/ready state)
```

The Terraform and GitHub Actions nodes are evidence modules, not browser controls. The page does not start a
workflow, create a VM, or scale the cluster.

## In-cluster routing test

`30-service-routing-load.yaml` is a bounded client Job that sends 90 independent HTTP requests to the dashboard
ClusterIP Service from inside AKS. It disables connection reuse, records the responding pod for each request, and
exits after about nine seconds. It is a POC Service-routing demonstration, not a throughput or stress test.

Run it only after an operator has scaled the dashboard to three replicas:

```powershell
kubectl -n azure-local-dashboard scale deployment/azure-local-dashboard --replicas=3
kubectl -n azure-local-dashboard rollout status deployment/azure-local-dashboard
kubectl apply -f tests/kubernetes/azure-local-dashboard/30-service-routing-load.yaml
kubectl -n azure-local-dashboard wait --for=condition=complete job/azure-local-dashboard-routing-load --timeout=180s
kubectl -n azure-local-dashboard logs job/azure-local-dashboard-routing-load
kubectl -n azure-local-dashboard scale deployment/azure-local-dashboard --replicas=2
kubectl -n azure-local-dashboard rollout status deployment/azure-local-dashboard
```

The output must show all requests succeeded and responses from more than one ready dashboard pod. It does not
prove external traffic, an external VIP, internet ingress, or performance capacity.

## Access from the Cloud PC

The dashboard Service is intentionally `ClusterIP` only. Reach it from the Cloud PC with a local Kubernetes
port-forward:

```powershell
$env:KUBECONFIG = "$PWD\out\kube\azl-cluster-01-aks-01-admin.config"
$env:Path = "$PWD\out\tools;$env:Path"
kubectl -n azure-local-dashboard port-forward service/azure-local-dashboard 8080:80
```

Open [http://localhost:8080](http://localhost:8080) on that same Cloud PC.

```text
Browser on Cloud PC -> localhost:8080
localhost:8080 -> kubectl port-forward
kubectl port-forward -> azure-local-dashboard ClusterIP Service:80
ClusterIP Service:80 -> one ready dashboard pod:8080 in AKS Arc
```

This creates a local tunnel only. It is not a public endpoint, is not reachable from other machines, and
stops when the `kubectl port-forward` process is stopped. It does not depend on MetalLB, a LoadBalancer VIP,
or the unavailable `Microsoft.KubernetesRuntime` provider registration.

## Tracking contract

The initial application establishes these tracking points for later image, pipeline, and application work:

- `app.kubernetes.io/version` and POC change annotations identify the deployed manifest version and change intent.
- `APP_VERSION` is returned by `/healthz` and added to every HTTP response as `X-App-Version`.
- Each request accepts or creates an `X-Request-ID`, returns it in the response, and emits a structured JSON stdout log with request ID, path, HTTP status, serving pod, and application version.
- The Downward API supplies pod, namespace, and worker-node identity without granting Kubernetes write access.

Future custom images and GitHub Actions workflows should set `APP_VERSION` to an immutable source revision or image tag and retain the same headers and log fields.
