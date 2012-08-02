add log -r /*
add log sim:/CPUtest/u1/mem/rf0/r*
add wave sim:/CPUtest/u1/dsp/*
radix -hex
run -all
wave zoom range 125ns 250ns

