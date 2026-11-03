# Clock example only. Complete actual board I/O and CDC constraints separately.
create_clock -name ai_clk -period 80.000 [get_ports clk]
