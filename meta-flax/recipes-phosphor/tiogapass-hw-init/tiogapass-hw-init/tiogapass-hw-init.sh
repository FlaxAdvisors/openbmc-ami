#!/bin/sh
# TiogaPass hardware initialization
# Sets up LPC port 80h redirect for debug card 7-segment display.
# The kernel lpc_snoop driver handles /dev/aspeed-lpc-snoop0 (software
# post code reading), but the physical debug card redirect needs these
# additional register writes (from meta-megarac U-Boot patch).

# Ensure /dev/mem is available
if [ ! -c /dev/mem ]; then
    mknod /dev/mem c 1 1
    chmod 600 /dev/mem
fi

# Port 80h redirect: assign LPC as command source
devmem 0x1e780068 32 0x01000000
devmem 0x1e78006C 32 0x00000000

# Enable snoop at port 0x80 and enable redirect to debug card UART
# Bits 31:30 = redirect enable, bits 26:24 = 7 (UART redirect target)
devmem 0x1e789090 32 0x80
devmem 0x1e789080 32 0xC7000001
