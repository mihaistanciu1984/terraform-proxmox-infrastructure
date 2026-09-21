#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_VERSION="2026-09-17-v1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="$(cd "${ANSIBLE_DIR}/.." && pwd)"

VM_FILE="${TERRAFORM_DIR}/windows_vms.auto.tfvars.json"
UBUNTU_VM_FILE="${TERRAFORM_DIR}/ubuntu_vms.auto.tfvars.json"
VM_CHECK_SCRIPT="${TERRAFORM_DIR}/Scripts/vm_check.py"
TERRAFORM_WINDOWS_DIR="$(wslpath -w "${TERRAFORM_DIR}")"

BACKUP_DIR=""
APPLY_STARTED=false
PLAN_NAME=""
PLAN_JSON=""
VM_CHECK_PASSWORD=""

run_terraform() {
    local terraform_command="$1"

    powershell.exe -NoProfile -Command \
        "Set-Location -LiteralPath '${TERRAFORM_WINDOWS_DIR}'; ${terraform_command}; exit \$LASTEXITCODE"
}

run_terraform_with_password() {
    local terraform_command="$1"

    printf '%s\n' "${VM_CHECK_PASSWORD}" | \
        powershell.exe -NoProfile -Command \
        "\$env:TF_VAR_vm_check_password = [Console]::In.ReadLine(); Set-Location -LiteralPath '${TERRAFORM_WINDOWS_DIR}'; ${terraform_command}; exit \$LASTEXITCODE"
}

export_plan_json() {
    powershell.exe -NoProfile -Command \
        "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(\$false); Set-Location -LiteralPath '${TERRAFORM_WINDOWS_DIR}'; terraform show -json '${PLAN_NAME}'; exit \$LASTEXITCODE" \
        >"${PLAN_JSON}"
}

remove_windows_plan() {
    if [[ -z "${PLAN_NAME}" || -z "${TERRAFORM_WINDOWS_DIR}" ]]; then
        return 0
    fi

    powershell.exe -NoProfile -Command \
        "Remove-Item -LiteralPath '${TERRAFORM_WINDOWS_DIR}\\${PLAN_NAME}' -Force -ErrorAction SilentlyContinue" \
        >/dev/null 2>&1 || true
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

    if [[ -n "${BACKUP_DIR}" && -f "${BACKUP_DIR}/windows_vms.json" ]]; then
        echo "[INFO] Restaurez configurația Windows anterioară..."
        cp "${BACKUP_DIR}/windows_vms.json" "${VM_FILE}"
    fi
}

cleanup() {
    VM_CHECK_PASSWORD=""
    unset VM_CHECK_PASSWORD

    if [[ -n "${PLAN_JSON}" && -f "${PLAN_JSON}" ]]; then
        rm -- "${PLAN_JSON}"
    fi

    remove_windows_plan

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

    for required_file in "${VM_FILE}" "${VM_CHECK_SCRIPT}"; do
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
        "${UBUNTU_VM_FILE}" \
        "${VM_NAME}" \
        "${VM_ID}" \
        "${VM_IP}" \
        "${TEMPLATE_ID}" \
        "${WINDOWS_USERNAME}" <<'PYTHON'
import ipaddress
import json
import pathlib
import re
import sys

vm_file = pathlib.Path(sys.argv[1])
ubuntu_vm_file = pathlib.Path(sys.argv[2])
vm_name = sys.argv[3].strip()
vm_id_text = sys.argv[4].strip()
vm_ip_text = sys.argv[5].strip()
template_id_text = sys.argv[6].strip()
windows_username = sys.argv[7].strip()

if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,62}", vm_name):
    raise SystemExit(
        "[EROARE] Numele VM poate conține numai litere, cifre și -."
    )

if not re.fullmatch(r"[A-Za-z0-9_.@-]{1,64}", windows_username):
    raise SystemExit("[EROARE] Numele utilizatorului Windows este invalid.")

try:
    vm_id = int(vm_id_text)
    template_id = int(template_id_text)
except ValueError:
    raise SystemExit("[EROARE] VM ID și Template ID trebuie să fie numerice.")

if not 100 <= vm_id <= 999999999:
    raise SystemExit("[EROARE] VM ID este în afara intervalului acceptat.")

if template_id != 9000:
    raise SystemExit(
        "[BLOCARE] Pentru acest flux este permis numai template-ul Windows 9000."
    )

try:
    interface = ipaddress.ip_interface(vm_ip_text)
