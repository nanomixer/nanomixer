# List all available programming hardwares, and select the USBBlaster.
# (Note: this example assumes only one USBBlaster connected.)
# Programming Hardwares:
foreach hardware_name [get_hardware_names] {
#	puts $hardware_name
	if { [string match "USB-Blaster*" $hardware_name] } {
		set usbblaster_name $hardware_name
	}
}

puts "\n\nSelect JTAG chain connected to $usbblaster_name.";

# List all devices on the chain, and select the first device on the chain.
foreach device_name [get_device_names -hardware_name $usbblaster_name] {
#	puts $device_name
	if { [string match "@1*" $device_name] } {
		set test_device $device_name
	}
}
puts "Select device: $test_device.";

set instance_indices [dict create]
foreach instance [get_editable_mem_instances -hardware_name $usbblaster_name -device_name $test_device] {
    set index [lindex $instance 0]
    set name [lindex $instance 5]
    dict set instance_indices $name $index
}
puts "Instance $instance_indices";
set metering_instance [dict get $instance_indices "MMEM"]

# This server is continuously editing memory.
begin_memory_edit -hardware_name $usbblaster_name -device_name $test_device


proc AcceptParamServerConnection {sock addr port} {
    # Ensure that each "puts" by the server
    # results in a network transmission
    fconfigure $sock -buffering line

    # Set up a callback following when the client sends data
    fileevent $sock readable [list IncomingParamData $sock]
}

proc AcceptMeteringConnection { sock addr port} {
    # Ensure that each "puts" by the server
    # results in a network transmission
    fconfigure $sock -buffering line

    fileevent $sock writable [list WriteMeteringData $sock]
}

proc WriteMeteringData {sock} {
    global metering_instance
    set metering_data [read_content_from_memory -content_in_hex -instance_index metering_instance -start_address 0 -word_count 8]
    puts -nonewline $sock $metering_data
    flush $sock
}

proc IncomingParamData {sock} {
    # Check end of file or abnormal connection drop,
    # then write the data to the vJTAG

    if {[eof $sock] || [catch {
	set mem_name [read $sock 4]
	set addr [expr [read $sock 10]]
	set length [expr [read $sock 10]]
	set content [read $sock $length]}]} {

	close $sock
	ClosePort
    } else {
	setMemContent $mem_name $addr $content
    # Read metering memory contents.
    puts -nonewline $sock "1"
	flush $sock
    }
}

proc setMemContent {mem_name addr content} {
	global instance_indices
    set instance_idx [dict get $instance_indices $mem_name]
    set content_words [expr [string length $content] / 9]
    puts "Setting $content_words at $mem_name:$addr to $content"
    write_content_to_memory -instance_index $instance_idx -start_address $addr -content $content -word_count $content_words -content_in_hex
}


set paramServerPort 2540
set meterServerPort 2541
socket -server AcceptParamServerConnection $paramServerPort
socket -server AcceptMeteringConnection $meterServerPort

puts "Started Socket Server on port $paramServerPort"
vwait forever

end_memory_edit
