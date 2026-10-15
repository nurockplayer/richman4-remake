"""Offline tests of platform template selection, integrity, and permissions."""
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile

SPEC = importlib.util.spec_from_file_location("installer", Path(__file__).with_name("install_templates.py"))
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class TemplateInstallTests(unittest.TestCase):
    def invoke(self, platform, checksum_ok=True):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        download = root / ".local/downloads/export_templates.tpz"
        download.parent.mkdir(parents=True)
        with zipfile.ZipFile(download, "w") as archive:
            archive.writestr("templates/linux_debug.x86_64", b"debug fixture")
            archive.writestr("templates/linux_release.x86_64", b"release fixture")
            archive.writestr("templates/macos.zip", b"macos fixture")
        digest = hashlib.sha512(download.read_bytes()).hexdigest() if checksum_ok else "incorrect"
        target = root / "templates"
        with mock.patch.object(installer, "__file__", str(root / "tools/install_templates.py")), \
             mock.patch.object(installer, "SHA512", digest), \
             mock.patch.object(installer.sys, "argv", ["install_templates.py", "--platform", platform, "--template-dir", str(target)]), \
             mock.patch.object(installer.urllib.request, "urlopen", side_effect=AssertionError("No network expected")), \
             contextlib.redirect_stdout(io.StringIO()):
            installer.main()
        return target

    def test_linux_extracts_only_linux_templates_and_sets_executable(self):
        target = self.invoke("linux")
        self.assertEqual({p.name for p in target.iterdir()}, {"linux_debug.x86_64", "linux_release.x86_64"})
        self.assertEqual((target / "linux_release.x86_64").read_bytes(), b"release fixture")
        self.assertTrue(os.access(target / "linux_release.x86_64", os.X_OK))

    def test_macos_template_remains_supported(self):
        target = self.invoke("macos")
        self.assertEqual([p.name for p in target.iterdir()], ["macos.zip"])
        self.assertEqual((target / "macos.zip").read_bytes(), b"macos fixture")

    def test_checksum_failure_prevents_installation(self):
        with self.assertRaisesRegex(SystemExit, "checksum mismatch"):
            self.invoke("linux", checksum_ok=False)


if __name__ == "__main__":
    unittest.main()
