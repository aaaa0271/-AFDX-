# SNMP/MIB sidecar evidence commands
#
# 1) Regenerate the source-hashed inventory:
#    python scripts/build_standard_mib_inventory.py
# 2) Check inventory consistency and source hashes:
#    python scripts/verify_standard_mib_inventory.py
# 3) Run the existing bounded ModelSim bank/policy test through the project runner:
#    powershell -File run_all.ps1 -Python <python>   # full project regression
#    or use scripts/run_all.py --tests tb_afdx_standard_mib
# 4) The existing bounded v2c wire evidence remains:
#    tb_contest_snmp_pysnmp + scripts/verify_snmp_interop.py
#    tb_completion_snmp_extended + scripts/verify_snmp_extended.py
#
# A PASS from these checks does not close standard MIB or SNMPv1/v2c/v3
# certification; it only validates the declared evidence boundary.
