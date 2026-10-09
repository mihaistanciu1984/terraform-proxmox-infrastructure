#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="$(cd "${ANSIBLE_DIR}/.." && pwd)"
TERRAFORM_WINDOWS_DIR="$(wslpath -w "${TERRAFORM_DIR}")"

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    echo "EROARE: Directorul Terraform nu există: ${TERRAFORM_DIR}"
    exit 1
fi

if [[ -z "${TERRAFORM_WINDOWS_DIR}" ]]; then
    echo "EROARE: TERRAFORM_WINDOWS_DIR este gol."
    exit 1
fi

VM_FILE="${TERRAFORM_DIR}/ubuntu_vms.auto.tfvars.json"
INVENTORY_STATIC="${ANSIBLE_DIR}/inventory/hosts.yml"
INVENTORY_GENERATED="${ANSIBLE_DIR}/inventory/generated_ubuntu.yml"

CREATE_VM_SCRIPT="${SCRIPT_DIR}/create_ubuntu_vm.sh"
DESTROY_VM_SCRIPT="${SCRIPT_DIR}/destroy_ubuntu_vm.sh"

CREATE_WINDOWS_VM_SCRIPT="${SCRIPT_DIR}/create_windows_vm.sh"
DESTROY_WINDOWS_VM_SCRIPT="${SCRIPT_DIR}/destroy_windows_vm.sh"
ZABBIX_SCRIPT="${SCRIPT_DIR}/zabbix_manager.sh"
PROXMOX_INVENTORY_SCRIPT="${SCRIPT_DIR}/proxmox_host_inventory_manager.sh"

export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"

cd "${ANSIBLE_DIR}" || {
    echo "[EROARE] Nu pot accesa ${ANSIBLE_DIR}"
    exit 1
}

pause_menu() {
    echo
    read -rp "Apasă ENTER pentru a reveni la meniu..."
}

print_header() {
    clear
    echo "============================================================"
    echo "          PROXMOX INFRASTRUCTURE MANAGEMENT"
    echo "============================================================"
    echo " Terraform : ${TERRAFORM_DIR}"
    echo " Ansible   : ${ANSIBLE_DIR}"
    echo "============================================================"
    echo
}

list_ubuntu_vms() {
    python3 - "${VM_FILE}" <<'PYTHON'
import ipaddress
import json
import pathlib
import sys

vm_file = pathlib.Path(sys.argv[1])

if not vm_file.exists():
    raise SystemExit(f"[EROARE] Fișier inexistent: {vm_file}")

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

ubuntu_vms = data.get("ubuntu_vms", {})

if not ubuntu_vms:
    print("[INFO] Nu există VM-uri Ubuntu definite.")
    raise SystemExit(0)

print()
print(f"{'NUME VM':<30} {'VM ID':<10} {'IP MANAGEMENT'}")
print("-" * 65)

for vm_name, config in sorted(ubuntu_vms.items()):
    print(
        f"{vm_name:<30} "
        f"{str(config['vm_id']):<10} "
        f"{config['ip_address']}"
    )
PYTHON
}

get_vm_ip() {
    local vm_name="$1"

    python3 - "${VM_FILE}" "${vm_name}" <<'PYTHON'
import ipaddress
import json
import pathlib
import sys

vm_file = pathlib.Path(sys.argv[1])
vm_name = sys.argv[2]

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

vm = data.get("ubuntu_vms", {}).get(vm_name)

if vm is None:
    raise SystemExit(1)

print(ipaddress.ip_interface(vm["ip_address"]).ip)
PYTHON
}

