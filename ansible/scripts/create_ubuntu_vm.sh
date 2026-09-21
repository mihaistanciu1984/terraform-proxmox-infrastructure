#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_VERSION="2026-09-17-v3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="$(cd "${ANSIBLE_DIR}/.." && pwd)"

VM_FILE="${TERRAFORM_DIR}/ubuntu_vms.auto.tfvars.json"
WINDOWS_VM_FILE="${TERRAFORM_DIR}/windows_vms.auto.tfvars.json"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/generated_ubuntu.yml"
SYNC_INVENTORY_SCRIPT="${SCRIPT_DIR}/sync_ubuntu_inventory.py"

TERRAFORM_WINDOWS_DIR="$(wslpath -w "${TERRAFORM_DIR}")"

BACKUP_DIR=""
APPLY_STARTED=false
PLAN_NAME=""
PLAN_JSON=""

run_terraform() {
    local terraform_command="$1"

    powershell.exe -NoProfile -Command \
        "Set-Location -LiteralPath '${TERRAFORM_WINDOWS_DIR}'; ${terraform_command}; exit \$LASTEXITCODE"
}

export_plan_json() {
    powershell.exe -NoProfile -Command \
        "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(\$false); Set-Location -LiteralPath '${TERRAFORM_WINDOWS_DIR}'; terraform show -json '${PLAN_NAME}'; exit \$LASTEXITCODE" \
        >"${PLAN_JSON}"
}

check_running_terraform() {
    powershell.exe -NoProfile -Command \
        "if (Get-Process terraform -ErrorAction SilentlyContinue) { exit 20 } else { exit 0 }"

    local process_result=$?

    if [[ "${process_result}" -eq 20 ]]; then
        echo "[EROARE] Există deja un proces Terraform activ."
        echo "[INFO] Verifică celelalte terminale înainte de a continua."
        return 1
    fi

    return 0
}

restore_configuration() {
    if [[ "${APPLY_STARTED}" == "true" ]]; then
        echo "[INFO] Terraform apply a început."
        echo "[INFO] Configurația nu va fi restaurată automat."
        return 0
    fi

    if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
        return 0
    fi

    echo "[INFO] Restaurez configurația anterioară..."

    if [[ -f "${BACKUP_DIR}/ubuntu_vms.json" ]]; then
        cp "${BACKUP_DIR}/ubuntu_vms.json" "${VM_FILE}"
    fi

    if [[ -f "${BACKUP_DIR}/generated_ubuntu.yml" ]]; then
        cp "${BACKUP_DIR}/generated_ubuntu.yml" "${INVENTORY_FILE}"
    elif [[ -f "${INVENTORY_FILE}" ]]; then
        rm -- "${INVENTORY_FILE}"
    fi
}

cleanup() {
    if [[ -n "${PLAN_JSON}" && -f "${PLAN_JSON}" ]]; then
        rm -- "${PLAN_JSON}"
    fi

    if [[ -n "${BACKUP_DIR}" && -d "${BACKUP_DIR}" ]]; then
        rm -r -- "${BACKUP_DIR}"
    fi
}

handle_interrupt() {
    echo
    echo "[INFO] Operația a fost întreruptă."
    restore_configuration
    exit 130
}

trap handle_interrupt INT TERM
trap cleanup EXIT

validate_required_files() {
    local missing=0

    for required_file in \
        "${VM_FILE}" \
        "${SYNC_INVENTORY_SCRIPT}" \
        "${ANSIBLE_DIR}/ansible.cfg" \
        "${ANSIBLE_DIR}/playbooks/configure_ubuntu.yml"
    do
        if [[ ! -f "${required_file}" ]]; then
            echo "[EROARE] Fișier lipsă: ${required_file}"
            missing=1
        fi
    done

    if [[ "${missing}" -ne 0 ]]; then
        return 1
    fi

    for required_command in python3 powershell.exe wslpath; do
        if ! command -v "${required_command}" >/dev/null 2>&1; then
            echo "[EROARE] Comanda ${required_command} nu este disponibilă."
            return 1
        fi
    done

    if [[ -z "${TERRAFORM_WINDOWS_DIR}" ]]; then
        echo "[EROARE] Nu am putut determina calea Windows a proiectului Terraform."
        return 1
    fi

    return 0
}

