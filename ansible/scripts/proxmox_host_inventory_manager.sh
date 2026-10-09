#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/proxmox_hosts.yml"
PLAYBOOK_DIR="${ANSIBLE_DIR}/playbooks/proxmox_inventory"
REPORT_DIR="${ANSIBLE_DIR}/reports/proxmox"
FORMAT_REPORT_SCRIPT="${SCRIPT_DIR}/format_inventory_reports.py"

export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"

pause_menu() {
    echo
    read -rp "Press ENTER to return to the inventory menu..."
}

print_header() {
    clear
    echo "============================================================"
    echo "              PROXMOX HOST INVENTORY"
    echo "============================================================"
    echo " Inventory : ${INVENTORY_FILE}"
    echo " Reports   : ${REPORT_DIR}"
    echo "============================================================"
    echo
}

check_inventory_file() {
    if [[ ! -f "${INVENTORY_FILE}" ]]; then
        echo "[ERROR] Missing inventory: ${INVENTORY_FILE}"
        return 1
    fi
}

show_proxmox_hosts() {
    check_inventory_file || return 1

    ansible-inventory \
        -i "${INVENTORY_FILE}" \
        --graph
}

test_proxmox_connection() {
    check_inventory_file || return 1

    echo "[INFO] Testing Ansible connectivity to Proxmox hosts..."
    echo

    ansible \
        -i "${INVENTORY_FILE}" \
        proxmox_hosts \
        -m ansible.builtin.ping
}

run_inventory_playbook() {
    local playbook_name="$1"
    local playbook_path="${PLAYBOOK_DIR}/${playbook_name}"

    check_inventory_file || return 1

    if [[ ! -f "${playbook_path}" ]]; then
        echo "[ERROR] Missing playbook: ${playbook_path}"
        return 1
    fi

    mkdir -p "${REPORT_DIR}"

    echo "[INFO] Running read-only inventory playbook:"
    echo "       ${playbook_name}"
    echo

 if ansible-playbook \
    -i "${INVENTORY_FILE}" \
    "${playbook_path}" \
    --extra-vars "report_root=${REPORT_DIR}"
then
    echo
    echo "[INFO] Formatting generated TXT reports..."

    if [[ -f "${FORMAT_REPORT_SCRIPT}" ]]; then
        python3 "${FORMAT_REPORT_SCRIPT}" "${REPORT_DIR}"
    else
        echo "[WARNING] Missing formatter: ${FORMAT_REPORT_SCRIPT}"
    fi
else
    echo "[ERROR] Inventory playbook failed."
    return 1
fi
}

show_saved_reports() {
    mkdir -p "${REPORT_DIR}"

    echo "Saved reports:"
    echo

    find "${REPORT_DIR}" \
        -maxdepth 2 \
        -type f \
        -printf '%TY-%Tm-%Td %TH:%TM  %p\n' \
        2>/dev/null |
        sort -r

    if [[ -z "$(find "${REPORT_DIR}" -type f -print -quit 2>/dev/null)" ]]; then
        echo "[INFO] No reports have been generated yet."
    fi
}

while true; do
    print_header

    echo "1) Show configured Proxmox hosts"
    echo "2) Test Ansible connection"
    echo "3) Generate full host inventory"
    echo "4) Hardware and BIOS"
    echo "5) CPU and memory"
    echo "6) PCI, GPU and IOMMU"
    echo "7) Storage"
    echo "8) Network"
    echo "9) Operating system and Proxmox"
    echo "10) Services"
    echo "11) Cluster and HA"
    echo "12) Ceph"
    echo "13) Virtual machines and containers"
    echo "14) Show saved reports"
    echo "0) Return to main menu"
    echo

    read -rp "Select an option: " option
    echo

    case "${option}" in
        1)
            show_proxmox_hosts
            ;;
        2)
            test_proxmox_connection
            ;;
        3)
            run_inventory_playbook "full_inventory.yml"
            ;;
        4)
            run_inventory_playbook "hardware_bios.yml"
            ;;
        5)
            run_inventory_playbook "cpu_memory.yml"
            ;;
        6)
            run_inventory_playbook "pci_gpu_iommu.yml"
            ;;
        7)
            run_inventory_playbook "storage.yml"
            ;;
        8)
            run_inventory_playbook "network.yml"
            ;;
        9)
            run_inventory_playbook "os_proxmox.yml"
            ;;
        10)
            run_inventory_playbook "services.yml"
            ;;
        11)
            run_inventory_playbook "cluster_ha.yml"
            ;;
        12)
            run_inventory_playbook "ceph.yml"
            ;;
        13)
            run_inventory_playbook "vm_ct_inventory.yml"
            ;;
        14)
            show_saved_reports
            ;;
        0)
            exit 0
            ;;
        *)
            echo "[ERROR] Invalid option."
            ;;
    esac

    pause_menu
done