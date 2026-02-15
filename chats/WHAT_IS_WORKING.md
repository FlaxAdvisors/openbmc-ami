# What is (and is Not) Working

This is a brief summary of checks with the emulator

openbmc default user is `root` and password is `0penBmc` and it is available for ssh, ipmi, and bmcweb.

## BMC Web

Working but likely need hardware to verify event logs, system population and inventory, and SOL, KVM, virtual media operational.

## IPMI

### Good

* bmc in-band
* oob

* chassis (power, bootdev)
* mc (info, reset cold)
* user
* lan (truncated compared to AMI)

```bash
dbahi@hoster-lorax:~/vvroom$ ipmitool -C 17 -I lanplus -U root -P 0penBmc -H localhost -p 9623 power status
Chassis Power is off
```

```bash
dbahi@hoster-lorax:~/vvroom$ ipmitool -C 17 -I lanplus -U root -P 0penBmc -H localhost -p 9623 mc info
Device ID                 : 32
Device Revision           : 1
Firmware Revision         : 0.00
IPMI Version              : 2.0
Manufacturer ID           : 40981
Manufacturer Name         : Facebook, Inc.
Product ID                : 12614 (0x3146)
Product Name              : Unknown (0x3146)
Device Available          : no
Provides Device SDRs      : yes
Additional Device Support :
    Sensor Device
    SDR Repository Device
    SEL Device
    FRU Inventory Device
    IPMB Event Receiver
    IPMB Event Generator
    Chassis Device
Aux Firmware Rev Info     :
    0x00
    0x00
    0x00
    0x00
```

```bash
dbahi@hoster-lorax:~/vvroom$ ipmitool -C 17 -I lanplus -U root -P 0penBmc -H localhost -p 9623 lan print 1
Set in Progress         : Set Complete
Auth Type Support       :
Auth Type Enable        : Callback :
                        : User     :
                        : Operator :
                        : Admin    :
                        : OEM      :
IP Address Source       : DHCP Address
IP Address              : 10.0.2.15
Subnet Mask             : 255.255.255.0
MAC Address             : 8a:77:81:a4:9d:4b
Default Gateway IP      : 10.0.2.2
Default Gateway MAC     : 00:00:00:00:00:00
802.1q VLAN ID          : Disabled
RMCP+ Cipher Suites     : 17
Cipher Suite Priv Max   : aaaaaaaaaaaaaaa
                        :     X=Cipher Suite Unused
                        :     c=CALLBACK
                        :     u=USER
                        :     o=OPERATOR
                        :     a=ADMIN
                        :     O=OEM
Bad Password Threshold  : Not Available
```


### Bad

* sol
* fru
* sel
* sdr
* sensor

```bash
Error: No response activating SOL payload
```

```bash
FRU Device Description : Builtin FRU Device (ID 0)
 Device not present (Requested sensor, data, or record not found)

Get SDR 0000 command failed: Requested sensor, data, or record not found
```


## Redfish

```bash
dbahi@hoster-lorax:~/vvroom$ curl -k https://localhost:9443/redfish/v1/ -u root:0penBmc 2>/dev/null
```

```json
{
  "@odata.id": "/redfish/v1",
  "@odata.type": "#ServiceRoot.v1_15_0.ServiceRoot",
  "AccountService": {
    "@odata.id": "/redfish/v1/AccountService"
  },
  "Cables": {
    "@odata.id": "/redfish/v1/Cables"
  },
  "CertificateService": {
    "@odata.id": "/redfish/v1/CertificateService"
  },
  "Chassis": {
    "@odata.id": "/redfish/v1/Chassis"
  },
  "EventService": {
    "@odata.id": "/redfish/v1/EventService"
  },
  "Id": "RootService",
  "JsonSchemas": {
    "@odata.id": "/redfish/v1/JsonSchemas"
  },
  "Links": {
    "ManagerProvidingService": {
      "@odata.id": "/redfish/v1/Managers/bmc"
    },
    "Sessions": {
      "@odata.id": "/redfish/v1/SessionService/Sessions"
    }
  },
  "Managers": {
    "@odata.id": "/redfish/v1/Managers"
  },
  "Name": "Root Service",
  "ProtocolFeaturesSupported": {
    "DeepOperations": {
      "DeepPATCH": false,
      "DeepPOST": false
    },
    "ExcerptQuery": false,
    "ExpandQuery": {
      "ExpandAll": true,
      "Levels": true,
      "Links": true,
      "MaxLevels": 6,
      "NoLinks": true
    },
    "FilterQuery": true,
    "OnlyMemberQuery": true,
    "SelectQuery": true
  },
  "RedfishVersion": "1.17.0",
  "Registries": {
    "@odata.id": "/redfish/v1/Registries"
  },
  "SessionService": {
    "@odata.id": "/redfish/v1/SessionService"
  },
  "Systems": {
    "@odata.id": "/redfish/v1/Systems"
  },
  "Tasks": {
    "@odata.id": "/redfish/v1/TaskService"
  },
  "TelemetryService": {
    "@odata.id": "/redfish/v1/TelemetryService"
  },
  "UUID": "8cd76422-42b9-4f17-bc70-a9824e4d08d2",
  "UpdateService": {
    "@odata.id": "/redfish/v1/UpdateService"
  }
```

