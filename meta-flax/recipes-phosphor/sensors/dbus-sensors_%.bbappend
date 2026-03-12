# meta-facebook removes intelcpusensor; re-enable it for TiogaPass
# which uses Intel PECI for CPU/DIMM temperature (feeds phosphor-pid-control)
PACKAGECONFIG:append:tiogapass = " intelcpusensor"
