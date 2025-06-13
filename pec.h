#ifndef _PEC_H
#define _PEC_H

#include <stddef.h>
#include <stdint.h>

uint8_t calc_pec(uint8_t crc, uint8_t *p, size_t count);

#endif
