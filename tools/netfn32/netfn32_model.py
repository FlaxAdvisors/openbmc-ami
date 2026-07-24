"""Pure-logic model of the NetFn 0x32 host-interface bootstrap handler.

This is the single source of truth for the response bytes; the C++ ipmid provider
(meta-flax) is a transliteration of respond(). Keeping the logic here lets us
validate byte-exactness offline (test_handler_responses.py) with no BIOS in the loop.

Ground truth: the live OEM KCS capture, decoded in
docs/redfish-inventory-netfn32-protocol.md. The NetFn 0x32 conversation is a small
bootstrap handshake; the bulk inventory rides the Redfish Host Interface over usb0,
not KCS (so there is no data-carrying command to handle here).

respond(cmd, req) -> (completion_code, response_data_bytes)
  cmd : IPMI command byte (NetFn is 0x32; dispatch is by cmd)
  req : request data bytes (everything after netfn/lun + cmd)
"""
import secrets
import string

_PW_ALPHABET = string.ascii_letters + string.digits

# KCS cmd 0x5d selector -> host-interface role name. The role name length prefixes
# the account label; a freshly generated password (length-prefixed) follows.
_HI_ROLE = {
    0x01: b"HostAutoFW",   # firmware (BIOS/UEFI) host-interface account
    0x02: b"HostAutoOS",   # OS host-interface account
}

CC_OK = 0x00
CC_INVALID_CMD = 0xC1
CC_SMEMBERS_EMPTY = 0xCC   # OEM returns this for an empty redis set; BIOS proceeds


def _generate_password(length: int = 12) -> bytes:
    return "".join(secrets.choice(_PW_ALPHABET) for _ in range(length)).encode()


def respond(cmd: int, req: bytes) -> tuple:
    if cmd == 0x2A:
        # Redis passthrough. The only probe the BIOS issues is
        # `smembers Redfish:oem:MappingOut:DeviceList`; that set is empty on our
        # BMC, so we return the empty-set completion code and no data.
        return (CC_SMEMBERS_EMPTY, b"")

    if cmd == 0x3D:
        # Get inventory device status. Observed req = Param/Set/BlockSelector
        # (01 00 07) -> three 0x07 status bytes. Return one status byte per unit
        # implied by the block selector (default 3, matching the capture).
        block_selector = req[2] if len(req) >= 3 else 0x07
        count = 3 if block_selector == 0x07 else block_selector
        return (CC_OK, bytes([0x07] * count))

    if cmd == 0x5D:
        selector = req[0] if req else 0x00
        role = _HI_ROLE.get(selector)
        if role is not None:
            pw = _generate_password(12)
            return (CC_OK, bytes([len(role)]) + role + bytes([len(pw)]) + pw)
        # other selectors (e.g. 0x04) are bare acks
        return (CC_OK, b"")

    if cmd == 0xAB:
        # version/capability probe -> cc 0x00 + 0x01
        return (CC_OK, bytes([0x01]))

    if cmd == 0xAA:
        # small ack
        return (CC_OK, b"")

    # Never return a blanket empty-success for unobserved commands: that misled the
    # BIOS into a cmd 0x3d retry storm in an earlier experiment. Reject explicitly.
    return (CC_INVALID_CMD, b"")
