terraform {
  required_version = ">= 1.5.0"
}

variable "node_count" {
  type        = number
  description = "Number of Azure Local nodes in the POC test design. Default is 4; 6 is the optional scale-out path."
  default     = 4

  validation {
    condition     = contains([4, 6], var.node_count)
    error_message = "node_count must be 4 for the default POC or 6 for the optional scale-out path."
  }
}

variable "node_prefix" {
  type        = string
  description = "Hostname prefix for the Azure Local lab nodes."
  default     = "azl-node"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.node_prefix))
    error_message = "node_prefix must be lowercase DNS-label safe text."
  }
}

variable "cluster_name" {
  type        = string
  description = "On-prem cluster computer object name used by the POC."
  default     = "AZL-CL01"
}

locals {
  node_names = [for index in range(var.node_count) : format("%s-%02d", var.node_prefix, index + 1)]
}

output "cluster_name" {
  value = var.cluster_name
}

output "node_names" {
  value = local.node_names
}

output "test_surface" {
  value = {
    terraform_validates = true
    default_node_count  = 4
    scale_node_count    = 6
    deploys_resources   = false
  }
}