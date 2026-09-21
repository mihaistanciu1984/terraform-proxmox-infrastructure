#!/usr/bin/env python3

import ipaddress
import json
import pathlib
import sys


def main():
    if len(sys.argv) != 3:
        print(
            "Usage: sync_windows_inventory.py "
            "<windows_vms.auto.tfvars.json> "
            "<generated_windows.yml>",
            file=sys.stderr,
        )
        return 1

    vm_file = pathlib.Path(sys.argv[1])
    inventory_file = pathlib.Path(sys.argv[2])

    if not vm_file.is_file():
        print(
            f"[ERROR] Terraform VM file not found: {vm_file}",
            file=sys.stderr,
        )
        return 1

    try:
        with vm_file.open("r", encoding="utf-8-sig") as stream:
            data = json.load(stream)
    except (OSError, json.JSONDecodeError) as error:
        print(
            f"[ERROR] Cannot read {vm_file}: {error}",
            file=sys.stderr,
        )
        return 1

    windows_vms = data.get("windows_vms")

    if not isinstance(windows_vms, dict):
        print(
            "[ERROR] windows_vms is missing or is not an object",
            file=sys.stderr,
        )
        return 1

    inventory_lines = [
        "---",
        "all:",
        "  children:",
        "    windows:",
        "      hosts:",
    ]

    for vm_name, vm_configuration in sorted(windows_vms.items()):
        try:
            vm_interface = ipaddress.ip_interface(
                vm_configuration["ip_address"]
            )
            windows_username = vm_configuration["windows_username"]
        except (KeyError, ValueError, TypeError) as error:
            print(
                f"[ERROR] Invalid configuration for {vm_name}: {error}",
                file=sys.stderr,
            )
            return 1

        management_ip = str(vm_interface.ip)

        inventory_lines.extend(
            [
                f"        {vm_name}:",
                f"          ansible_host: {management_ip}",
                f"          ansible_user: {windows_username}",
                "          ansible_connection: ssh",
                "          ansible_shell_type: powershell",

            ]
        )

    inventory_content = "\n".join(inventory_lines) + "\n"

    inventory_file.parent.mkdir(parents=True, exist_ok=True)

    temporary_file = inventory_file.with_suffix(
        inventory_file.suffix + ".tmp"
    )

    temporary_file.write_text(
        inventory_content,
        encoding="utf-8",
    )

    temporary_file.replace(inventory_file)

    print(
        f"[OK] Generated {inventory_file} "
        f"with {len(windows_vms)} Windows VM(s)"
    )

    for vm_name, vm_configuration in sorted(windows_vms.items()):
        management_ip = ipaddress.ip_interface(
            vm_configuration["ip_address"]
        ).ip

        print(
            f"  - {vm_name}: "
            f"VM ID {vm_configuration['vm_id']}, "
            f"IP {management_ip}, "
            f"User {vm_configuration['windows_username']}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())