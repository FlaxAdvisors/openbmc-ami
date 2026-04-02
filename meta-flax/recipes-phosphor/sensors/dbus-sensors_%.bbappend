# meta-facebook removes intelcpusensor; re-enable it for TiogaPass
# which uses Intel PECI for CPU/DIMM temperature (feeds phosphor-pid-control)
PACKAGECONFIG:append:tiogapass = " intelcpusensor"

# Skip individual "Core N" per-core temperature sensors.
# DTS and Die aggregate sensors cover CPU thermal status for fan control.
# do_patch base (from patch.bbclass EXPORT_FUNCTIONS) is a Python function,
# so the append must also be Python.
python do_patch:append() {
    import os

    src = os.path.join(d.getVar('S'), 'src', 'IntelCPUSensorMain.cpp')

    if not os.path.exists(src):
        return

    insertion = (
        '\n'
        '            // Skip individual per-core temps ("Core 0", "Core 1", ...).\n'
        '            // DTS and Die sensors provide aggregate CPU thermal coverage.\n'
        '            if (label.size() > 5 && label.compare(0, 5, "Core ") == 0 &&\n'
        '                std::isdigit(static_cast<unsigned char>(label[5])))\n'
        '            {\n'
        '                continue;\n'
        '            }\n'
    )

    marker = 'labelFile.close();\n\n            std::string sensorName'
    replacement = 'labelFile.close();\n' + insertion + '\n            std::string sensorName'

    with open(src) as f:
        content = f.read()

    if 'Skip individual per-core temps' in content:
        return  # already applied

    new_content = content.replace(marker, replacement, 1)
    if new_content == content:
        bb.fatal('skip-core-temps: marker not found in %s' % src)

    with open(src, 'w') as f:
        f.write(new_content)

    bb.note('Applied core-skip patch to %s' % src)
}
