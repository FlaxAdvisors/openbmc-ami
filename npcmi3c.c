/* SPDX-License-Identifier: Apache-2.0 */
#include <errno.h>
#include <unistd.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "libmctp-log.h"
#include "libmctp-alloc.h"
#include "libmctp-npcmi3c.h"
#include "container_of.h"
#include "pec.h"

#undef pr_fmt
#define pr_fmt(x) "npcmi3c: " x

#define binding_to_npcmi3c(b)                                                   \
    container_of(b, struct mctp_binding_npcmi3c, binding)

int mctp_npcmi3c_poll(struct mctp_binding_npcmi3c *npcmi3c, int timeout)
{
    struct pollfd fds[1];
    int rc;

    fds[0].fd = npcmi3c->fd;
    fds[0].events = POLLIN;

    rc = poll(fds, 1, timeout);

    if (rc > 0)
        return fds[0].revents;

    if (rc < 0) {
        mctp_prwarn("Poll returned error status (errno=%d)", errno);

        return -1;
    }

    return 0;
}

static int mctp_npcmi3c_tx(struct mctp_binding *binding, struct mctp_pktbuf *pkt)
{
    struct mctp_binding_npcmi3c *npcmi3c = binding_to_npcmi3c(binding);
    ssize_t write_len, len;

    if (npcmi3c->fd < 0) {
        mctp_prerr("Invalid file descriptor passed");
        return -1;
    }

    len = mctp_pktbuf_size(pkt);

    mctp_prdebug("Transmitting packet, len: %zu", len);

    /* Calculate PEC */
    pkt->data[len] = calc_pec(0, pkt->data, len);
    mctp_prdebug("pec=0x%x\n", pkt->data[len]);
    len++;

    write_len = write(npcmi3c->fd, pkt->data, len);
    if (write_len != len) {
        mctp_prerr("TX error");
        return -1;
    }
    return 0;
}

int mctp_npcmi3c_rx(struct mctp_binding_npcmi3c *npcmi3c)
{
    uint8_t data[MCTP_I3C_PKT_SIZE];
    struct mctp_pktbuf *pkt;
    ssize_t read_len;
    uint8_t pec, cal_pec;
    int rc;

    if (npcmi3c->fd < 0) {
        mctp_prerr("Invalid file descriptor");
        return -1;
    }

    read_len = read(npcmi3c->fd, &data, sizeof(data));
    if (read_len < 0) {
        mctp_prerr("Reading RX data failed (errno = %d)", errno);
        return -1;
    }

    if (read_len < 2) {
        mctp_prerr("short RX data: %zd", read_len);
        return -1;
    }

    /* PEC byte is handled by libmctp-npcmi3c */
    if ((read_len > (ssize_t)(npcmi3c->binding.pkt_size + 1)) ||
        (read_len < (MCTP_HEADER_SIZE + 1))) {
        mctp_prerr("Incorrect packet size: %zd", read_len);
        return -1;
    }

    /* Verify PEC */
    pec = data[read_len - 1];
    read_len--;
    cal_pec = calc_pec(0, data, read_len);
    if (pec != cal_pec) {
        mctp_prerr("PEC error: 0x%x 0x%x", pec, cal_pec);
        return -1;
    }

    pkt = mctp_pktbuf_alloc(&npcmi3c->binding, 0);
    if (!pkt) {
        mctp_prerr("pktbuf allocation failed");
        return -1;
    }

    rc = mctp_pktbuf_push(pkt, data, read_len);

    if (rc) {
        mctp_prerr("Cannot push to pktbuf");
        mctp_pktbuf_free(pkt);
        return -1;
    }

    mctp_bus_rx(&npcmi3c->binding, pkt);

    return 0;
}

int mctp_npcmi3c_open_path(struct mctp_binding_npcmi3c *npcmi3c,
              const char *device)
{
    npcmi3c->fd = open(device, O_RDWR);
    if (npcmi3c->fd < 0) {
        mctp_prerr("can't open device %s: error %d", device, errno);
        return -1;
    }

    return 0;
}

static int mctp_npcmi3c_core_start(struct mctp_binding *binding)
{
    mctp_binding_set_tx_enabled(binding, true);
    return 0;
}

struct mctp_binding *mctp_binding_npcmi3c_core(struct mctp_binding_npcmi3c *b)
{
    return &b->binding;
}

struct mctp_binding_npcmi3c *mctp_npcmi3c_init(void)
{
    struct mctp_binding_npcmi3c *npcmi3c;

    npcmi3c = __mctp_alloc(sizeof(*npcmi3c));
    if (!npcmi3c)
        return NULL;

    memset(npcmi3c, 0, sizeof(*npcmi3c));

    npcmi3c->binding.name = "npcmi3c";
    npcmi3c->binding.version = 1;
    npcmi3c->binding.pkt_size = MCTP_PACKET_SIZE(MCTP_BTU_I3C);
    npcmi3c->binding.start = mctp_npcmi3c_core_start;
    npcmi3c->binding.tx = mctp_npcmi3c_tx;

    return npcmi3c;
}

void mctp_npcmi3c_destroy(struct mctp_binding_npcmi3c *npcmi3c)
{
    if (npcmi3c->fd > 0)
        close(npcmi3c->fd);
    __mctp_free(npcmi3c);
}
