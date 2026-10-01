#!/usr/bin/python3
"""Pure current-product plist contract; no signing, package, or deployment authority.

Accept XML and binary plists through the public plistlib dict_type seam, rejecting
duplicate keys before dictionary conversion. The only admitted value is the exact
typed current Beluga driver dictionary. Run with fixed Python -I -S -B; downstream
release closure must independently pin this module and the verifier that uses it.
"""

import os
import plistlib
import stat
import sys

MAX_BYTES = 65536
SUCCESS_MARKER = "VERIFIED_CURRENT_BELUGA_DRIVER_PLIST"


class Refusal(RuntimeError):
    pass


class _UniqueDict(dict):
    def __setitem__(self, key, value):
        if key in self:
            raise Refusal("duplicate plist key (contents redacted)") from None
        super().__setitem__(key, value)


def _expected():
    return {
        "CFBundleDevelopmentRegion": "English",
        "CFBundleExecutable": "OpensteamerVirtualMicrophone",
        "CFBundleIdentifier": "com.elamin.opensteamer.VirtualMicrophoneDriver",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "Beluga Virtual Microphone",
        "CFBundlePackageType": "BNDL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleSignature": "????",
        "CFBundleVersion": "1",
        "CFPlugInFactories": {
            "81CE9D28-D187-499B-84EE-F6AC6159C800":
                "OpensteamerVirtualMicrophone_Create",
        },
        "CFPlugInTypes": {
            "443ABAB8-E7B3-491A-B985-BEB9187030DB": [
                "81CE9D28-D187-499B-84EE-F6AC6159C800",
            ],
        },
        "LSMinimumSystemVersion": "14.0",
    }


def _exact_shape(actual, expected, depth=0):
    # Traverse only the bounded expected shape, never an untrusted cyclic graph.
    if depth > 3:
        return False
    if type(expected) is dict:
        return (type(actual) is _UniqueDict and actual.keys() == expected.keys()
                and all(_exact_shape(actual[key], value, depth + 1)
                        for key, value in expected.items()))
    if type(expected) is list:
        return (type(actual) is list and len(actual) == len(expected)
                and all(_exact_shape(left, right, depth + 1)
                        for left, right in zip(actual, expected)))
    return type(actual) is str and actual == expected


def validate_bytes(payload):
    """Return True only for exact current-product XML/binary plist bytes."""
    if type(payload) is not bytes:
        raise Refusal("plist input must be bytes") from None
    if not payload or len(payload) > MAX_BYTES:
        raise Refusal("plist byte bound exceeded or input empty") from None
    try:
        actual = plistlib.loads(payload, dict_type=_UniqueDict)
    except Refusal:
        raise
    except Exception:
        raise Refusal("malformed plist (contents redacted)") from None
    if not _exact_shape(actual, _expected()):
        raise Refusal("current Beluga driver plist contract is not exact") from None
    return True


def _identity(value):
    return (value.st_dev, value.st_ino, value.st_uid, value.st_gid,
            value.st_mode, value.st_nlink, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns)


def verify_file(path):
    """Read one canonical regular plist without conversion or writes."""
    try:
        if not os.path.isabs(path) or os.path.realpath(path) != path:
            raise Refusal("plist path must be absolute and canonical")
        before = os.lstat(path)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise Refusal("plist must be a non-symlink single-link regular file")
        if not 0 < before.st_size <= MAX_BYTES:
            raise Refusal("plist byte bound exceeded or input empty")
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as stream:
            if _identity(os.fstat(stream.fileno())) != _identity(before):
                raise Refusal("plist changed before read")
            payload = stream.read(MAX_BYTES + 1)
            validate_bytes(payload)
            if _identity(os.fstat(stream.fileno())) != _identity(before):
                raise Refusal("plist changed during read")
        if os.path.realpath(path) != path or _identity(os.lstat(path)) != _identity(before):
            raise Refusal("plist changed after read")
    except Refusal:
        raise
    except Exception:
        raise Refusal("plist file unavailable (details redacted)") from None
    return True


