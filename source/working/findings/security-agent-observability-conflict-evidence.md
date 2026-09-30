---
title: "Security monitoring extension and observability agent conflict evidence"
domain: [security, observability]
layer: [os, arc]
type: evidence
status: current
proof: proven
audience: [engineer, leadership]
tags: [security-agent, security-monitoring-agent, security-exception, skip-security-monitoring-agent, policy-exclusion]
updated: 2026-07-23
---

# Security monitoring extension and observability agent conflict evidence

Evidence brief prepared to support a scoped, reversible security exception.

Azure Local could not deploy because an incumbent corporate security monitoring agent held the single
per-host monitoring agent slot, so Azure Local's own agent could never start. This document records
the verbatim on-node errors, how to reproduce them, and the exact change requested.

Resolved by applying the documented `SkipSecurityMonitoringAgent=true` opt-out tag at resource and resource
group scope, rather than by removing a security control outright.

## Reference content

```text
EVIDENCE BRIEF - Azure Local deployment blocked by a conflicting monitoring agent
========================================================================================
Prepared by : platform team
Date        : 2026-07-23
Purpose     : Support a security override / policy-exclusion decision. This document
              states, with verbatim on-node evidence, why an Azure Local deployment
              cannot complete on these machines and exactly what change is being requested.

--------------------------------------------------------------------------------
1. ENVIRONMENT
--------------------------------------------------------------------------------
Tenant             : 00000000-0000-0000-0000-000000000002
Subscription       : contoso-lab-sub  (00000000-0000-0000-0000-000000000001)
Resource group     : rg-azlocal-poc-001
Arc-connected nodes: AZL-NODE-01, -02, -04, -06 (the 4-node POC cluster)
                     (AZL-NODE-03 and -05 are additional physical machines in the same
                      subscription and carry the same agent.)
Workload           : Azure Local (Azure Stack HCI 24H2) cluster deployment via Azure portal.

--------------------------------------------------------------------------------
2. THE BLOCKER, IN ONE SENTENCE
--------------------------------------------------------------------------------
The Azure Local deployment installs its own monitoring agent (MA) as a required
component; the monitoring agent (MA) is a per-host singleton ("one MA service per system"); on these
nodes the corporate security monitoring agent already occupies that single slot, so
the Azure Local monitoring agent can never start and the mandatory
"AzureEdgeTelemetryAndDiagnostics" extension fails on every attempt, halting deployment.

--------------------------------------------------------------------------------
3. VERBATIM EVIDENCE (captured from the nodes 2026-07-23/24 UTC)
--------------------------------------------------------------------------------

3a. Azure-side: the mandatory extension times out (per node)
    Command: az connectedmachine extension show -g rg-azlocal-poc-001
             --machine-name AZL-NODE-04 -n AzureEdgeTelemetryAndDiagnostics
    Verbatim status message:
      "Extension Enable command timed out. ... Extension Message: AzureEdgeCrashDumpCollection
       process is not running. FleetDiagnosticsAgent process is running. MonAgentHost process
       is not running. AzureStack Observability Agent service is running. AzureEMP service is
       running. Execute time: 7/24/2026 12:00:41 AM"
    -> The Azure Local monitoring host process (MonAgentHost) will not run. Note AzureEMP
       (the launcher) IS running, so this is not a start-order problem; MonAgentHost itself
       cannot start.

3b. On-node root cause: the monitoring agent (MA) singleton is already taken
    File: C:\GMACache\MonAgentHostCache\Configuration\MonAgentService.16.log  (AZL-NODE-04)
    Verbatim log line (timestamped, repeats every ~90 seconds):
      "Error (2026-07-24T00:08:52Z): MonAgentService - Another instance of the MA tenant
       service is already running; you can only run one MA service per system."

3c. The instance holding the singleton = the security monitoring extension
    Source: Get-CimInstance Win32_Process (Name='MonAgentHost.exe') on AZL-NODE-04
    Verbatim process command line:
      MonAgentHost pid 6564: -connectionInfo "AuthMSIToken" -serviceIdentity
      "externalprod#CorpSecurityMonitoring#CorpSecurityMonitoring#southcentralus" -configVersion 24.0
      -localpath "C:\WindowsAzure\Resources\SecurityMonitoringExtension.MonitoringDataStore\CorpSecurityMonitoring"
      ... -launcherType SecurityMonitoringExtension
    -> serviceIdentity = CorpSecurityMonitoring. This is the corporate security monitoring agent.

3d. How the security monitoring agent is installed on these nodes
    - Plugin present: C:\Packages\Plugins\Corp.Security.MonitoringAgent
    - Guest Configuration logs: C:\ProgramData\GuestConfig\extension_logs\Corp.Security.MonitoringAgent
    - Delivered via the Guest Configuration services (GCArcService / ExtensionService),
      i.e. an Azure Policy / security-agent auto-configuration applied to Arc machines in this
      subscription. (The Azure portal Deploy wizard also showed a resource group named
      "SecAgentAutoConfigRG" for this subscription.)

--------------------------------------------------------------------------------
4. WHAT IS RULED OUT (so the override is correctly targeted)
--------------------------------------------------------------------------------
- NOT outbound connectivity. Observability endpoints are reachable from the nodes:
    microsoftaik.azure.net                    dns=(none)          tcp443=False   [see note]
    gcs.prod.monitoring.core.windows.net      dns=203.0.113.10    tcp443=True
    global.prod.microsoftmetrics.com          dns=203.0.113.11     tcp443=True
    login.microsoftonline.com                 dns=203.0.113.12   tcp443=True
    login.windows.net                         dns=203.0.113.13  tcp443=True
  (microsoftaik.azure.net DNS failure is unrelated to the MA singleton conflict and does
   not change the root cause.)
- NOT the AzureEMP launcher service. Captured state on AZL-NODE-01 showed AzureEMP
  StartMode=Manual, and it starts cleanly on demand (Start-Service -> Running). On
  AZL-NODE-04 AzureEMP was already Running while MonAgentHost still could not start.
- NOT hardware, Active Directory, RBAC, storage, or the OS image. All other Azure Local
  prerequisites are verified green for these nodes.

--------------------------------------------------------------------------------
5. WHY THIS IS NOT A DOCUMENTED AZURE LOCAL LIMITATION
--------------------------------------------------------------------------------
- Microsoft Learn (Azure Local prerequisites, observability, telemetry, and known-issues
  pages) does NOT document any conflict with a corporate security monitoring extension or any other monitoring agent,
  and there is no "machine must be free of other monitoring agents" prerequisite.
- Reason: the security monitoring extension is an organization-specific security agent. Most Azure Local
  customers do not run one that uses the same agent slot, so their host's single monitoring-agent slot is free and they never hit this.
- Learn DOES confirm Azure Local's own observability is a monitoring agent (MA) storing data under
  C:\GMACache (concept doc: "You can view data in \\<NodeName>\c$\GMACache\TelemetryCache\
  Tables/*.tsf"), which is exactly the path of the collision above.
- Conclusion: this is an environment-specific collision that occurs only on Arc machines
  carrying the corporate security monitoring agent. The authority for the fix is the security
  monitoring extension / policy owner for this subscription, not Azure Local product documentation.

--------------------------------------------------------------------------------
6. CHANGE / OVERRIDE BEING REQUESTED
--------------------------------------------------------------------------------
Goal: free the single monitoring agent (MA) slot on the cluster nodes so Azure Local can install its
own monitoring agent and deployment can proceed.

Requested (preferred): exclude the cluster machines (AZL-NODE-01, -02, -04, -06; and
-03, -05 if they may later join) from the security-agent auto-configuration policy assignment
for subscription contoso-lab-sub, then remove the Corp.Security.MonitoringAgent
agent and stop the security monitoring MonAgent on those nodes. Exclusion is required so the agent is
not re-pushed by policy after removal.

Acceptable alternative (if permanent exclusion is not approved): a time-boxed override for
the deployment window, with the security monitoring extension re-applied afterward, if that is compatible with the
post-deploy state. (Feasibility of re-applying the security monitoring extension after Azure Local owns the MA slot
should be confirmed by the security monitoring extension owners.)

Routing note (from live check): at the subscription scope only Defender-for-Cloud (ASC)
assignments are visible; the requester is not authorized to read the management group. This
indicates the security-agent auto-config policy is inherited from a MANAGEMENT GROUP above the
subscription, so the change/approval routes through the management-group / central security
owner, not the subscription owner alone.

--------------------------------------------------------------------------------
6b. PRECEDENT AND SUPPORTED WORKAROUND
--------------------------------------------------------------------------------
Documented precedent: a previously recorded incident of the same class. A monitoring agent
deployed by a management-group policy (security-agent auto-config) contended with the
monitoring agent deployed by the platform stack, and the platform's logs/metrics disappeared.

Resolution in that incident:
- Adding the documented opt-out tag  SkipSecurityMonitoringAgent = true  disabled the
  conflicting auto-configuration, and the platform's logs/metrics became visible again.
- Other, similarly named skip tags did NOT prevent installation; only the documented
  opt-out tag worked.
- The policy-deployed extension remained visible in the Azure portal, i.e. the tag disabled the
  auto-configuration rather than necessarily uninstalling the extension.

Preferred requested change (updated to the supported mechanism): apply the tag
  SkipSecurityMonitoringAgent = true
scoped to this deployment (subscription contoso-lab-sub, or the specific cluster
machines/resource group), so security-agent auto-config stops contending for the single monitoring agent (MA)
slot and Azure Local can install its own agent. This is the same, supported opt-out used in
that precedent. It is reversible (remove the tag and auto-config resumes). The exact scope at
which the tag is honored (subscription vs resource) should be confirmed with the security monitoring extension
owners; subscription-level is the typical application.

--------------------------------------------------------------------------------
7. IMPACT, SCOPE, REVERSIBILITY
--------------------------------------------------------------------------------
- Impact if not granted: the Azure Local POC cannot be deployed on these machines by any
  method (portal or ARM/CLI use the same Environment Checker and fail identically).
- Scope: limited to the specific lab cluster nodes listed above, in a single dev subscription.
- Reversibility: removing the extension is reversible; the exclusion is a scoped policy change.
- Security posture note for the decision-maker: these are lab/POC nodes; the request is to
  remove ONE security-monitoring agent from a small, named set of machines. Azure Local
  provides its own observability/telemetry pipeline once deployed. The decision-maker should
  weigh the loss of the security monitoring extension coverage on these specific nodes against the POC requirement.

--------------------------------------------------------------------------------
8. EVIDENCE FILES (on the operator workstation, reproducible)
--------------------------------------------------------------------------------
- out/_obs-conn-azl-node-04.txt   (endpoint reachability + MonAgentHost process identities + MA logs)
- out/_emp-diag-azl-node-01.txt   (AzureEMP service state)
- Reproduce the MA error live:
    Get-Content 'C:\GMACache\MonAgentHostCache\Configuration\MonAgentService.*.log' | Select-String 'one MA service per system'
- Reproduce the conflicting identity live:
    Get-CimInstance Win32_Process -Filter "Name='MonAgentHost.exe'" | Select-Object ProcessId, CommandLine
```
