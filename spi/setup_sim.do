add log -r /*
add log sim:/spi_test/u1/*
add wave sim:/spi_test/u1/*
radix -hex
run -all
wave zoom range 125ns 250ns
