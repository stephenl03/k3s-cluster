terraform {
  backend "remote" {
    organization = "my-super-awesome-company"
    workspaces {
      name = "home-cloudflare-casa-tld"
    }
  }
  
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.21.0"
}
    http = {
      source  = "hashicorp/http"
      version = ">= 2.1.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = ">= 0.7.0"
    }
  }
}

provider "cloudflare" {
  email   = data.sops_file.cloudflare_secrets.data["cloudflare_email"]
  api_key = data.sops_file.cloudflare_secrets.data["cloudflare_apikey"]
}

data "sops_file" "cloudflare_secrets" {
  source_file = "secret.sops.yaml"
}

data "cloudflare_zones" "domain" {
  filter {
    name = data.sops_file.cloudflare_secrets.data["cloudflare_domain"]
  }
}
