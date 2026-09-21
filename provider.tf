# ==============================================================================
# 1. CONFIGURAREA PROVIDER-ULUI (Plugin-ul pentru Proxmox)
# ==============================================================================
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.0.0.101:8006/"                                # INLOCUIEȘTE cu IP-ul serverului tău Proxmox
  api_token = "terraform@pve!tf-token=TOKEN-ID" # Pune Token ID-ul și Secretul exact așa cum le-ai salvat
  insecure  = true                                                          # Ignoră alerta de certificat SSL dacă folosești conexiunea standard Proxmox
}