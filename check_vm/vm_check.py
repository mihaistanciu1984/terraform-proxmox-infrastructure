import argparse
import getpass
import os
import socket
import sys
import time

import paramiko


# ============================================================
# OUTPUT
# ============================================================

def print_ok(message):
    print(f"[ OK ] {message}")


def print_fail(message):
    print(f"[FAIL] {message}")


def print_info(message):
    print(f"[INFO] {message}")


# ============================================================
# TCP PORT CHECK
# ============================================================

def check_tcp_port(host, port, service, timeout=5):
    print_info(f"Testing {service} ({host}:{port})...")

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)

    try:
        result = sock.connect_ex((host, port))

        if result == 0:
            print_ok(f"{service} port {port} is reachable")
            return True

        print_fail(f"{service} port {port} is NOT reachable")
        return False

    except Exception as exc:
        print_fail(f"{service} check failed: {exc}")
        return False

    finally:
        sock.close()


# ============================================================
# SSH
# ============================================================

def ssh_connect(host, username, password, timeout=5):
    client = paramiko.SSHClient()

    # VM-ul este creat din template.
    # Acceptăm automat host key-ul pentru VM-ul nou.
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        client.connect(
            hostname=host,
            port=22,
            username=username,
            password=password,
            timeout=timeout,
            banner_timeout=timeout,
            auth_timeout=timeout,
            look_for_keys=False,
            allow_agent=False,
        )

        return client

    except Exception:
        try:
            client.close()
        except Exception:
            pass

        return None


# ============================================================
# WAIT FOR SSH
# ============================================================

def wait_for_ssh(host, username, password, retries=30, delay=10):
    print_info(
        f"Waiting for SSH on {host}:22 "
        f"(timeout {retries * delay}s)..."
    )

    for attempt in range(1, retries + 1):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)

        try:
            result = sock.connect_ex((host, 22))
        except Exception:
            result = 1
        finally:
            sock.close()

        if result == 0:
            client = ssh_connect(
                host,
                username,
                password,
                timeout=5,
            )

            if client:
                print_ok(
                    f"SSH authentication successful "
                    f"(after {(attempt - 1) * delay}s)"
                )
                return client

        if attempt < retries:
            time.sleep(delay)

    print_fail(
        f"SSH did not become available after "
        f"{retries * delay}s"
    )

    return None

# ============================================================
# SSH COMMAND
# ============================================================

def ssh_command(client, command):
    stdin, stdout, stderr = client.exec_command(command)

    output = stdout.read().decode(
        errors="replace"
    ).strip()

    error = stderr.read().decode(
        errors="replace"
    ).strip()

    return output, error


# ============================================================
# UBUNTU CHECK
# ============================================================

def check_linux_network(client, expected_ip):
    print_info("Checking Ubuntu network configuration...")

    success = True

    # --------------------------------------------------------
    # Interfaces
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "ip -br addr"
    )

    if error:
        print_fail(
            f"Could not get network interfaces: {error}"
        )
        return False

    print()
    print("--- Linux interfaces ---")
    print(output)
    print("------------------------")
    print()

    if expected_ip in output:
        print_ok(
            f"Management IP {expected_ip} found"
        )
    else:
        print_fail(
            f"Management IP {expected_ip} NOT found"
        )
        success = False

    # --------------------------------------------------------
    # Default route
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "ip route show default"
    )

    if output:
        print_ok(
            f"Default gateway detected: {output}"
        )
    else:
        print_fail(
            "No default gateway detected"
        )
        success = False

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "resolvectl status 2>/dev/null || cat /etc/resolv.conf"
    )

    if output:
        print_ok("DNS configuration detected")
    else:
        print_fail(
            "DNS configuration could not be detected"
        )
        success = False

    # --------------------------------------------------------
    # Internet by IP
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "ping -c 3 -W 3 8.8.8.8"
    )

    if "0% packet loss" in output:
        print_ok(
            "Internet connectivity by IP works"
        )
    else:
        print_fail(
            "Internet connectivity by IP FAILED"
        )
        success = False

    # --------------------------------------------------------
    # Internet + DNS
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "ping -c 3 -W 3 www.google.com"
    )

    if "0% packet loss" in output:
        print_ok(
            "DNS + Internet connectivity works"
        )
    else:
        print_fail(
            "DNS + Internet connectivity FAILED"
        )
        success = False

    return success


# ============================================================
# WINDOWS CHECK
# ============================================================

