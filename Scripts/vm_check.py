#!/usr/bin/env python3

import argparse
import os
import socket
import sys
import time


def normalize_ip(value: str) -> str:
    return value.split("/", 1)[0].strip()


def tcp_open(ip_address: str, port: int, timeout: float = 5.0) -> bool:
    try:
        with socket.create_connection((ip_address, port), timeout=timeout):
            return True
    except OSError:
        return False


def wait_for_port(ip_address: str, port: int, timeout: int, label: str) -> None:
    deadline = time.monotonic() + timeout
    next_message = 0.0

    while time.monotonic() < deadline:
        if tcp_open(ip_address, port):
            print(f"[OK] {label}: {ip_address}:{port}", flush=True)
            return

        if time.monotonic() >= next_message:
            remaining = max(0, int(deadline - time.monotonic()))
            print(
                f"[INFO] Aștept {label} pe {ip_address}:{port} "
                f"({remaining}s rămase)...",
                flush=True,
            )
            next_message = time.monotonic() + 30

        time.sleep(5)

    raise RuntimeError(
        f"{label} nu a devenit disponibil pe {ip_address}:{port} "
        f"în {timeout} secunde."
    )


def check_windows_ssh(
    ip_address: str,
    username: str,
    password: str,
    timeout: int,
) -> None:
    try:
        import paramiko
    except ImportError as exc:
        raise RuntimeError(
            "Lipsește modulul Python paramiko. Instalează-l cu: "
            "python -m pip install paramiko"
        ) from exc

    deadline = time.monotonic() + timeout
    authentication_failures = 0
    last_error = "necunoscută"

    while time.monotonic() < deadline:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        try:
            client.connect(
                hostname=ip_address,
                port=22,
                username=username,
                password=password,
                timeout=15,
                banner_timeout=30,
                auth_timeout=30,
                look_for_keys=False,
                allow_agent=False,
            )

            _, stdout, stderr = client.exec_command("whoami", timeout=30)
            identity = stdout.read().decode("utf-8", errors="replace").strip()
            error_text = stderr.read().decode("utf-8", errors="replace").strip()
            exit_status = stdout.channel.recv_exit_status()

            if exit_status != 0:
                raise RuntimeError(
                    f"Comanda whoami a eșuat: {error_text or exit_status}"
                )

            print(f"[OK] Autentificare SSH Windows: {identity}", flush=True)
            return

        except paramiko.AuthenticationException:
            authentication_failures += 1
            last_error = "autentificare respinsă"

            if authentication_failures >= 3:
                raise RuntimeError(
                    "Autentificarea SSH a fost respinsă de 3 ori. "
                    "Verifică utilizatorul, parola și configurația Cloudbase-Init."
                )

        except Exception as exc:  # network/banner errors while Windows boots
            last_error = str(exc)

        finally:
            client.close()

        print(f"[INFO] SSH nu este încă pregătit: {last_error}", flush=True)
        time.sleep(10)

    raise RuntimeError(
        f"SSH nu a putut fi verificat în {timeout} secunde. "
        f"Ultima eroare: {last_error}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Verifică o mașină virtuală.")
    parser.add_argument("--os", choices=("windows",), required=True)
    parser.add_argument("--ip", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()

    password = os.environ.get("VM_CHECK_PASSWORD", "")
    if not password:
        print("[EROARE] Variabila VM_CHECK_PASSWORD este goală.", file=sys.stderr)
        return 2

    ip_address = normalize_ip(args.ip)

    try:
        wait_for_port(ip_address, 22, args.timeout, "SSH")
        check_windows_ssh(ip_address, args.user, password, args.timeout)
        wait_for_port(ip_address, 3389, 300, "RDP")
    except RuntimeError as exc:
        print(f"[EROARE] {exc}", file=sys.stderr, flush=True)
        return 1

    print(f"[OK] Verificarea Windows pentru {ip_address} s-a încheiat.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
