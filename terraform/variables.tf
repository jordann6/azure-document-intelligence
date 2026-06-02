variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Deployment environment label (dev / prod)."
  type        = string
  default     = "dev"
}
