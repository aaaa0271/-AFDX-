create_clock -name {sys_clk} -period 80.000 [get_ports {clk}]
derive_clock_uncertainty