add_vm_to_configuration() {
    python3 - \
        "${VM_FILE}" \
        "${WINDOWS_VM_FILE}" \
        "${VM_NAME}" \
        "${VM_ID}" \
        "${VM_IP}" <<'PYTHON'
import ipaddress
import json
import pathlib
import re
import sys

vm_file = pathlib.Path(sys.argv[1])
windows_vm_file = pathlib.Path(sys.argv[2])
vm_name = sys.argv[3].strip()
vm_id_text = sys.argv[4].strip()
vm_ip_text = sys.argv[5].strip()

if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,62}", vm_name):
    raise SystemExit(
        "[EROARE] Numele VM poate conține numai litere, cifre și -."
    )

try:
    vm_id = int(vm_id_text)
except ValueError:
    raise SystemExit("[EROARE] VM ID trebuie să fie numeric.")

if not 100 <= vm_id <= 999999999:
    raise SystemExit("[EROARE] VM ID este în afara intervalului acceptat.")

try:
    interface = ipaddress.ip_interface(vm_ip_text)
except ValueError:
    raise SystemExit(
        "[EROARE] Adresă invalidă. Exemplu: 192.0.2.175/24."
    )

if interface.version != 4:
    raise SystemExit("[EROARE] Sunt acceptate numai adrese IPv4.")

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

ubuntu_vms = data.setdefault("ubuntu_vms", {})

other_groups = [("Ubuntu", ubuntu_vms)]

if windows_vm_file.is_file():
    with windows_vm_file.open("r", encoding="utf-8-sig") as stream:
        windows_data = json.load(stream)
    other_groups.append(("Windows", windows_data.get("windows_vms", {})))

for group_name, group in other_groups:
    for existing_name, existing_vm in group.items():
        if existing_name == vm_name:
            raise SystemExit(
                f"[EROARE] Numele {vm_name} există deja în configurația {group_name}."
            )

        if int(existing_vm["vm_id"]) == vm_id:
            raise SystemExit(
                f"[EROARE] VM ID {vm_id} este utilizat de "
                f"{existing_name} ({group_name})."
            )

        existing_ip = str(
            ipaddress.ip_interface(existing_vm["ip_address"]).ip
        )

        if existing_ip == str(interface.ip):
            raise SystemExit(
                f"[EROARE] IP-ul {interface.ip} este utilizat de "
                f"{existing_name} ({group_name})."
            )

data["create_ubuntu"] = True
ubuntu_vms[vm_name] = {
    "vm_id": vm_id,
    "ip_address": str(interface),
}

temporary_file = vm_file.with_suffix(vm_file.suffix + ".tmp")
temporary_file.write_text(
    json.dumps(data, indent=2) + "\n",
    encoding="utf-8",
)
temporary_file.replace(vm_file)

print(f"[OK] {vm_name} a fost adăugat în {vm_file}.")
print("[OK] create_ubuntu a fost setat la true.")
PYTHON
}

verify_synchronization() {
    python3 - \
        "${VM_FILE}" \
        "${INVENTORY_FILE}" \
        "${VM_NAME}" \
        "${VM_ID}" \
        "${VM_IP}" <<'PYTHON'
import ipaddress
import json
import pathlib
import sys

vm_file = pathlib.Path(sys.argv[1])
inventory_file = pathlib.Path(sys.argv[2])
vm_name = sys.argv[3]
expected_vm_id = int(sys.argv[4])
expected_ip = str(ipaddress.ip_interface(sys.argv[5]).ip)

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

if data.get("create_ubuntu") is not True:
    raise SystemExit("[EROARE] create_ubuntu nu este true.")

vm = data.get("ubuntu_vms", {}).get(vm_name)

if vm is None:
    raise SystemExit(
        f"[EROARE] {vm_name} lipsește din configurația Terraform."
    )

if int(vm["vm_id"]) != expected_vm_id:
    raise SystemExit(f"[EROARE] VM ID incorect pentru {vm_name}.")

configured_ip = str(ipaddress.ip_interface(vm["ip_address"]).ip)

if configured_ip != expected_ip:
    raise SystemExit(f"[EROARE] IP incorect pentru {vm_name}.")

if not inventory_file.is_file():
    raise SystemExit(f"[EROARE] Inventarul {inventory_file} nu există.")

inventory_content = inventory_file.read_text(encoding="utf-8")
host_line = f"        {vm_name}:"
ip_line = f"          ansible_host: {expected_ip}"

if host_line not in inventory_content:
    raise SystemExit(
        f"[EROARE] {vm_name} lipsește din inventarul Ansible."
    )

if ip_line not in inventory_content:
    raise SystemExit(
        f"[EROARE] IP-ul {expected_ip} lipsește din inventarul Ansible."
    )

print(f"[OK] {vm_name} este sincronizat între Terraform și Ansible.")
PYTHON
}

