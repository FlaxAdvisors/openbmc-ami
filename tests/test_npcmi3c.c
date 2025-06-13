#include <stdio.h>
#include <assert.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>

#include "libmctp-npcmi3c.h"
#include "libmctp-log.h"

#define i3c_tx_packet 0x00, 0x81, 0x04, 0x00

#define i3c_one_packet_btu_write_payload                                       \
    0x00, 0x81, 0x04, 0x00, 0x20, 0x09, 0xC8, 0x00, 0x81, 0x04, 0x00,      \
        0x01, 0x09, 0xC8, 0x00, 0x81, 0x04, 0x00, 0x01, 0x20, 0xC8,    \
        0x00, 0x81, 0x04, 0x00, 0x01, 0x20, 0x09, 0x00, 0x81, 0x04,    \
        0x00, 0x01, 0x20, 0x09, 0xC8, 0x81, 0x04, 0x00, 0x01, 0x20,    \
        0x09, 0xC8, 0x00, 0x04, 0x00, 0x01, 0x20, 0x09, 0xC8, 0x00,    \
        0x81, 0x04, 0x00, 0x01, 0x20, 0x09, 0xC8, 0x00, 0x81, 0x00,    \
        0x01, 0x20, 0x09, 0x09,

typedef enum testcase {
    i3c_packet_read = 0,
    i3c_packet_write,
    mctp_npcmi3c_daemon_test,
} testcase;

testcase test = mctp_npcmi3c_daemon_test;

static void test_rx_verify_payload_debug(uint8_t src __attribute__((unused)), 
                      bool tag_owner __attribute__((unused)), 
                      uint8_t msg_tag __attribute__((unused)),
                      void *ctx __attribute__((unused)), 
                      void *msg, size_t len)
{
    char *buf = (char *)msg;
    size_t i;

    mctp_prdebug("rx payload len: %#zx", len);
    for (i = 0; i < len; i++)
        printf("%02x ", buf[i]);
    printf("\n");
}

static void test_rx_verify_payload_daemon(uint8_t src __attribute__((unused)), 
                       bool tag_owner __attribute__((unused)), 
                       uint8_t msg_tag __attribute__((unused)),
                       void *ctx, void *msg, size_t len)
{
    uint8_t *expected_data = (uint8_t *)ctx;
    int rc;

    assert(MCTP_BTU_I3C == len);
    rc = memcmp(expected_data, msg, len);
    assert(rc == 0);
}

static void test_npcmi3c_tx_btu(struct mctp_binding_npcmi3c *npcmi3c __attribute__((unused)),
                struct mctp *mctp, uint8_t dst_eid)
{
    uint8_t test_payload[] = { i3c_one_packet_btu_write_payload };
    bool tag_owner = true;
    uint8_t tag = 0;
    int rc = 0;

    rc = mctp_message_tx(mctp, dst_eid, tag_owner, tag, test_payload, sizeof(test_payload));
    assert(rc == 0);
}

static void test_npcmi3c_rx(struct mctp_binding_npcmi3c *npcmi3c,
            struct mctp *mctp)
{
    mctp_npcmi3c_poll(npcmi3c, 100000);
    mctp_set_rx_all(mctp, test_rx_verify_payload_debug, NULL);
    mctp_npcmi3c_rx(npcmi3c);
}

static void test_npcmi3c_daemon(struct mctp_binding_npcmi3c *npcmi3c,
                struct mctp *mctp, uint8_t dst_eid)
{
    uint8_t test_payload[MCTP_BTU_I3C];
    bool tag_owner = true;
    uint8_t tag = 0;
    int rc = 0;
    size_t i;

    for (i = 0; i < MCTP_BTU_I3C; i++)
        test_payload[i] = (char)random();
    rc = mctp_message_tx(mctp, dst_eid, tag_owner, tag, test_payload, sizeof(test_payload));
    assert(rc == 0);

    mctp_npcmi3c_poll(npcmi3c, 100000);
    mctp_set_rx_all(mctp, test_rx_verify_payload_daemon, test_payload);
    mctp_npcmi3c_rx(npcmi3c);
}

const char *sopts = "p:e:d:t:l:h";
static const struct option lopts[] = {
    {"path",        required_argument,    NULL,    'p' },
    {"test",        required_argument,    NULL,    't' },
    {"eid",            required_argument,    NULL,    'e' },
    {"dst_eid",        required_argument,    NULL,    'd' },
    {"loop",        required_argument,    NULL,    'l' },
    {"help",        no_argument,        NULL,    'h' },
    {0, 0, 0, 0}
};

static void print_usage(const char *name)
{
    fprintf(stderr, "usage: %s options...\n", name);
    fprintf(stderr, "  options:\n");
    fprintf(stderr, "    -p --devpath      <devpath>      device path\n");
    fprintf(stderr, "    -e --eid          <eid>          my eid\n");
    fprintf(stderr, "    -d --eid          <eid>          destination eid\n");
    fprintf(stderr, "    -t --test         <test case>    Run test case\n");
    fprintf(stderr, "    -l --loop         <loop count>   Test loop count\n");
    fprintf(stderr, "    -h --help                        Output usage message and exit.\n");
}

int main(int argc, char **argv)
{
    struct mctp_binding_npcmi3c *npcmi3c;
    struct mctp *mctp;
    char *i3cdev_path = NULL;
    int opt, loop = 1;
    int i;
    uint8_t eid = 8, dst_eid = 32;

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
        case 'd':
            dst_eid = atoi(optarg);
            break;
        case 'l':
            loop = atoi(optarg);
            break;
        case 't':
            test = atoi(optarg);
            break;
        default:
            print_usage(argv[0]);
            exit(EXIT_FAILURE);
        }
    }
    assert(i3cdev_path);

    mctp = mctp_init();
    assert(mctp);

    npcmi3c = mctp_npcmi3c_init();
    assert(npcmi3c);

    mctp_npcmi3c_open_path(npcmi3c, i3cdev_path);

    mctp_register_bus(mctp, mctp_binding_npcmi3c_core(npcmi3c), eid);

    switch (test) {
    case i3c_packet_write:
        printf("i3c_packet_write test\n");
        mctp_set_log_stdio(MCTP_LOG_DEBUG);
        test_npcmi3c_tx_btu(npcmi3c, mctp, dst_eid);
        printf("i3c_packet_write test complete\n");
        break;
    case i3c_packet_read:
        printf("i3c_packet_read test\n");
        mctp_set_log_stdio(MCTP_LOG_DEBUG);
        test_npcmi3c_rx(npcmi3c, mctp);
        printf("i3c_packet_read test complete\n");
        break;
    case mctp_npcmi3c_daemon_test:
        printf("mctp_npcmi3c_daemon test\n");
        mctp_set_log_stdio(MCTP_LOG_WARNING);
        for (i = 0; i < loop; i++) {
            printf("loop %d\n", i);
            test_npcmi3c_daemon(npcmi3c, mctp, dst_eid);
        }
        printf("mctp_npcmi3c_daemon test complete\n");
        break;
    }

    return 0;
}
