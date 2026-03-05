import subprocess
import sys

from test_dls_tiled import __version__


def test_cli_version():
    cmd = [sys.executable, "-m", "test_dls_tiled", "--version"]
    assert subprocess.check_output(cmd).decode().strip() == __version__
