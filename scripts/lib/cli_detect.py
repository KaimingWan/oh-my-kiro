"""CLI auto-detection for ralph loop."""
import os
import shutil
import subprocess
import sys


def detect_cli() -> list[str]:
    """Detect available CLI: env override > claude > kiro-cli."""
    env_cmd = os.environ.get('RALPH_KIRO_CMD', '').strip()
    if env_cmd:
        return env_cmd.split()

    if shutil.which('claude'):
        # Verify claude is authenticated
        try:
            r = subprocess.run(
                ['claude', '-p', 'ping', '--output-format', 'text'],
                capture_output=True, text=True, timeout=10,
            )
            if r.returncode == 0:
                return [
                    'claude', '-p',
                    '--allowedTools', 'Bash,Read,Write,Edit,Task,WebSearch,WebFetch',
                    '--output-format', 'stream-json', '--verbose',
                    '--no-session-persistence',
                ]
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    if shutil.which('kiro-cli'):
        return ['kiro-cli', 'chat', '--no-interactive', '--trust-all-tools', '--agent', 'pilot']

    print('❌ Neither claude nor kiro-cli found in PATH.', file=sys.stderr)
    sys.exit(1)