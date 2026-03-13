"""Utility to run SSH commands on the droplet via paramiko."""
import os, sys, paramiko

def _env(key, default=None):
    v = os.environ.get(key, default)
    if v is None:
        print(f"ERROR: set {key} env-var first", file=sys.stderr); sys.exit(1)
    return v

HOST     = _env("DEPLOY_HOST")
USER     = _env("DEPLOY_USER", "root")
PASSWORD = _env("DEPLOY_PASSWORD")

def run(cmd: str) -> None:
    ssh = paramiko.SSHClient()
    ssh.load_system_host_keys()
    ssh.set_missing_host_key_policy(paramiko.WarningPolicy())
    try:
        ssh.connect(HOST, username=USER, password=PASSWORD, timeout=15)
        stdin, stdout, stderr = ssh.exec_command(cmd, timeout=300)
        out = stdout.read().decode()
        err = stderr.read().decode()
        if out:
            print(out)
        if err:
            print(err, file=sys.stderr)
        ssh.close()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    cmd = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "hostname"
    run(cmd)