select_vm() {
    list_ubuntu_vms
    echo
    read -rp "Introdu numele exact al VM-ului: " SELECTED_VM

    SELECTED_IP="$(get_vm_ip "${SELECTED_VM}")"

    if [[ $? -ne 0 || -z "${SELECTED_IP}" ]]; then
        echo "[EROARE] VM-ul ${SELECTED_VM} nu există în configurație."
        return 1
    fi

    echo
    echo "[INFO] VM selectat: ${SELECTED_VM}"
    echo "[INFO] IP management: ${SELECTED_IP}"
}
create_windows_vm() {
    if [[ ! -f "${CREATE_WINDOWS_VM_SCRIPT}" ]]; then
        echo "[EROARE] Lipsește ${CREATE_WINDOWS_VM_SCRIPT}"
        return 1
    fi

    bash "${CREATE_WINDOWS_VM_SCRIPT}"
}

create_ubuntu_vm() {
    if [[ ! -f "${CREATE_VM_SCRIPT}" ]]; then
        echo "[EROARE] Lipsește ${CREATE_VM_SCRIPT}"
        return 1
    fi

    bash "${CREATE_VM_SCRIPT}"
}

terraform_plan() {
    powershell.exe -NoProfile -Command \
        "Set-Location -LiteralPath '${TERRAFORM_WINDOWS_DIR}'; terraform validate; if (\$LASTEXITCODE -eq 0) { terraform plan }"
}

show_ansible_inventory() {
    ansible-inventory \
        -i "${INVENTORY_STATIC}" \
        -i "${INVENTORY_GENERATED}" \
        --graph
}

test_ansible_connection() {
    select_vm || return 1

    ansible \
        -i "${INVENTORY_STATIC}" \
        -i "${INVENTORY_GENERATED}" \
        "${SELECTED_VM}" \
        -m ansible.builtin.ping
}

configure_ubuntu_vm() {
    select_vm || return 1

    echo
    read -rp "Reconfigurez ${SELECTED_VM} prin Ansible? [y/N]: " confirmation

    if [[ ! "${confirmation}" =~ ^[Yy]$ ]]; then
        echo "[INFO] Operația a fost anulată."
        return 0
    fi

    ansible-playbook \
        -i "${INVENTORY_STATIC}" \
        -i "${INVENTORY_GENERATED}" \
        playbooks/configure_ubuntu.yml \
        --limit "${SELECTED_VM}" \
        --extra-vars "ansible_host=${SELECTED_IP}"
}

check_tcp_port() {
    local ip_address="$1"
    local port="$2"
    local service_name="$3"

    if nc -z -w 5 "${ip_address}" "${port}" >/dev/null 2>&1; then
        echo "[OK] ${service_name}: ${ip_address}:${port}"
        return 0
    fi

    echo "[FAIL] ${service_name}: ${ip_address}:${port}"
    return 1
}

check_vm_services() {
    select_vm || return 1

    echo
    echo "Verificări pentru ${SELECTED_VM}:"
    echo "------------------------------------------------------------"

    check_tcp_port "${SELECTED_IP}" 22 "SSH"
    check_tcp_port "${SELECTED_IP}" 3389 "RDP/XRDP"
    check_tcp_port "${SELECTED_IP}" 10050 "Zabbix Agent 2"

    echo "------------------------------------------------------------"

    echo
    echo "[INFO] Verific serviciile prin Ansible..."

    ansible \
        -i "${INVENTORY_STATIC}" \
        -i "${INVENTORY_GENERATED}" \
        "${SELECTED_VM}" \
        --become \
        -m ansible.builtin.shell \
        -a "systemctl is-active ssh xrdp qemu-guest-agent zabbix-agent2 2>/dev/null || true"
}

open_zabbix_menu() {
    if [[ ! -f "${ZABBIX_SCRIPT}" ]]; then
        echo "[EROARE] Lipsește ${ZABBIX_SCRIPT}"
        echo "[INFO] Creează scriptul Zabbix din documentația anterioară."
        return 1
    fi

    bash "${ZABBIX_SCRIPT}"
}

open_proxmox_inventory_menu() {
    if [[ ! -f "${PROXMOX_INVENTORY_SCRIPT}" ]]; then
        echo "[ERROR] Missing script: ${PROXMOX_INVENTORY_SCRIPT}"
        echo "[INFO] The Proxmox inventory menu has not been created yet."
        return 1
    fi

    bash "${PROXMOX_INVENTORY_SCRIPT}"
}