verify_plan() {
    python3 - "${PLAN_JSON}" "${VM_NAME}" <<'PYTHON'
import json
import pathlib
import sys

plan_file = pathlib.Path(sys.argv[1])
vm_name = sys.argv[2]

with plan_file.open("r", encoding="utf-8-sig") as stream:
    plan = json.load(stream)

expected_vm = (
    f'module.ubuntu_server["{vm_name}"]'
    '.proxmox_virtual_environment_vm.ubuntu_vm[0]'
)
expected_automation = (
    f'terraform_data.ubuntu_ansible_configuration["{vm_name}"]'
)
allowed = {expected_vm, expected_automation}
created = set()

for change in plan.get("resource_changes", []):
    address = change.get("address", "")
    actions = change.get("change", {}).get("actions", [])

    if actions in (["no-op"], ["read"]):
        continue

    if "windows" in address.lower():
        raise SystemExit(
            f"[BLOCARE] Planul conține o resursă Windows: {address}"
        )

    if "delete" in actions or "update" in actions:
        raise SystemExit(
            f"[BLOCARE] Planul modifică sau șterge o resursă: "
            f"{address} -> {actions}"
        )

    if address not in allowed:
        raise SystemExit(
            f"[BLOCARE] Planul conține o resursă neașteptată: "
            f"{address} -> {actions}"
        )

    if actions != ["create"]:
        raise SystemExit(
            f"[BLOCARE] Acțiuni neașteptate pentru {address}: {actions}"
        )

    created.add(address)

missing = allowed - created
if missing:
    raise SystemExit(
        "[BLOCARE] Planul nu creează toate resursele așteptate: "
        + ", ".join(sorted(missing))
    )

print("[OK] Plan verificat: 2 resurse Ubuntu create, fără Windows/destroy/replace.")
PYTHON
}

check_port() {
    local ip_address="$1"
    local port="$2"
    local service_name="$3"

    if nc -z -w 5 "${ip_address}" "${port}" >/dev/null 2>&1; then
        echo "[OK] ${service_name}: ${ip_address}:${port}"
        return 0
    fi

    echo "[AVERTISMENT] ${service_name} nu răspunde: ${ip_address}:${port}"
    return 1
}

echo "============================================================"
echo "             CREATE UBUNTU VM IN PROXMOX"
echo "============================================================"
echo " Versiune: ${SCRIPT_VERSION}"
echo

validate_required_files || exit 1
check_running_terraform || exit 1

read -rp "Numele noului VM: " VM_NAME
read -rp "VM ID: " VM_ID
read -rp "IP management (CIDR opțional, implicit /24): " VM_IP

VM_NAME="${VM_NAME//[[:space:]]/}"
VM_ID="${VM_ID//[[:space:]]/}"
VM_IP="${VM_IP//[[:space:]]/}"

