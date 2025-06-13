// SPDX-License-Identifier: GPL-2.0-or-later
/* Reference from linux/drivers/i2c/i2c-core-smbus.c */

#include "pec.h"

#define POLY    (0x1070U << 3)
static uint8_t crc8(uint16_t data)
{
    int i;

    for (i = 0; i < 8; i++) {
        if (data & 0x8000)
            data = data ^ POLY;
        data = data << 1;
    }
    return (uint8_t)(data >> 8);
}

/**
 * calc_pec - Incremental CRC8 over the given input data array
 * @crc: previous return crc8 value
 * @p: pointer to data buffer.
 * @count: number of bytes in data buffer.
 *
 * Incremental CRC8 over count bytes in the array pointed to by p
 */
uint8_t calc_pec(uint8_t crc, uint8_t *p, size_t count)
{
    size_t i;

    for (i = 0; i < count; i++)
        crc = crc8((crc ^ p[i]) << 8);
    return crc;
}
