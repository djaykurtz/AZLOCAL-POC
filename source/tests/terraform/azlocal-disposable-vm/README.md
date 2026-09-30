# Azure Local disposable VM module

This module is the Terraform capstone's plan-only wrapper around the official Azure Verified Module:

`Azure/avm-res-azurestackhci-virtualmachineinstance/azurerm` version `2.1.1`.

It intentionally creates only resources owned by Terraform with a `tf-poc-` name and Terraform ownership tags.
It must not import, change, or destroy the Azure Local cluster, AKS, gallery images, shared logical network,
`ws2025-core-01`, or `rocky-docker-01`.

## Safe workflow

1. Run `terraform fmt -check -recursive` and `terraform init -backend=false`.
2. Populate a local, untracked variable file from live read-only resource IDs.
3. Run a human-authenticated speculative plan only.
4. Reject the plan if it changes any resource not prefixed `tf-poc-`.
5. Do not run `apply`, `destroy`, `import`, or `-target` until the capstone approval and state/OIDC gates are complete.

The module requests a small dynamic-memory Linux VM: one vCPU and 2048 MB initial memory, with a 4096 MB upper
bound enforced by the wrapper variable validation. Re-measure Azure Local host capacity before any future apply.