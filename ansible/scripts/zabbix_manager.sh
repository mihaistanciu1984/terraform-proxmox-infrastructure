#!/usr/bin/env bash

set -u

# Directorul rădăcină al proiectului Ansible.
# Scriptul funcționează indiferent din ce director este lansat.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ANSIBLE_CONFIG_FILE="${ANSIBLE_DIR}/ansible.cfg"
SCAN_PLAYBOOK="${ANSIBLE_DIR}/playbooks/scan_zabbix_agents.yml"
INSTALL_PLAYBOOK="${ANSIBLE_DIR}/playbooks/install_zabbix_agent.yml"
TARGET_INVENTORY="${ANSIBLE_DIR}/inventory/zabbix_targets.yml"
REPORT_FILE="${ANSIBLE_DIR}/reports/zabbix_open_10050.txt"

export ANSIBLE_CONFIG="${ANSIBLE_CONFIG_FILE}"

cd "${ANSIBLE_DIR}" || {
    echo "[EROARE] Nu pot accesa directorul ${ANSIBLE_DIR}"
    exit 1
}

print_header() {
    clear
    echo "============================================================"
    echo "          ZABBIX AGENT 2 - MANAGEMENT TOOL"
    echo "============================================================"
    echo " Director Ansible : ${ANSIBLE_DIR}"
    echo " Inventory        : ${TARGET_INVENTORY}"
    echo " Raport scanare   : ${REPORT_FILE}"
    echo "============================================================"
    echo
}

pause_menu() {
    echo
    read -rp "Apasă ENTER pentru a reveni la meniu..."
}

check_requirements() {
    local missing=0

    echo "[INFO] Verific cerințele..."

    for command_name in ansible ansible-playbook ansible-inventory nmap; do
        if command -v "${command_name}" >/dev/null 2>&1; then
            echo "[OK] ${command_name}: $(command -v "${command_name}")"
        else
            echo "[LIPSĂ] ${command_name}"
            missing=1
        fi
    done

    if [[ ! -f "${ANSIBLE_CONFIG_FILE}" ]]; then
        echo "[EROARE] Lipsește ${ANSIBLE_CONFIG_FILE}"
        missing=1
    fi

    if [[ ! -f "${SCAN_PLAYBOOK}" ]]; then
        echo "[EROARE] Lipsește ${SCAN_PLAYBOOK}"
        missing=1
    fi

    if [[ ! -f "${INSTALL_PLAYBOOK}" ]]; then
        echo "[EROARE] Lipsește ${INSTALL_PLAYBOOK}"
        missing=1
    fi

    if [[ ! -f "${TARGET_INVENTORY}" ]]; then
        echo "[EROARE] Lipsește ${TARGET_INVENTORY}"
        missing=1
    fi

    if [[ "${missing}" -ne 0 ]]; then
        echo
        echo "Instalează componentele lipsă cu:"
        echo "sudo apt update"
        echo "sudo apt install -y ansible nmap"
        return 1
    fi

    echo
    echo "[OK] Toate cerințele sunt îndeplinite."
}

syntax_check() {
    echo "[INFO] Verific sintaxa playbook-ului de scanare..."

    ansible-playbook \
        "${SCAN_PLAYBOOK}" \
        --syntax-check || return 1

    echo
    echo "[INFO] Verific sintaxa playbook-ului de instalare..."

    ansible-playbook \
        -i "${TARGET_INVENTORY}" \
        "${INSTALL_PLAYBOOK}" \
        --syntax-check
}

scan_network() {
    local subnet

    echo "Introdu subnetul autorizat pentru scanare."
    echo "Exemplu: 192.0.2.0/24"
    echo
    read -rp "Subnet: " subnet

    if [[ -z "${subnet}" ]]; then
        echo "[EROARE] Subnetul nu poate fi gol."
        return 1
    fi

    echo
    echo "[INFO] Se va scana ${subnet} pentru TCP 10050."
    read -rp "Continui? [y/N]: " confirmation

    if [[ ! "${confirmation}" =~ ^[Yy]$ ]]; then
        echo "[INFO] Scanarea a fost anulată."
        return 0
    fi

    ansible-playbook \
        "${SCAN_PLAYBOOK}" \
        --extra-vars "zabbix_scan_network=${subnet}"

    local result=$?

    if [[ "${result}" -eq 0 ]]; then
        echo
        echo "[OK] Scanarea s-a terminat."

        if [[ -f "${REPORT_FILE}" ]]; then
            echo
            echo "IP-uri cu portul TCP 10050 deschis:"
            echo "------------------------------------------------------------"

            if [[ -s "${REPORT_FILE}" ]]; then
                cat "${REPORT_FILE}"
            else
                echo "Nu au fost detectate porturi TCP 10050 deschise."
            fi

            echo "------------------------------------------------------------"
            echo "Raport: ${REPORT_FILE}"
        fi
    else
        echo "[EROARE] Scanarea a eșuat."
    fi

    return "${result}"
}

