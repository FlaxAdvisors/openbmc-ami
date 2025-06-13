/* SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later */

#ifndef _LIBMCTP_ASTI3C_H
#define _LIBMCTP_ASTI3C_H

#ifdef __cplusplus
extern "C" {
#endif

#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#include "libmctp.h"

/*
 * I3C HDR transmit data by words(16 bits), let packet size to be word aligned.
 * 4-byte MCTP_HEADER + 65-byte MCTP payload + 1-byte PEC
 */
#define MCTP_BTU_I3C 65
#define MCTP_I3C_PKT_SIZE 70
#define MCTP_HEADER_SIZE 4

struct mctp_binding_npcmi3c {
	struct mctp_binding binding;
	int fd;
};

struct mctp_binding_npcmi3c *mctp_npcmi3c_init(void);
void mctp_npcmi3c_destroy(struct mctp_binding_npcmi3c *npcmi3c);
int mctp_npcmi3c_open_path(struct mctp_binding_npcmi3c *npcmi3c,
			   const char *device);
struct mctp_binding *mctp_binding_npcmi3c_core(struct mctp_binding_npcmi3c *b);
int mctp_npcmi3c_poll(struct mctp_binding_npcmi3c *npcmi3c, int timeout);
int mctp_npcmi3c_rx(struct mctp_binding_npcmi3c *npcmi3c);

#ifdef __cplusplus
}
#endif

#endif /* _LIBMCTP_NPCMI3C_H */
