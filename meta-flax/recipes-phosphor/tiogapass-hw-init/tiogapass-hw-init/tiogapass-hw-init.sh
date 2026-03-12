#!/bin/sh
# TiogaPass hardware initialization

# --- GPIO setup ---
# ASPEED AST2500 GPIO base (typically 0)
GPIO_BASE=$(cat /sys/class/gpio/gpiochip*/base 2>/dev/null | sort -n | head -n 1)
GPIO_BASE=${GPIO_BASE:-0}

gpio_out() {
    # gpio_out <gpio_number> <level: low|high>
    GPIO_NUM=$((GPIO_BASE + $1))
    echo "$GPIO_NUM" > /sys/class/gpio/export 2>/dev/null || true
    echo "$2" > /sys/class/gpio/gpio${GPIO_NUM}/direction 2>/dev/null || true
}

# FM_BMC_READY_N (GPIO S1 = base+145): active-low, drive LOW to signal BMC ready.
# Without this, host BIOS polls for BMC ready at multiple POST checkpoints and
# waits for timeout each time, causing progressive host boot slowdown.
gpio_out 145 low

# FP_PECI_MUX (GPIO AA4 = 212): active-low, drive HIGH to route PECI to BMC
# Without this, PECI bus is not accessible to the BMC (no CPU temperature).
gpio_out 212 high

# --- LPC port 80h redirect ---
# The kernel lpc_snoop driver handles /dev/aspeed-lpc-snoop0 (software
# post code reading), but the physical debug card 7-segment display
# needs these additional register writes (from meta-megarac U-Boot patch).

# Ensure /dev/mem is available
if [ ! -c /dev/mem ]; then
    mknod /dev/mem c 1 1
    chmod 600 /dev/mem
fi

# --- Clear PMBus faults on CPU voltage regulators (I2C bus 5) ---
# The Infineon PXE1610 VRs assert SMBALERT# after CPU power-on, causing
# a continuous ASPEED I2C IRQ storm (bit 12 = SMBUS_ALERT in interrupt
# status register). PMBus CLEAR_FAULTS command (0x03) de-asserts SMBALERT#.
for addr in 0x48 0x4a 0x50 0x52 0x58 0x5a 0x68 0x70 0x72; do
    i2cset -y 5 $addr 0x03 2>/dev/null || true
done

# Port 80h redirect: assign LPC as command source
devmem 0x1e780068 32 0x01000000
devmem 0x1e78006C 32 0x00000000

# Enable snoop at port 0x80 and enable redirect to debug card UART
# Bits 31:30 = redirect enable, bits 26:24 = 7 (UART redirect target)
devmem 0x1e789090 32 0x80
devmem 0x1e789080 32 0xC7000001
