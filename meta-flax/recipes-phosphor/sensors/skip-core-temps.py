#!/usr/bin/env python3
"""
Patch IntelCPUSensorMain.cpp to skip per-core CPU temperature sensors.
Called from dbus-sensors_%.bbappend do_patch:append:tiogapass.
"""
import sys

src = sys.argv[1]

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
    sys.exit(0)  # already applied

new_content = content.replace(marker, replacement, 1)
if new_content == content:
    print(f"WARNING: core-skip marker not found in {src}", file=sys.stderr)
    sys.exit(1)

with open(src, 'w') as f:
    f.write(new_content)

print(f"Applied core-skip to {src}")
