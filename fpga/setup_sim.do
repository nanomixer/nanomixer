add log -r /*
add wave sim:/CPUtest/u1/dsp/*
radix -hex
run -all
wave zoom range 125ns 250ns

