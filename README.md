# Proxmox Infrastructure Automation

Infrastructure-as-Code project for provisioning and configuring Ubuntu and Windows virtual machines on Proxmox VE.

The project combines Terraform, Ansible, PowerShell, Python and Bash to automate VM cloning, network configuration, operating-system validation and service deployment.

## Features

* Provision Ubuntu and Windows virtual machines from Proxmox templates
* Configure VM identifiers, names and management IP addresses
* Generate Ansible inventory automatically
* Configure Ubuntu systems using reusable Ansible roles
* Install and validate SSH, XRDP and QEMU Guest Agent
* Deploy and verify Zabbix Agent 2
* Validate Windows and Ubuntu connectivity using Python
* Manage infrastructure through an interactive Bash menu
* Create and destroy individual virtual machines
* Perform post-deployment SSH, RDP and service checks

## Architecture

```text
Infrastructure Manager
        |
        +-- Terraform
        |     |
        |     +-- Proxmox Ubuntu module
        |     +-- Proxmox Windows module
        |
        +-- Ansible
        |     |
        |     +-- Common configuration
        |     +-- SSH
        |     +-- XRDP
        |     +-- Zabbix Agent 2
        |
        +-- Validation
              |
              +-- Python connectivity checks
              +-- SSH and RDP checks
              +-- QEMU Guest Agent checks
```

## Repository structure

```text
.
├── ansible/
│   ├── group_vars/
│   ├── inventory/
│   ├── playbooks/
│   ├── roles/
│   │   ├── common/
│   │   ├── rdp/
│   │   ├── ssh/
│   │   ├── zabbix_agent/
│   │   └── zabbix_discovery/
│   └── scripts/
├── check_vm/
├── modules/
│   ├── Ubuntu/
│   └── Windows/
├── Scripts/
├── main.tf
├── outputs.tf
├── provider.tf
├── variables.tf
├── ubuntu-init.yaml
└── windows-init.ps1
```

## Prerequisites

* Proxmox VE environment
* Existing Ubuntu and Windows VM templates
* Terraform installed on the management workstation
* Python 3
* Windows PowerShell
* WSL with Ansible installed
* SSH access to Ubuntu virtual machines
* QEMU Guest Agent installed in the VM templates
* Cloud-Init for Ubuntu
* Cloudbase-Init for Windows
* Appropriate Proxmox API permissions

## Configuration

The public repository contains sanitized configuration values.

Example IP addresses use the documentation network:

```text
192.0.2.0/24
```

Before using the project, configure:

* Proxmox API endpoint
* Proxmox node name
* Storage names
* Network bridges
* Ubuntu and Windows template IDs
* VM identifiers
* Management IP addresses
* Local usernames
* Required environment variables and credentials

Do not store passwords, API tokens, private keys or production IP addresses in tracked files.

## Terraform variables

Local VM definitions can be stored in ignored files such as:

```text
ubuntu_vms.auto.tfvars.json
windows_vms.auto.tfvars.json
```

Example Ubuntu configuration:

```json
{
  "create_ubuntu": true,
  "ubuntu_vms": {
    "ubuntu-lab-01": {
      "vm_id": 101,
      "ip_address": "192.0.2.101/24"
    }
  }
}
```

Example Windows configuration:

```json
{
  "create_windows": true,
  "windows_vms": {
    "windows-lab-01": {
      "vm_id": 201,
      "template_id": 9000,
      "ip_address": "192.0.2.201/24",
      "windows_username": "example-admin"
    }
  }
}
```

Adapt these examples to match the variable definitions in the current Terraform configuration.

## Terraform workflow

Initialize Terraform:

```powershell
terraform init
```

Validate the configuration:

```powershell
terraform fmt -check -recursive
terraform validate
```

Review the proposed changes:

```powershell
terraform plan
```

Apply the configuration only after reviewing the complete plan:

```powershell
terraform apply
```

## Infrastructure Manager

The interactive management menu is located at:

```text
ansible/scripts/infrastructure_manager.sh
```

Run it from WSL:

```bash
cd ansible/scripts
chmod +x infrastructure_manager.sh
./infrastructure_manager.sh
```

The menu supports:

* Ubuntu VM creation
* Managed VM listing
* Terraform validation and planning
* Ansible inventory display
* SSH and Ansible connectivity tests
* Ubuntu configuration
* SSH, RDP and Zabbix verification
* VM destruction

## Ansible

Display the combined inventory:

```bash
ansible-inventory \
  -i ansible/inventory/hosts.yml \
  -i ansible/inventory/generated_ubuntu.yml \
  --graph
```

Test connectivity:

```bash
ansible \
  -i ansible/inventory/hosts.yml \
  -i ansible/inventory/generated_ubuntu.yml \
  all \
  -m ansible.builtin.ping
```

Run the Ubuntu configuration playbook:

```bash
ansible-playbook \
  -i ansible/inventory/hosts.yml \
  -i ansible/inventory/generated_ubuntu.yml \
  ansible/playbooks/configure_ubuntu.yml
```

## Security

The repository intentionally excludes:

* Terraform state files
* Terraform plans
* Local variable files
* API tokens
* Passwords
* SSH private keys
* Generated inventories
* Backup files
* Local reports

Use environment variables or an external secret-management solution for sensitive values.

Password authentication is disabled in the public Cloud-Init example. SSH key authentication is recommended for Linux administration.

Never commit production credentials, password hashes or private infrastructure information.

## Validation

Before committing changes, run:

```powershell
terraform fmt -check -recursive
terraform validate
git diff --cached --check
```

Search for accidentally committed private information:

```powershell
git grep -n -I -E '192\.168\.|BEGIN OPENSSH PRIVATE KEY|BEGIN RSA PRIVATE KEY'
```

## Disclaimer

This repository is an anonymized infrastructure automation example.

Node names, IP addresses, template identifiers, usernames and paths must be adapted before the project is used in another environment.