full_existing_vm_workflow() {
    select_vm || return 1

    echo
    echo "[PAS 1] Testez accesul Ansible..."

    ansible \
        -i "${INVENTORY_STATIC}" \
        -i "${INVENTORY_GENERATED}" \
        "${SELECTED_VM}" \
        -m ansible.builtin.ping || return 1

    echo
    echo "[PAS 2] Rulez configurarea Ubuntu..."

    ansible-playbook \
        -i "${INVENTORY_STATIC}" \
        -i "${INVENTORY_GENERATED}" \
        playbooks/configure_ubuntu.yml \
        --limit "${SELECTED_VM}" \
        --extra-vars "ansible_host=${SELECTED_IP}" || return 1

    echo
    echo "[PAS 3] Verific SSH și RDP..."

    check_tcp_port "${SELECTED_IP}" 22 "SSH"
    check_tcp_port "${SELECTED_IP}" 3389 "RDP/XRDP"

    echo
    read -rp "Deschid meniul Zabbix? [y/N]: " zabbix_confirmation

    if [[ "${zabbix_confirmation}" =~ ^[Yy]$ ]]; then
        open_zabbix_menu
    fi
}

vm_management_menu() {
    while true; do
        print_header

        echo "VIRTUAL MACHINE MANAGEMENT"
        echo
        echo "1) Create a new Ubuntu VM"
        echo "2) List managed Ubuntu VMs"
        echo "3) Show Ansible inventory"
        echo "4) Run Terraform validate and global plan"
        echo "5) Test Ansible/SSH connection"
        echo "6) Reconfigure an existing Ubuntu VM with Ansible"
        echo "7) Check SSH, RDP and Zabbix"
        echo "8) Open Zabbix menu"
        echo "9) Run the complete workflow for an existing VM"
        echo "10) Destroy an Ubuntu VM"
        echo "11) Create a new Windows VM"
        echo "12) Destroy a Windows VM"
        echo "0) Return to main menu"
        echo

        read -rp "Select an option: " option
        echo

        case "${option}" in
            1)
                create_ubuntu_vm
                ;;
            2)
                list_ubuntu_vms
                ;;
            3)
                show_ansible_inventory
                ;;
            4)
                terraform_plan
                ;;
            5)
                test_ansible_connection
                ;;
            6)
                configure_ubuntu_vm
                ;;
            7)
                check_vm_services
                ;;
            8)
                open_zabbix_menu
                ;;
            9)
                full_existing_vm_workflow
                ;;
            10)
                if [[ ! -f "${DESTROY_VM_SCRIPT}" ]]; then
                    echo "[ERROR] Missing script: ${DESTROY_VM_SCRIPT}"
                else
                    bash "${DESTROY_VM_SCRIPT}"
                fi
                ;;
            11)
                create_windows_vm
                ;;
            12)
                if [[ ! -f "${DESTROY_WINDOWS_VM_SCRIPT}" ]]; then
                    echo "[ERROR] Missing script: ${DESTROY_WINDOWS_VM_SCRIPT}"
                else
                    bash "${DESTROY_WINDOWS_VM_SCRIPT}"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                echo "[ERROR] Invalid option."
                ;;
        esac

        pause_menu
    done
}

main_menu() {
    while true; do
        print_header

        echo "MAIN MENU"
        echo
        echo "1) Virtual machine management"
        echo "2) Proxmox host inventory"
        echo "3) Monitoring and Zabbix"
        echo "0) Exit"
        echo

        read -rp "Select an option: " option
        echo

        case "${option}" in
            1)
                vm_management_menu
                ;;
            2)
                open_proxmox_inventory_menu
                pause_menu
                ;;
            3)
                open_zabbix_menu
                pause_menu
                ;;
            0)
                echo "Application closed."
                exit 0
                ;;
            *)
                echo "[ERROR] Invalid option."
                pause_menu
                ;;
        esac
    done
}

main_menu