# OpenCruise hardware (KiCad 9)

- pwrctrl/  : main power-control / vehicle-interface board (schematic + placement-proposal PCB, NOT routed yet)
- usbblock/ : USB-A inline VBUS back-feed blocker adapter (schematic)
- lib/      : project symbol/footprint library (OpenCruise) and 3D models
- gen/      : Python generators used to build the schematics/placement (kicad-cli + pcbnew 9.0)

Status v1.7 (2026-11-09): schematics complete, ERC 0 errors / 0 warnings. PCB layout pending review of placement_proposal.png.
Design notes: Claude project docs claude/power-board-design.md, firmware-config-spec.md, usb-adapter-design.md
