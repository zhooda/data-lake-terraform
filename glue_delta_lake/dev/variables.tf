variable "tag_env" {
  type    = string
  default = "dev"
}

variable "tag_terraform" {
  type    = string
  default = "true"
}

variable "tag_owner" {
  type    = string
  default = "none"
}

variable "name" {
  type    = string
  default = "dev-data-lake"
}

variable "vpc" {
  type = map(any)
  default = {
    dms_subnets                = ["subnet-0005beed8a25d8688", "subnet-0c7111c9556e855d9"]
    default_security_group_ids = ["sg-00755e8aacad54b70"]
  }
}