show_report() {
    if [[ ! -f "${REPORT_FILE}" ]]; then
        echo "[INFO] Raportul nu există încă."
        echo "Rulează mai întâi opțiunea de scanare."
        return 0
    fi

    echo "============================================================"
    echo " IP-URI CU PORTUL TCP 10050 DESCHIS"
    echo "============================================================"

    if [[ -s "${REPORT_FILE}" ]]; then
        cat "${REPORT_FILE}"
    else
        echo "Raportul este gol."
    fi
}

show_inventory() {
    echo "[INFO] Inventarul folosit pentru instalare:"
    echo "${TARGET_INVENTORY}"
    echo

    ansible-inventory \
        -i "${TARGET_INVENTORY}" \
        --graph
}

test_ssh() {
    echo "[INFO] Testez accesul Ansible la sistemele aprobate..."

    ansible \
        -i "${TARGET_INVENTORY}" \
        zabbix_targets \
        -m ansible.builtin.ping
}

install_all_agents() {
    echo "ATENȚIE: Zabbix Agent 2 va fi instalat sau reconfigurat"
    echo "pe toate sistemele din grupul zabbix_targets."
    echo
    echo "Inventory: ${TARGET_INVENTORY}"
    echo

    ansible-inventory \
        -i "${TARGET_INVENTORY}" \
        --graph || return 1

    echo
    read -rp "Scrie INSTALL pentru confirmare: " confirmation

    if [[ "${confirmation}" != "INSTALL" ]]; then
        echo "[INFO] Instalarea a fost anulată."
        return 0
    fi

    ansible-playbook \
        -i "${TARGET_INVENTORY}" \
        "${INSTALL_PLAYBOOK}"
}

install_single_agent() {
    local target_host

    echo "[INFO] Hosturile disponibile:"
    echo

    ansible-inventory \
        -i "${TARGET_INVENTORY}" \
        --graph || return 1

    echo
    read -rp "Introdu numele hostului, de exemplu ubuntu-01: " target_host

    if [[ -z "${target_host}" ]]; then
        echo "[EROARE] Numele hostului nu poate fi gol."
        return 1
    fi

    echo
    echo "Va fi procesat numai hostul: ${target_host}"
    read -rp "Scrie INSTALL pentru confirmare: " confirmation

    if [[ "${confirmation}" != "INSTALL" ]]; then
        echo "[INFO] Instalarea a fost anulată."
        return 0
    fi

    ansible-playbook \
        -i "${TARGET_INVENTORY}" \
        "${INSTALL_PLAYBOOK}" \
        --limit "${target_host}"
}

verify_agents() {
    echo "[INFO] Verific serviciul Zabbix Agent 2..."

    ansible \
        -i "${TARGET_INVENTORY}" \
        zabbix_targets \
        --become \
        -m ansible.builtin.command \
        -a "systemctl is-active zabbix-agent2"

    echo
    echo "[INFO] Verific portul TCP 10050 pe sistemele administrate..."

    ansible \
        -i "${TARGET_INVENTORY}" \
        zabbix_targets \
        --become \
        -m ansible.builtin.shell \
        -a "ss -lntp | grep ':10050'"
}

while true; do
    print_header

    echo "1) Verifică cerințele"
    echo "2) Verifică sintaxa playbook-urilor"
    echo "3) Scanează rețeaua pentru TCP 10050"
    echo "4) Afișează ultimul raport de scanare"
    echo "5) Afișează inventarul aprobat"
    echo "6) Testează conexiunea Ansible/SSH"
    echo "7) Instalează agentul pe toate IP-urile aprobate"
    echo "8) Instalează agentul pe un singur host"
    echo "9) Verifică serviciul și portul 10050"
    echo "0) Ieșire"
    echo

    read -rp "Selectează opțiunea: " option

    echo

    case "${option}" in
        1) check_requirements ;;
        2) syntax_check ;;
        3) scan_network ;;
        4) show_report ;;
        5) show_inventory ;;
        6) test_ssh ;;
        7) install_all_agents ;;
        8) install_single_agent ;;
        9) verify_agents ;;
        0)
            echo "Închidere."
            exit 0
            ;;
        *)
            echo "[EROARE] Opțiune invalidă."
            ;;
    esac

    pause_menu
done