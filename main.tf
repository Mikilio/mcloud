terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.54.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.3"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }
}

provider "hcloud" {}
provider "cloudflare" {} #CLOUDFLARE_API_TOKEN
provider "random" {}

resource "random_bytes" "tunnel_secret" {
  length = 32
}
# Creates a new remotely-managed tunnel for clan.
resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnel" {
  account_id    = var.cloudflare_account_id
  name          = "Terraform Clan tunnel"
  tunnel_secret = sensitive(random_bytes.tunnel_secret.base64)
}

resource "cloudflare_dns_record" "mail_4" {
  zone_id = var.cloudflare_zone_id
  name    = "mail"
  content = hcloud_server.gate.ipv4_address
  type    = "A"
  ttl     = 10800
}

resource "cloudflare_dns_record" "mail_6" {
  zone_id = var.cloudflare_zone_id
  name    = "mail"
  content = hcloud_server.gate.ipv6_address
  type    = "AAAA"
  ttl     = 10800
}

resource "cloudflare_dns_record" "ts_4" {
  zone_id = var.cloudflare_zone_id
  name    = "ts"
  content = hcloud_server.gate.ipv4_address
  type    = "A"
  ttl     = 10800
}

resource "cloudflare_dns_record" "ts_6" {
  zone_id = var.cloudflare_zone_id
  name    = "ts"
  content = hcloud_server.gate.ipv6_address
  type    = "AAAA"
  ttl     = 10800
}

resource "cloudflare_dns_record" "auth_4" {
  zone_id = var.cloudflare_zone_id
  name    = "auth"
  content = hcloud_server.gate.ipv4_address
  type    = "A"
  ttl     = 10800
}

resource "cloudflare_dns_record" "auth_6" {
  zone_id = var.cloudflare_zone_id
  name    = "auth"
  content = hcloud_server.gate.ipv6_address
  type    = "AAAA"
  ttl     = 10800
}

resource "cloudflare_dns_record" "wp_4" {
  zone_id = var.cloudflare_zone_id
  name    = "wp"
  content = hcloud_server.gate.ipv4_address
  type    = "A"
  ttl     = 10800
}

resource "cloudflare_dns_record" "wp_6" {
  zone_id = var.cloudflare_zone_id
  name    = "wp"
  content = hcloud_server.gate.ipv6_address
  type    = "AAAA"
  ttl     = 10800
}

resource "cloudflare_dns_record" "cal_4" {
  zone_id = var.cloudflare_zone_id
  name    = "cal"
  content = hcloud_server.gate.ipv4_address
  type    = "A"
  ttl     = 10800
}

resource "cloudflare_dns_record" "cal_6" {
  zone_id = var.cloudflare_zone_id
  name    = "cal"
  content = hcloud_server.gate.ipv6_address
  type    = "AAAA"
  ttl     = 10800
}
resource "cloudflare_dns_record" "root_mx" {
  zone_id  = var.cloudflare_zone_id
  name     = "@"
  content  = "mail.mikilio.com"
  type     = "MX"
  ttl      = 1
  priority = 10
}

resource "cloudflare_dns_record" "root_spf" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = "\"v=spf1 a:mail.mikilio.com -all\""
  type    = "TXT"
  ttl     = 10800
}

resource "cloudflare_dns_record" "root_dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc.mikilio.com"
  content = "\"v=DMARC1; p=quarantine\""
  type    = "TXT"
  ttl     = 10800
}

resource "cloudflare_dns_record" "root_dkim" {
  zone_id = var.cloudflare_zone_id
  name    = "mail._domainkey.mikilio.com"
  content = "${join("", [for match in regexall("\"([^\"]+)\"", module.clan.imported_vars.mikilio_dkim) : match[0]])}"
  type    = "TXT"
  ttl     = 10800
}

resource "cloudflare_dns_record" "root_submissions_tcp" {
  zone_id = var.cloudflare_zone_id
  name    = "_submissions._tcp.mikilio.com"
  type    = "SRV"
  ttl     = 3600
  data = {
    priority = 5
    weight   = 0
    port     = 465
    target    = "mail.mikilio.com"
  }
}

resource "cloudflare_dns_record" "root_imaps_tcp" {
  zone_id = var.cloudflare_zone_id
  name    = "_imaps._tcp.mikilio.com"
  type    = "SRV"
  ttl     = 3600
  data = {
    priority = 5
    weight   = 0
    port     = 993
    target    = "mail.mikilio.com"
  }
}

resource "cloudflare_dns_record" "google-site-verification" {
  zone_id = var.cloudflare_zone_id
  name = "mikilio.com"
  content = "google-site-verification=eYOLwimDSv2PSMLrJv93AOvcBKjCMTeFXjY9ew3wpDg"
  type    = "TXT"
  ttl     = 10800
}

resource "hcloud_rdns" "mail4" {
  server_id  = hcloud_server.gate.id
  ip_address = hcloud_server.gate.ipv4_address
  dns_ptr    = "mail.mikilio.com"
}

resource "hcloud_rdns" "mail6" {
  server_id  = hcloud_server.gate.id
  ip_address = hcloud_server.gate.ipv6_address
  dns_ptr    = "mail.mikilio.com"
}


resource "hcloud_server" "brain" {
  name        = "brain"
  server_type = "cx23"
  image       = "debian-12"
  location    = "fsn1"
  ssh_keys    = ["mikilio"]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = true
  }
}

resource "hcloud_server" "gate" {
  name        = "gate"
  server_type = "cx23"
  image       = "debian-12"
  location    = "fsn1"
  ssh_keys    = ["mikilio"]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
}

resource "hcloud_server" "wp1" {
  name        = "wp1"
  server_type = "cx23"
  image       = "debian-12"
  location    = "fsn1"
  ssh_keys    = ["mikilio"]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = true
  }
}

module "clan" {
  source = "github.com/Mikilio/terraform-clan-vars?ref=main"

  vars_to_import = {
    mikilio_dkim = {
      key     = "dkim/mikilio.com.mail.txt"
      machine = "gate"
    }
  }

  vars_to_store = [

    {
      name     = "hcloud_ipv6"
      value    = hcloud_server.brain.ipv6_address
      machines = ["brain"]
    },
    {
      name     = "hcloud_ipv6"
      value    = hcloud_server.wp1.ipv6_address
      machines = ["wp1"]
    },
    {
      name     = "hcloud_ipv6"
      value    = hcloud_server.gate.ipv6_address
      machines = ["gate"]
    },
    {
      name     = "hcloud_ipv4"
      value    = hcloud_server.gate.ipv4_address
      machines = ["gate"]
    },
  ]

  secrets_to_store = {
    cftunnel = {
      value = jsonencode({
        "AccountTag"   = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.account_tag}"
        "TunnelSecret" = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.tunnel_secret}"
        "TunnelID"     = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.id}"
        "Endpoint"     = ""
      })
      users = ["mikilio"]
      hosts = ["brain"]
    }
  }
}

# Output the path to the generated JSON file
output "install_commands" {
  description = "The 'clan machines install' command to run."
  value       = <<-EOT
    clan machines install brain --update-hardware-config nixos-facter --phases kexec --target-host root@[${hcloud_server.brain.ipv6_address}]
    clan machines install gate --update-hardware-config nixos-facter --phases kexec --target-host root@[${hcloud_server.gate.ipv6_address}]
    clan machines install wp1 --update-hardware-config nixos-facter --phases kexec --target-host root@[${hcloud_server.wp1.ipv6_address}]
    EOT
}
