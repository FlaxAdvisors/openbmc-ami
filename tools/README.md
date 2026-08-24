# Flax BMC development tools

Host-side tooling for the Flax TiogaPass OpenBMC firmware.  These are developer
utilities — none of them ship in the BMC image.  They pair with the firmware
repo, `openbmc-ami`, which several of them expect to find as a sibling checkout:

    <parent>/
      openbmc-ami/      # firmware (meta-flax layer, recipes, patches)
      <this repo>/      # these tools

| Directory | What it is |
|-----------|------------|
| `hi-inventory/` | Native host build + 89-check test for the `flax-hi-inventory` mapping layer, replayed against captured BIOS payloads in `samples/collections`.  Sources under test live in `openbmc-ami`; override the location with `make FLAX_REPO=/path/to/openbmc-ami test`. |
| `netfn32/` | Offline byte-exact model of the KCS NetFn 0x32 host-interface bootstrap handler, plus its pytest suite (`python3 -m pytest`). |
| `hi-cert/` | `mint-hi-cert.sh` — mints the TLS certificate the BIOS requires for the Redfish host interface. |
| `oem-capture/` | `capture-phase-a.sh` / `capture-phase-b.sh` — scripted capture of the stock AMI firmware's behaviour around an OEM chip swap, used to reverse-engineer the inventory protocol. |

## Tests

    make -C hi-inventory test          # 89 mapping checks
    cd netfn32 && python3 -m pytest    # 8 handler checks