except ValueError:
    raise SystemExit(
        "[EROARE] Adresă invalidă. Exemplu: 192.0.2.183/24."
    )

if interface.version != 4:
    raise SystemExit("[EROARE] Sunt acceptate numai adrese IPv4.")

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

windows_vms = data.setdefault("windows_vms", {})
groups = [("Windows", windows_vms)]

if ubuntu_vm_file.is_file():
    with ubuntu_vm_file.open("r", encoding="utf-8-sig") as stream:
        ubuntu_data = json.load(stream)
    groups.append(("Ubuntu", ubuntu_data.get("ubuntu_vms", {})))

for group_name, group in groups:
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

data["create_windows"] = True
windows_vms[vm_name] = {
    "vm_id": vm_id,
    "template_id": template_id,
    "ip_address": str(interface),
    "windows_username": windows_username,
}

temporary_file = vm_file.with_suffix(vm_file.suffix + ".tmp")
temporary_file.write_text(
    json.dumps(data, indent=2) + "\n",
    encoding="utf-8",
)
temporary_file.replace(vm_file)

print(f"[OK] {vm_name} a fost adăugat în {vm_file}.")
print("[OK] create_windows a fost setat la true.")
PYTHON
}

verify_configuration() {
    python3 - \
        "${VM_FILE}" \
        "${VM_NAME}" \
        "${VM_ID}" \
        "${VM_IP}" \
        "${TEMPLATE_ID}" \
        "${WINDOWS_USERNAME}" <<'PYTHON'
import ipaddress
import json
import pathlib
import sys

vm_file = pathlib.Path(sys.argv[1])
vm_name = sys.argv[2]
expected_vm_id = int(sys.argv[3])
expected_ip = str(ipaddress.ip_interface(sys.argv[4]))
expected_template = int(sys.argv[5])
expected_username = sys.argv[6]

with vm_file.open("r", encoding="utf-8-sig") as stream:
    data = json.load(stream)

if data.get("create_windows") is not True:
    raise SystemExit("[EROARE] create_windows nu este true.")

vm = data.get("windows_vms", {}).get(vm_name)
if vm is None:
    raise SystemExit(f"[EROARE] {vm_name} lipsește din configurație.")

checks = {
    "VM ID": (int(vm["vm_id"]), expected_vm_id),
    "IP": (str(ipaddress.ip_interface(vm["ip_address"])), expected_ip),
    "Template ID": (int(vm["template_id"]), expected_template),
    "Utilizator": (vm["windows_username"], expected_username),
}

for label, (actual, expected) in checks.items():
    if actual != expected:
        raise SystemExit(
            f"[EROARE] {label} incorect: {actual!r}, așteptat {expected!r}."
        )

print(f"[OK] Configurația Windows pentru {vm_name} este validă.")
PYTHON
}

verify_plan() {
    python3 - \
        "${PLAN_JSON}" \
        "${VM_NAME}" \
        "${VM_ID}" \
        "${TEMPLATE_ID}" <<'PYTHON'
import json
import pathlib
import sys

plan_file = pathlib.Path(sys.argv[1])
vm_name = sys.argv[2]
expected_vm_id = int(sys.argv[3])
expected_template_id = int(sys.argv[4])

with plan_file.open("r", encoding="utf-8-sig") as stream:
    plan = json.load(stream)

expected_vm = (
    f'module.windows_server["{vm_name}"]'
    '.proxmox_virtual_environment_vm.windows_vm[0]'
)
expected_check = f'terraform_data.windows_vm_check["{vm_name}"]'
allowed = {expected_vm, expected_check}
created = set()

for change in plan.get("resource_changes", []):
    address = change.get("address", "")
    actions = change.get("change", {}).get("actions", [])

    if actions in (["no-op"], ["read"]):
        continue

    if "ubuntu" in address.lower():
        raise SystemExit(
            f"[BLOCARE] Planul conține o resursă Ubuntu: {address}"
        )

    if "delete" in actions or "update" in actions:
        raise SystemExit(
            f"[BLOCARE] Planul modifică sau șterge o resursă: "
            f"{address} -> {actions}"
        )

    if address not in allowed:
        raise SystemExit(
            f"[BLOCARE] Resursă neașteptată: {address} -> {actions}"
        )

    if actions != ["create"]:
        raise SystemExit(
            f"[BLOCARE] Acțiuni neașteptate pentru {address}: {actions}"
        )

    if address == expected_vm:
        after = change.get("change", {}).get("after", {}) or {}
        if after.get("vm_id") != expected_vm_id:
            raise SystemExit("[BLOCARE] VM ID din plan nu este cel solicitat.")

        clone = after.get("clone") or []
        if not clone or clone[0].get("vm_id") != expected_template_id:
            raise SystemExit("[BLOCARE] Template ID din plan nu este cel solicitat.")

    created.add(address)

missing = allowed - created
if missing:
    raise SystemExit(
        "[BLOCARE] Planul nu creează toate resursele așteptate: "
        + ", ".join(sorted(missing))
    )

print("[OK] Plan verificat: 2 resurse Windows create, fără Ubuntu/destroy/replace.")
PYTHON
}

