"""Offline byte-exact tests for the NetFn 0x32 bootstrap handler logic.

Expected responses are ground-truthed from the live OEM KCS capture
(/vagrant/oem-reference/protocol-reverse/live-2026-07-23/kcs-bytes-fullpush.txt),
decoded in docs/redfish-inventory-netfn32-protocol.md. The C++ ipmid handler is a
transliteration of netfn32_model.respond(); this test validates the logic offline
so we never need the BIOS in the loop to check response bytes.
"""
from netfn32_model import respond


def test_0x2a_smembers_empty_devicelist_returns_cc():
    # BIOS probe: redis `smembers Redfish:oem:MappingOut:DeviceList`; the set is
    # empty on our BMC -> completion code 0xCC, no data. BIOS tolerates and proceeds.
    req = bytes([0x01, 0x00]) + b"smembers Redfish:oem:MappingOut:DeviceList"
    assert respond(0x2a, req) == (0xCC, b"")


def test_0x3d_device_status_block7():
    # req = ParamSelector, SetSelector, BlockSelector(=0x07); resp cc=0 + 3 status bytes.
    assert respond(0x3d, bytes([0x01, 0x00, 0x07])) == (0x00, bytes([0x07, 0x07, 0x07]))


def test_0x5d_fw_credential_structure():
    # req[0]=0x01 -> Host-Interface firmware credential:
    # cc=0 + [len]"HostAutoFW" + [len]<12-char generated password>.
    cc, data = respond(0x5d, bytes([0x01]))
    assert cc == 0x00
    assert data[0] == 0x0A and data[1:11] == b"HostAutoFW"
    assert data[11] == 0x0C and len(data[12:]) == 12
    assert data[12:].isalnum()


def test_0x5d_os_credential_role():
    cc, data = respond(0x5d, bytes([0x02]))
    assert cc == 0x00 and data[1:11] == b"HostAutoOS" and data[11] == 0x0C


def test_0x5d_selector4_is_bare_ack():
    assert respond(0x5d, bytes([0x04])) == (0x00, b"")


def test_0xab_version_returns_01():
    assert respond(0xAB, b"") == (0x00, bytes([0x01]))


def test_0xaa_ack():
    assert respond(0xAA, bytes([0x00])) == (0x00, b"")
    assert respond(0xAA, bytes([0x01])) == (0x00, b"")


def test_unknown_cmd_is_invalid_command():
    # anything we didn't observe -> 0xC1 (invalid command), never a blanket empty-success
    assert respond(0x99, b"") == (0xC1, b"")