if [[ "${VM_IP}" != */* ]]; then
    VM_IP="${VM_IP}/24"
    echo "[INFO] CIDR absent; folosesc ${VM_IP}."
fi

PLAN_NAME="ubuntu-${VM_NAME}-$(date +%Y%m%d-%H%M%S).tfplan"
PLAN_JSON="${TERRAFORM_DIR}/${PLAN_NAME}.json"

echo
echo "Configurație solicitată:"
echo "  Nume VM : ${VM_NAME}"
echo "  VM ID   : ${VM_ID}"
echo "  IP      : ${VM_IP}"
echo "  Plan    : ${PLAN_NAME}"
echo

read -rp "Continui cu validarea? [y/N]: " INITIAL_CONFIRMATION

if [[ ! "${INITIAL_CONFIRMATION}" =~ ^[Yy]$ ]]; then
    echo "[INFO] Operația a fost anulată."
    exit 0
fi

BACKUP_DIR="$(mktemp -d)"
cp "${VM_FILE}" "${BACKUP_DIR}/ubuntu_vms.json"

if [[ -f "${INVENTORY_FILE}" ]]; then
    cp "${INVENTORY_FILE}" "${BACKUP_DIR}/generated_ubuntu.yml"
fi

echo
echo "[INFO] Adaug VM-ul în configurația Terraform..."

if ! add_vm_to_configuration; then
    restore_configuration
    exit 1
fi

echo
echo "[INFO] Generez inventarul Ansible..."

if ! python3 "${SYNC_INVENTORY_SCRIPT}" "${VM_FILE}" "${INVENTORY_FILE}"; then
    echo "[EROARE] Generarea inventarului a eșuat."
    restore_configuration
    exit 1
fi

echo
echo "[INFO] Verific sincronizarea Terraform-Ansible..."

if ! verify_synchronization; then
    restore_configuration
    exit 1
fi

echo
echo "[INFO] Verific configurația Terraform..."

if ! run_terraform "terraform validate"; then
    echo "[EROARE] terraform validate a eșuat."
    restore_configuration
    exit 1
fi

echo
echo "[INFO] Generez planul țintit ${PLAN_NAME}..."

TARGET_VM="module.ubuntu_server[\\\"${VM_NAME}\\\"].proxmox_virtual_environment_vm.ubuntu_vm[0]"
TARGET_AUTOMATION="terraform_data.ubuntu_ansible_configuration[\\\"${VM_NAME}\\\"]"

if ! run_terraform \
    "terraform plan -input=false -var='vm_check_password=' -target='${TARGET_VM}' -target='${TARGET_AUTOMATION}' -out='${PLAN_NAME}'"
then
    echo "[EROARE] terraform plan a eșuat."
    restore_configuration
    exit 1
fi

echo
echo "[INFO] Verific automat conținutul planului..."

if ! export_plan_json; then
    echo "[EROARE] Nu am putut exporta planul în format JSON."
    restore_configuration
    exit 1
fi

if ! verify_plan; then
    echo "[EROARE] Planul nu este sigur și nu va fi aplicat."
    restore_configuration
    exit 1
fi

echo
run_terraform "terraform show -no-color '${PLAN_NAME}'"

echo
echo "============================================================"
echo "Planul a trecut verificările automate."
echo "Va fi creat exclusiv VM-ul Ubuntu ${VM_NAME} (${VM_ID})."
echo "============================================================"
echo

read -rp "Scrie APPLY pentru a aplica planul: " APPLY_CONFIRMATION
APPLY_CONFIRMATION="${APPLY_CONFIRMATION^^}"

if [[ "${APPLY_CONFIRMATION}" != "APPLY" ]]; then
    echo "[INFO] Aplicarea a fost anulată."
    restore_configuration
    exit 0
fi

APPLY_STARTED=true

echo
echo "[INFO] Încep Terraform apply pentru ${VM_NAME}."
echo "[INFO] Configurația nu va mai fi restaurată automat."

run_terraform "terraform apply -input=false '${PLAN_NAME}'"
APPLY_RESULT=$?

echo
echo "[INFO] Cod returnat de Terraform apply: ${APPLY_RESULT}"

if [[ "${APPLY_RESULT}" -ne 0 ]]; then
    echo "[EROARE] Terraform apply sau configurarea Ansible a eșuat."
    echo "[INFO] VM-ul rămâne în JSON și în inventarul Ansible."
    echo "[INFO] Verifică Proxmox și terraform state înainte de reluare."
    exit "${APPLY_RESULT}"
fi

MANAGEMENT_IP="${VM_IP%/*}"

echo
echo "============================================================"
echo "                   VERIFICĂRI FINALE"
echo "============================================================"

check_port "${MANAGEMENT_IP}" 22 "SSH"
check_port "${MANAGEMENT_IP}" 3389 "RDP/XRDP"
check_port "${MANAGEMENT_IP}" 10050 "Zabbix Agent 2"

echo
echo "[OK] Procesul pentru ${VM_NAME} s-a terminat."