echo "============================================================"
echo "             CREATE WINDOWS VM IN PROXMOX"
echo "============================================================"
echo " Versiune: ${SCRIPT_VERSION}"
echo

validate_required_files || exit 1
check_running_terraform || exit 1

read -rp "Numele noului VM Windows: " VM_NAME
read -rp "VM ID: " VM_ID
read -rp "IP management (CIDR opțional, implicit /24): " VM_IP
read -rp "Template ID [9000]: " TEMPLATE_ID
read -rp "Utilizator Windows [Administrator]: " WINDOWS_USERNAME
read -rsp "Parola existentă a utilizatorului Windows: " VM_CHECK_PASSWORD
echo

VM_NAME="${VM_NAME//[[:space:]]/}"
VM_ID="${VM_ID//[[:space:]]/}"
VM_IP="${VM_IP//[[:space:]]/}"
TEMPLATE_ID="${TEMPLATE_ID//[[:space:]]/}"
WINDOWS_USERNAME="${WINDOWS_USERNAME//[[:space:]]/}"

TEMPLATE_ID="${TEMPLATE_ID:-9000}"
WINDOWS_USERNAME="${WINDOWS_USERNAME:-Administrator}"

if [[ "${VM_IP}" != */* ]]; then
    VM_IP="${VM_IP}/24"
    echo "[INFO] CIDR absent; folosesc ${VM_IP}."
fi

if [[ -z "${VM_CHECK_PASSWORD}" ]]; then
    echo "[EROARE] Parola de verificare nu poate fi goală."
    exit 1
fi

PLAN_NAME="windows-${VM_NAME}-$(date +%Y%m%d-%H%M%S).tfplan"
PLAN_JSON="${TERRAFORM_DIR}/${PLAN_NAME}.json"

echo
echo "Configurație solicitată:"
echo "  Nume VM      : ${VM_NAME}"
echo "  VM ID        : ${VM_ID}"
echo "  IP           : ${VM_IP}"
echo "  Template ID  : ${TEMPLATE_ID}"
echo "  Utilizator   : ${WINDOWS_USERNAME}"
echo "  Parolă       : [ascunsă]"
echo "  Plan         : ${PLAN_NAME}"
echo

read -rp "Continui cu validarea? [y/N]: " INITIAL_CONFIRMATION

if [[ ! "${INITIAL_CONFIRMATION}" =~ ^[Yy]$ ]]; then
    echo "[INFO] Operația a fost anulată."
    exit 0
fi

BACKUP_DIR="$(mktemp -d)"
cp "${VM_FILE}" "${BACKUP_DIR}/windows_vms.json"

echo
echo "[INFO] Adaug VM-ul Windows în configurația Terraform..."

if ! add_vm_to_configuration; then
    restore_configuration
    exit 1
fi

echo
echo "[INFO] Verific configurația Windows..."

if ! verify_configuration; then
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

TARGET_VM="module.windows_server[\\\"${VM_NAME}\\\"].proxmox_virtual_environment_vm.windows_vm[0]"
TARGET_CHECK="terraform_data.windows_vm_check[\\\"${VM_NAME}\\\"]"

echo
echo "[INFO] Generez planul Windows țintit ${PLAN_NAME}..."

if ! run_terraform_with_password \
    "terraform plan -input=false -var='windows_username=${WINDOWS_USERNAME}' -target='${TARGET_VM}' -target='${TARGET_CHECK}' -out='${PLAN_NAME}'"
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
echo "Va fi creat exclusiv VM-ul Windows ${VM_NAME} (${VM_ID})."
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
    echo "[EROARE] Apply sau verificarea Windows a eșuat."
    echo "[INFO] VM-ul poate fi deja creat; nu relansa opțiunea de creare."
    echo "[INFO] Verifică Proxmox și terraform state."
    exit "${APPLY_RESULT}"
fi

echo
echo "[OK] VM-ul Windows ${VM_NAME} a fost creat și verificat."