def _self_test():
    import tempfile
    import unittest

    formats = (plistlib.FMT_XML, plistlib.FMT_BINARY)

    class DuplicateItems(dict):
        def items(self):
            values = list(super().items())
            return values + values[:1]

    class ContractTests(unittest.TestCase):
        def refuses(self, payload, message=None):
            with self.assertRaises(Refusal) as raised:
                validate_bytes(payload)
            if message:
                self.assertEqual(str(raised.exception), message)
            return raised.exception

        def test_exact_xml_and_binary(self):
            for fmt in formats:
                with self.subTest(fmt=fmt):
                    self.assertTrue(validate_bytes(plistlib.dumps(_expected(), fmt=fmt)))

        def test_each_top_level_value_and_missing_key(self):
            for key in _expected():
                for fmt in formats:
                    with self.subTest(key=key, fmt=fmt):
                        changed = _expected()
                        changed[key] = "wrong"
                        self.refuses(plistlib.dumps(changed, fmt=fmt))
                        missing = _expected()
                        del missing[key]
                        self.refuses(plistlib.dumps(missing, fmt=fmt))

        def test_old_name_casing_whitespace_and_empty(self):
            for name in ("opensteamer Virtual Microphone", "beluga Virtual Microphone",
                         "Beluga Virtual Microphone ", "", "Beluga Virtual Microphone\n"):
                for fmt in formats:
                    changed = _expected()
                    changed["CFBundleName"] = name
                    self.refuses(plistlib.dumps(changed, fmt=fmt))

        def test_extra_and_nested_fields(self):
            for fmt in formats:
                extra = _expected()
                extra["Unexpected"] = "extra"
                self.refuses(plistlib.dumps(extra, fmt=fmt))
                for key in ("CFPlugInFactories", "CFPlugInTypes"):
                    changed = _expected()
                    changed[key]["Unexpected"] = "extra"
                    self.refuses(plistlib.dumps(changed, fmt=fmt))
                    changed = _expected()
                    changed[key] = {}
                    self.refuses(plistlib.dumps(changed, fmt=fmt))

        def test_factory_type_uuid_and_array_contracts(self):
            for fmt in formats:
                for key in ("CFPlugInFactories", "CFPlugInTypes"):
                    changed = _expected()
                    original = next(iter(changed[key]))
                    changed[key][original.lower()] = changed[key].pop(original)
                    self.refuses(plistlib.dumps(changed, fmt=fmt))
                changed = _expected()
                changed["CFPlugInFactories"][next(iter(changed["CFPlugInFactories"]))] += "Wrong"
                self.refuses(plistlib.dumps(changed, fmt=fmt))
                for value in ([], ["wrong"], ["81CE9D28-D187-499B-84EE-F6AC6159C800"] * 2):
                    changed = _expected()
                    changed["CFPlugInTypes"][next(iter(changed["CFPlugInTypes"]))] = value
                    self.refuses(plistlib.dumps(changed, fmt=fmt))

        def test_exact_types(self):
            for fmt in formats:
                for value in (True, False, 1, 1.0, b"Beluga Virtual Microphone", [], {}):
                    changed = _expected()
                    changed["CFBundleName"] = value
                    self.refuses(plistlib.dumps(changed, fmt=fmt))
                changed = _expected()
                changed["CFPlugInTypes"][next(iter(changed["CFPlugInTypes"]))] = \
                    "81CE9D28-D187-499B-84EE-F6AC6159C800"
                self.refuses(plistlib.dumps(changed, fmt=fmt))

        def test_raw_duplicate_root_and_nested_xml_and_binary(self):
            for fmt in formats:
                for nested in (False, True):
                    changed = _expected()
                    if nested:
                        changed["CFPlugInFactories"] = DuplicateItems(changed["CFPlugInFactories"])
                    else:
                        changed = DuplicateItems(changed)
                    raw = plistlib.dumps(changed, fmt=fmt, sort_keys=False)
                    # Same-value duplicates would pass after a lossy dict conversion.
                    self.assertEqual(plistlib.loads(raw), _expected())
                    self.refuses(raw, "duplicate plist key (contents redacted)")

        def test_malformed_xml_and_binary_are_redacted(self):
            for raw in (b"secret-credential-not-a-plist", b"<plist><dict><key>secret-value</key></dict>",
                        b"bplist00", b"bplist00" + bytes(32), b"\xff\xfeBAD", b""):
                error = self.refuses(raw)
                self.assertNotIn("secret", str(error))
                self.assertIsNone(error.__cause__)
                self.assertTrue(error.__suppress_context__)
            for fmt in formats:
                raw = plistlib.dumps(_expected(), fmt=fmt)
                self.refuses(raw[:len(raw) // 2])

        def test_byte_bound_is_independent_of_valid_schema(self):
            raw = plistlib.dumps(_expected(), fmt=plistlib.FMT_XML)
            oversized = raw + b" " * (MAX_BYTES + 1 - len(raw))
            self.assertEqual(plistlib.loads(oversized), _expected())
            self.refuses(oversized, "plist byte bound exceeded or input empty")

        def test_recursive_and_deep_containers(self):
            changed = _expected()
            changed["CFPlugInTypes"] = changed
            raw = plistlib.dumps(changed, fmt=plistlib.FMT_BINARY)
            parsed = plistlib.loads(raw)
            self.assertIs(parsed["CFPlugInTypes"], parsed)
            self.refuses(raw, "current Beluga driver plist contract is not exact")
            raw = (b'<?xml version="1.0"?><plist version="1.0">' + b"<array>" * 2000
                   + b"<string>x</string>" + b"</array>" * 2000 + b"</plist>")
            self.assertLess(len(raw), MAX_BYTES)
            self.refuses(raw)

        def test_nonbytes_and_wrong_roots(self):
            for value in (None, "plist", bytearray(b"plist"), {}, []):
                self.refuses(value, "plist input must be bytes")
            for fmt in formats:
                for value in ([], "Beluga Virtual Microphone", 1, True):
                    self.refuses(plistlib.dumps(value, fmt=fmt))

        def test_file_path_contract(self):
            with tempfile.TemporaryDirectory(prefix="beluga-plist-contract-") as scratch:
                scratch = os.path.realpath(scratch)
                path = os.path.join(scratch, "Info.plist")
                with open(path, "wb") as stream:
                    stream.write(plistlib.dumps(_expected()))
                self.assertTrue(verify_file(path))
                for refused in ("Info.plist", path + "/../Info.plist", path + ".missing"):
                    with self.assertRaises(Refusal):
                        verify_file(refused)
                link = os.path.join(scratch, "link")
                os.symlink(path, link)
                with self.assertRaises(Refusal):
                    verify_file(link)
                hardlink = os.path.join(scratch, "hardlink")
                os.link(path, hardlink)
                with self.assertRaises(Refusal):
                    verify_file(path)

    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful() or result.testsRun != 12 or result.skipped:
        return 1
    print("SELF_TEST_OK current-beluga-driver-plist-contract 12 tests")
    return 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return _self_test()
    if len(sys.argv) != 2 or not os.path.isabs(sys.argv[1]):
        print("usage: beluga-production-driver-plist.py absolute-Info.plist", file=sys.stderr)
        return 64
    try:
        verify_file(sys.argv[1])
    except Refusal as error:
        print(str(error), file=sys.stderr)
        return 65
    print(SUCCESS_MARKER)
    return 0


if __name__ == "__main__":
    sys.exit(main())
