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
        # Try Hex decoding first
        return bytes.fromhex(data).decode("utf-8", errors="ignore")
    except ValueError:
        pass

    try:
        # If hex fails, try Base64 decoding
        return base64.b64decode(data).decode("utf-8", errors="ignore")
    except ValueError:
        pass

    # If all decoding fails, return raw
    return data


def execute_command(sock, command_path, command_args):
    """Execute a command inside the guest VM with specified path and arguments."""
    exec_request = {
        "execute": "guest-exec",
        "arguments": {
            "path": command_path,
            "arg": command_args,
            "capture-output": True,  # Capture stdout and stderr
        },
    }
    response = send_qga_command(sock, exec_request)

    if response is None:
        return None

    if "return" not in response or "pid" not in response["return"]:
        print("Error: Failed to start execution:", response, file=sys.stderr)
        return None

    pid = response["return"]["pid"]
    print(f"Command started with PID {pid}")

    # Step 2: Wait for completion
    while True:
        status_request = {"execute": "guest-exec-status", "arguments": {"pid": pid}}
        status_response = send_qga_command(sock, status_request)

        if status_response is None:
            continue

        if "return" in status_response:
            status = status_response["return"]
            if status.get("exited", False):
                break  # Command finished
        time.sleep(0.2)  # Wait before checking again

    # Step 3: Get exit code and output
    exit_code = status.get("exitcode", -1)
    stdout_data = decode_output(status.get("out-data", ""))
    stderr_data = decode_output(status.get("err-data", ""))

    return {"exit_code": exit_code, "stdout": stdout_data, "stderr": stderr_data}


def create_socket():
    """Create and return a reusable socket connection to the QEMU Guest Agent."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(30)  # 30 seconds timeout
    try:
        sock.connect(QGA_SOCKET)
        return sock
    except Exception as e:
        print(f"Error creating socket: {e}", file=sys.stderr)
        return None


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Send commands to QEMU Guest Agent.")
    parser.add_argument(
        "command", help="Path to the command to execute inside the guest VM"
    )
    parser.add_argument(
        "args", nargs=argparse.REMAINDER, help="Arguments to pass to the command"
    )
    return parser.parse_args()


if __name__ == "__main__":
    # Parse command-line arguments
    args = parse_args()

    # Create a reusable socket
    unix_sock = create_socket()
    if not unix_sock:
        print("Failed to create socket.", file=sys.stderr)
        sys.exit(1)  # Exit if we can't connect to the socket

    # Execute the command
    result = execute_command(unix_sock, args.command, args.args)
    if result:
        print(f"Exit Code: {result['exit_code']}")
        if result["stdout"]:
            print("STDOUT:\n", result["stdout"])
        if result["stderr"]:
            print("STDERR:\n", result["stderr"])

    # Close the socket once all commands are executed
    unix_sock.close()

    # Exit with the appropriate code based on command execution result
    sys.exit(result["exit_code"] if result else 2)
