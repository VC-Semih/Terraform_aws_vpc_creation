variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_name" {
  type        = string
  description = "Nom du vpc (example ccm-insset)"
  default = "ccm-insset"
}

variable "vpc_cidr" {
  type    = string
  default = "172.29.0.0/16"
}

variable "vpc_azs" {
  type    = list(string)
  default = ["a", "b", "c"]
}