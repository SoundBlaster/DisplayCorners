import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent


class HookInstallationTests(unittest.TestCase):
    def test_install_idempotently_and_remove_preserves_other_hooks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, data = root / "codex", root / "display corners"
            home.mkdir()
            original = {"description": "existing", "hooks": {
                "PostToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo kept"}]}, {"hooks": []}],
                "AnotherEvent": [{"hooks": [{"type": "command", "command": "echo other"}]}]}}
            path = home / "hooks.json"
            path.write_text(json.dumps(original))

            def run(action):
                return subprocess.run([sys.executable, str(HERE / "install.py"), action, "--home", str(home), "--data", str(data)],
                                      text=True, capture_output=True, check=True).stdout.strip()

            self.assertEqual(run("status"), "not_installed")
            self.assertEqual(run("install"), "installed")
            installed = json.loads(path.read_text())
            self.assertEqual(run("install"), "installed")
            self.assertEqual(json.loads(path.read_text()), installed)
            self.assertTrue((data / "hook.py").is_file())
            self.assertEqual(run("remove"), "not_installed")
            self.assertEqual(json.loads(path.read_text()), original)

    def test_invalid_existing_configuration_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "hooks.json"
            path.write_text("invalid json")
            result = subprocess.run([sys.executable, str(HERE / "install.py"), "install", "--home", str(root),
                                     "--data", str(root / "data")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_text(), "invalid json")

    def test_existing_symlink_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            target = root / "shared.json"
            original = {"hooks": {"PostToolUse": [{"hooks": [{"type": "command", "command": "echo keep"}]}]}}
            target.write_text(json.dumps(original))
            (home / "hooks.json").symlink_to(target)
            args = [sys.executable, str(HERE / "install.py"), "install", "--home", str(home), "--data", str(root / "data")]
            subprocess.run(args, capture_output=True, text=True, check=True)
            self.assertTrue((home / "hooks.json").is_symlink())
            self.assertEqual(json.loads(target.read_text())["hooks"]["PostToolUse"][0], original["hooks"]["PostToolUse"][0])


if __name__ == "__main__":
    unittest.main()
