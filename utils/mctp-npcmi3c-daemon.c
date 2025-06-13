/* SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later */

#include "compiler.h"
#include "libmctp.h"
#include "libmctp-npcmi3c.h"

#include <assert.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/poll.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>

struct ctx {
    struct mctp *mctp;
};

static void echo_message(uint8_t eid, bool tag_owner __attribute__((unused)),
               uint8_t msg_tag __attribute__((unused)), void *data, void *msg, size_t len)
{
    struct ctx *ctx = data;
    ssize_t rc;

    rc = mctp_message_tx(ctx->mctp, eid, MCTP_MESSAGE_TO_SRC, 0, msg, len);
    if (rc < 0)
        warn("Write failed");
}

const char *sopts = "p:e:h";
static const struct option lopts[] = {
    {"dev_path",        required_argument,    NULL,    'p' },
    {"eid",            required_argument,    NULL,    'e' },
    {"help",        no_argument,        NULL,    'h' },
    {0, 0, 0, 0}
};
static void print_usage(const char *name)
{
    fprintf(stderr, "usage: %s options...\n", name);
    fprintf(stderr, "  options:\n");
    fprintf(stderr, "    -p --devpath      <path>          device path\n");
    fprintf(stderr, "    -e --eid          <eid>          my eid\n");
    fprintf(stderr, "    -h --help                        Output usage message and exit.\n");
}
int main(int argc, char **argv)
{
    struct mctp_binding_npcmi3c *npcmi3c;
    struct mctp *mctp;
    char *i3cdev_path = NULL;
    struct ctx *ctx, _ctx;
    int opt;
    int rc;
    int eid = 32;

    while ((opt = getopt_long(argc, argv,  sopts, lopts, NULL)) != EOF) {
        switch (opt) {
        case 'h':
            print_usage(argv[0]);
            exit(EXIT_SUCCESS);
        case 'p':
            i3cdev_path = optarg;
            break;
        case 'e':
            eid = atoi(optarg);
            break;
        default:
            print_usage(argv[0]);
            exit(EXIT_FAILURE);
        }
    }
    assert(i3cdev_path);

    mctp_set_log_stdio(MCTP_LOG_WARNING);

    mctp = mctp_init();
    assert(mctp);

    npcmi3c = mctp_npcmi3c_init();
    assert(npcmi3c);

    rc = mctp_npcmi3c_open_path(npcmi3c, i3cdev_path);
    assert(rc == 0);

    mctp_register_bus(mctp, mctp_binding_npcmi3c_core(npcmi3c), eid);

    ctx = &_ctx;
    ctx->mctp = mctp;
    mctp_set_rx_all(mctp, echo_message, ctx);

    for (;;) {
        rc = mctp_npcmi3c_poll(npcmi3c, -1);
        if (rc < 0) {
            break;
        }
        rc = mctp_npcmi3c_rx(npcmi3c);
        if (rc)
            break;
    }

    return EXIT_SUCCESS;
}
