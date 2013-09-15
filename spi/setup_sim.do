add log -r /*
add wave sim:/spi_test/*
add log sim:/spi_test/serdes_inst/*
add wave sim:/spi_test/serdes_inst/*
add log sim:/spi_test/memif_inst/*
add wave sim:/spi_test/memif_inst/*
radix -hex
run -all
wave zoom range 0ns 250ns
