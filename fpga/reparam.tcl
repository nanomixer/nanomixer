
##############################################################################################
############################# Basic vJTAG Interface ##########################################
##############################################################################################

#This portion of the script is derived from some of the examples from Altera

global usbblaster_name
global test_device
# List all available programming hardwares, and select the USBBlaster.
# (Note: this example assumes only one USBBlaster connected.)
# Programming Hardwares:
foreach hardware_name [get_hardware_names] {
#	puts $hardware_name
	if { [string match "USB-Blaster*" $hardware_name] } {
		set usbblaster_name $hardware_name
	}
}


puts "\nSelect JTAG chain connected to $usbblaster_name.\n";

# List all devices on the chain, and select the first device on the chain.
#Devices on the JTAG chain:


foreach device_name [get_device_names -hardware_name $usbblaster_name] {
#	puts $device_name
	if { [string match "@1*" $device_name] } {
		set test_device $device_name
	}
}
puts "\nSelect device: $test_device.\n";


# Open device 
proc openport {} {
	global usbblaster_name
        global test_device
	open_device -hardware_name $usbblaster_name -device_name $test_device
}

foreach instance [get_editable_mem_instances -hardware_name $usbblaster_name -device_name $test_device] {
	set name [lindex $instance 5];
	if { [string match "parm" $name] } {
		set instance_idx [lindex $instance 0];
	}
}
puts "\nInstance $instance_idx";

begin_memory_edit -hardware_name $usbblaster_name -device_name $test_device
update_content_to_memory_from_file -instance_index $instance_idx -mem_file_path "param.mif" -mem_file_type mif
end_memory_edit

