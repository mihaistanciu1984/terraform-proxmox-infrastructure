#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="$(cd "${ANSIBLE_DIR}/.." && pwd)"

VM_FILE="${TERRAFORM_DIR}/ubuntu_vms.auto.tfvars.json"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/generated_ubuntu.yml"
SYNC_SCRIPT="${SCRIPT_DIR}/sync_ubuntu_inventory.py"

TERRAFORM_WINDOWS_DIR="$(wslpath -w "${TERRAFORM_DIR}")"

BACKUP_DIR=""
DESTROY_STARTED=false

run_terraform() {
    local terraform_command="$1"

    powershell.exe -NoProfile -Command \
        "Set-Location -LiteralPath '${TERRAFORM_WINDOWS_DIR}'; ${terraform_command}"
}

cleanup() {
    if [[ -n "${BACKUP_DIR}" && -d "${BACKUP_DIR}" ]]; then
        rm -r -- "${BACKUP_DIR}"
    fi
}

restore_configuration() {
    if [[ "${DESTROY_STARTED}" == "true" ]]; then
        echo "[INFO] Terraform apply a început."
        echo "[INFO] Configurația nu va fi restaurată automat."
        return
    fi

    if [[ -n "${BACKUP_DIR}" &&
          -f "${BACKUP_DIR}/ubuntu_vms.auto.tfvars.json" ]]; then
        echo "[INFO] Restaurez configurația Terraform..."
        cp \
            "${BACKUP_DIR}/ubuntu_vms.auto.tfvars.json" \
            "${VM_FILE}"
    fi
}

trap cleanup EXIT

if [[ ! -f "${VM_FILE}" ]]; then
    echo "[EROARE] Lipsește ${VM_FILE}"
    exit 1
fi

if [[ ! -f "${SYNC_SCRIPT}" ]]; then
    echo "[EROARE] Lipsește ${SYNC_SCRIPT}"
    exit 1
fi

echo "============================================================"
echo "               DESTROY UBUNTU VM"
echo "============================================================"
echo

python3 - "${VM_FILE}" <<'PYTHON'
import ipaddress
import json
import pathlib
import sys

vm_file = pathlib.Path(sys.argv[1])

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

ubuntu_vms = data.get("ubuntu_vms", {})

if not ubuntu_vms:
    print("[INFO] Nu există VM-uri Ubuntu administrate.")
    raise SystemExit(0)

print(f"{'NUME VM':<30} {'VM ID':<10} {'IP MANAGEMENT'}")
print("-" * 65)

for vm_name, vm in sorted(ubuntu_vms.items()):
    management_ip = ipaddress.ip_interface(
        vm["ip_address"]
    ).ip

    print(
        f"{vm_name:<30} "
        f"{str(vm['vm_id']):<10} "
        f"{management_ip}"
    )
PYTHON

echo
read -rp "Introdu numele exact al VM-ului de șters: " VM_NAME

VM_INFORMATION="$(
    python3 - "${VM_FILE}" "${VM_NAME}" <<'PYTHON'
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

print(f"{vm['vm_id']}|{vm['ip_address']}")
PYTHON
)"

if [[ $? -ne 0 || -z "${VM_INFORMATION}" ]]; then
    echo "[EROARE] VM-ul ${VM_NAME} nu există în configurație."
    exit 1
fi

VM_ID="${VM_INFORMATION%%|*}"
VM_IP="${VM_INFORMATION#*|}"

echo
echo "VM selectat pentru distrugere:"
echo "  Nume  : ${VM_NAME}"
echo "  VM ID : ${VM_ID}"
echo "  IP    : ${VM_IP}"
echo
echo "ATENȚIE: VM-ul și discurile sale vor fi șterse din Proxmox."
echo

read -rp "Scrie numele VM-ului pentru confirmare: " NAME_CONFIRMATION

if [[ "${NAME_CONFIRMATION}" != "${VM_NAME}" ]]; then
    echo "[INFO] Numele nu corespunde. Operația a fost anulată."
    exit 0
fi

BACKUP_DIR="$(mktemp -d)"

cp \
    "${VM_FILE}" \
    "${BACKUP_DIR}/ubuntu_vms.auto.tfvars.json"

echo
echo "[INFO] Elimin ${VM_NAME} din configurația dorită..."

python3 - "${VM_FILE}" "${VM_NAME}" <<'PYTHON'
import json
import pathlib
import sys

vm_file = pathlib.Path(sys.argv[1])
vm_name = sys.argv[2]

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

removed_vm = data.get("ubuntu_vms", {}).pop(vm_name, None)

if removed_vm is None:
    raise SystemExit(
        f"[EROARE] {vm_name} nu există în configurație"
    )

temporary_file = vm_file.with_suffix(vm_file.suffix + ".tmp")

temporary_file.write_text(
    json.dumps(data, indent=2) + "\n",
    encoding="utf-8",
)

temporary_file.replace(vm_file)

print(f"[OK] {vm_name} a fost eliminat din configurația dorită")
PYTHON

if [[ $? -ne 0 ]]; then
    restore_configuration
    exit 1
fi

PLAN_NAME="destroy-ubuntu-${VM_NAME}-$(date +%Y%m%d-%H%M%S).tfplan"

echo
echo "[INFO] Verific configurația Terraform..."

if ! run_terraform "terraform validate"; then
    echo "[EROARE] terraform validate a eșuat."
    restore_configuration
    exit 1
fi

echo
echo "[INFO] Generez planul de distrugere..."

if ! run_terraform "terraform plan -out='${PLAN_NAME}'"; then
    echo "[EROARE] terraform plan a eșuat."
    restore_configuration
    exit 1
fi

echo
echo "============================================================"
echo "Verifică planul afișat."
echo
echo "Trebuie distruse numai:"
echo "  - VM-ul Ubuntu ${VM_NAME}"
echo "  - terraform_data asociat lui ${VM_NAME}"
echo
echo "Celelalte VM-uri trebuie păstrate."
echo "============================================================"
echo

read -rp "Scrie DESTROY pentru aplicarea planului: " DESTROY_CONFIRMATION

DESTROY_CONFIRMATION="${DESTROY_CONFIRMATION^^}"

if [[ "${DESTROY_CONFIRMATION}" != "DESTROY" ]]; then
    echo "[INFO] Distrugerea a fost anulată."
    restore_configuration
    exit 0
fi

DESTROY_STARTED=true

echo
echo "[INFO] Aplic planul ${PLAN_NAME}..."

run_terraform "terraform apply '${PLAN_NAME}'"

DESTROY_RESULT=$?

echo
echo "[INFO] Cod returnat de Terraform: ${DESTROY_RESULT}"

if [[ "${DESTROY_RESULT}" -ne 0 ]]; then
    echo "[EROARE] Distrugerea nu s-a terminat cu succes."
    echo "[INFO] Configurația nu a fost restaurată automat."
    echo "[INFO] Verifică Proxmox și terraform state."
    exit "${DESTROY_RESULT}"
fi

echo
echo "[INFO] Regenerez inventarul Ansible..."

if ! python3 \
    "${SYNC_SCRIPT}" \
    "${VM_FILE}" \
    "${INVENTORY_FILE}"
then
    echo "[AVERTISMENT] VM-ul a fost șters, dar inventarul nu a putut fi regenerat."
    exit 1
fi

echo
echo "============================================================"
echo "[OK] VM-ul ${VM_NAME}, ID ${VM_ID}, a fost șters."
echo "[OK] Inventarul Ansible a fost actualizat."
echo "============================================================"