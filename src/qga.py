import argparse
import base64
import json
import socket
import sys
import time

QGA_SOCKET = "/tmp/qga.sock"  # Adjust if needed


def send_qga_command(sock, command):
    """Send a JSON command to the QEMU Guest Agent socket and receive the response."""
    try:
        cmd = (json.dumps(command) + "\n").encode()
        sock.sendall(cmd)
        response = sock.recv(4096)
        return json.loads(response.decode())
    except socket.timeout:
        print(f"Timeout waiting for response from {QGA_SOCKET}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error communicating with socket: {e}", file=sys.stderr)
        return None


def decode_output(data):
    """Try to decode output as hex or Base64, or return raw."""
    if not data:
        return ""

    try:
        return bytes.fromhex(data).decode("utf-8", errors="ignore")
    except ValueError:
        pass

    try:
        return base64.b64decode(data).decode("utf-8", errors="ignore")
    except ValueError:
        pass

    return data


def execute_command(sock, command_path, command_args, timeout):
    """Execute a command inside the guest VM with specified path and arguments."""
    exec_request = {
        "execute": "guest-exec",
        "arguments": {
            "path": command_path,
            "arg": command_args,
            "capture-output": True,
        },
    }

    print(f"Executing: {command_path} {' '.join(command_args)}")
    response = send_qga_command(sock, exec_request)

    if response is None or "return" not in response or "pid" not in response["return"]:
        print(
            "Error: Failed to start execution.",
            json.dumps(response or {}, indent=2),
            file=sys.stderr,
        )
        return None

    pid = response["return"]["pid"]
    print(f"Command started with PID {pid}")

    # Step 2: Wait for completion with timeout
    start_time = time.time()
    status = {}
    while True:
        if time.time() - start_time > timeout:
            print("Execution timeout reached.", file=sys.stderr)
            return {"exit_code": -2, "stdout": "", "stderr": "Execution timed out."}

        status_request = {"execute": "guest-exec-status", "arguments": {"pid": pid}}
        status_response = send_qga_command(sock, status_request)

        if status_response and "return" in status_response:
            status = status_response["return"]
            if status.get("exited", False):
                break

        time.sleep(0.2)

    exit_code = status.get("exitcode", -1)
    stdout_data = decode_output(status.get("out-data", ""))
    stderr_data = decode_output(status.get("err-data", ""))

    return {"exit_code": exit_code, "stdout": stdout_data, "stderr": stderr_data}


def create_socket():
    """Create and return a reusable socket connection to the QEMU Guest Agent."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(30)
    try:
        sock.connect(QGA_SOCKET)
        return sock
    except Exception as e:
        print(f"Error creating socket: {e}", file=sys.stderr)
        return None


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Send commands to QEMU Guest Agent.")
    shell_group = parser.add_mutually_exclusive_group()
    shell_group.add_argument(
        "--cmd", action="store_true", help="Run the command through cmd.exe /c"
    )
    shell_group.add_argument(
        "--powershell",
        action="store_true",
        help="Run the command with powershell -Command",
    )
    parser.add_argument(
        "--timeout", type=int, default=60, help="Max execution time in seconds"
    )
    parser.add_argument(
        "--json", action="store_true", help="Output result in JSON format"
    )
    parser.add_argument(
        "command", help="Path to the command to execute inside the guest VM"
    )
    parser.add_argument(
        "args", nargs=argparse.REMAINDER, help="Arguments to pass to the command"
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    if args.cmd:
        command_path = "cmd.exe"
        command_args = ["/c", args.command] + args.args
    elif args.powershell:
        command_path = "powershell.exe"
        full_command = " ".join([args.command] + args.args)
        command_args = ["-Command", full_command]
    else:
        command_path = args.command
        command_args = args.args

        # Create a reusable socket
    unix_sock = create_socket()
    if not unix_sock:
        print("Failed to create socket.", file=sys.stderr)
        sys.exit(1)  # Exit if we can't connect to the socket

    result = execute_command(unix_sock, command_path, command_args, args.timeout)
    if result:
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(f"Exit Code: {result['exit_code']}")
            if result["stdout"]:
                print("STDOUT:\n", result["stdout"])
            if result["stderr"]:
                print("STDERR:\n", result["stderr"])

    # Close the socket once all commands are executed
    unix_sock.close()

    # Exit with the appropriate code based on command execution result
    sys.exit(result["exit_code"] if result else 2)