def check_windows_network(client, expected_ip):
    print_info("Checking Windows network configuration...")

    success = True

    # --------------------------------------------------------
    # IP configuration
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "ipconfig /all"
    )

    if error:
        print_fail(
            f"Could not get Windows network configuration: {error}"
        )
        return False

    print()
    print("--- Windows network configuration ---")
    print(output)
    print("-------------------------------------")
    print()

    # --------------------------------------------------------
    # Management IP
    # --------------------------------------------------------

    if expected_ip in output:
        print_ok(
            f"Management IP {expected_ip} found"
        )
    else:
        print_fail(
            f"Management IP {expected_ip} NOT found"
        )
        success = False

    # --------------------------------------------------------
    # Default route
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "route print 0.0.0.0"
    )

    if "0.0.0.0" in output:
        print_ok("Default route detected")
    else:
        print_fail(
            "Default route NOT detected"
        )
        success = False

    # --------------------------------------------------------
    # Internet by IP
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "ping -n 3 8.8.8.8"
    )

    if "Lost = 0" in output:
        print_ok(
            "Internet connectivity by IP works"
        )
    else:
        print_fail(
            "Internet connectivity by IP FAILED"
        )
        success = False

    # --------------------------------------------------------
    # DNS + Internet
    # --------------------------------------------------------

    output, error = ssh_command(
        client,
        "ping -n 3 www.google.com"
    )

    if "Lost = 0" in output:
        print_ok(
            "DNS + Internet connectivity works"
        )
    else:
        print_fail(
            "DNS + Internet connectivity FAILED"
        )
        success = False

    return success


# ============================================================
# MAIN
# ============================================================

def main():

    parser = argparse.ArgumentParser(
        description="Terraform VM connectivity checker"
    )

    parser.add_argument(
        "--os",
        required=True,
        choices=["ubuntu", "windows"],
        help="Operating system"
    )

    parser.add_argument(
        "--ip",
        required=True,
        help="Management IP address"
    )

    parser.add_argument(
        "--user",
        required=True,
        help="SSH username"
    )

    args = parser.parse_args()

    # IP-ul este primit cu /24.
    management_ip = args.ip.split("/")[0]

    # Terraform transmite parola prin environment variable.
    # Daca scriptul este rulat manual si variabila nu exista,
    # cerem parola interactively.
    password = os.environ.get("VM_CHECK_PASSWORD")

    if not password:
        password = getpass.getpass(
            f"Password for {args.user}@{management_ip}: "
        )

    print()

    print("=" * 65)
    print("                         VM CHECK")
    print("=" * 65)
    print(f"OS           : {args.os}")
    print(f"Management IP: {management_ip}")
    print(f"SSH user     : {args.user}")
    print("=" * 65)
    print()

    overall_success = True
# ========================================================
    # INITIAL BOOT WAIT
    # ========================================================

    if args.os == "windows":
        initial_wait = 50
        ssh_retries = 90
        ssh_delay = 10

        print_info(
            "Waiting 5 minutes for Windows/Cloudbase-Init "
            "and the first reboot to finish..."
        )

    else:
        initial_wait = 30
        ssh_retries = 30
        ssh_delay = 10

        print_info(
            "Waiting 30 seconds for Ubuntu/Cloud-Init "
            "to finish booting..."
        )

    time.sleep(initial_wait)
    # ========================================================
    # SSH
    # ========================================================
    ssh_client = wait_for_ssh(
        management_ip,
        args.user,
        password,
        retries=ssh_retries,
        delay=ssh_delay,
    )

    if not ssh_client:
        print_fail("SSH check FAILED")
        sys.exit(1)

    print_ok("SSH check PASSED")
    print()


  # ========================================================
    # OS SPECIFIC CHECKS
    # ========================================================

    if args.os == "ubuntu":

        # SSH a fost deja verificat prin autentificarea Paramiko.
        print_ok("SSH service and authentication are functional")
        print()

        # Verifică xrdp/RDP pe portul TCP 3389.
        if not check_tcp_port(
            management_ip,
            3389,
            "RDP/xrdp"
        ):
            overall_success = False

        print()

        # Verificarea configurației de rețea Ubuntu.
        if not check_linux_network(
            ssh_client,
            management_ip
        ):
            overall_success = False

    elif args.os == "windows":

        # Verificarea RDP pe portul TCP 3389.
        if not check_tcp_port(
            management_ip,
            3389,
            "RDP"
        ):
            overall_success = False

        print()

        # Verificarea configurației de rețea Windows.
        if not check_windows_network(
            ssh_client,
            management_ip
        ):
            overall_success = False

    # Închide conexiunea SSH indiferent de sistemul de operare.
    ssh_client.close()

    # ========================================================
    # RESULT
    # ========================================================

    print()

    print("=" * 65)

    if overall_success:

        print_ok("VM CHECK PASSED")
        print("=" * 65)
        sys.exit(0)

    print_fail("VM CHECK FAILED")
    print("=" * 65)
    sys.exit(1)


if __name__ == "__main__":
    main()