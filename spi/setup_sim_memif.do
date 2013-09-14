add log -r /*
add log sim:/memif_test/u1/*
add wave sim:/memif_test/u1/*
radix -hex
run -all
wave zoom range 0ns 250ns
