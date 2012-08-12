global usbblaster_name
global test_device
global instance_idx
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

foreach instance [get_editable_mem_instances -hardware_name $usbblaster_name -device_name $test_device] {
	set name [lindex $instance 5];
	if { [string match "parm" $name] } {
		set instance_idx [lindex $instance 0];
	}
}
puts "Instance $instance_idx";

proc Start_Server {port} {
	set s [socket -server ConnAccept $port]
	puts "Started Socket Server on port - $port"
	vwait forever
}

	
proc ConnAccept {sock addr port} {
    global conn

    # Record the client's information

    puts "Accept $sock from $addr port $port"
    set conn(addr,$sock) [list $addr $port]

    # Ensure that each "puts" by the server
    # results in a network transmission

    fconfigure $sock -buffering line

    # Set up a callback for when the client sends data

    fileevent $sock readable [list IncomingData $sock]

    OpenPort
}


proc IncomingData {sock} {
    global conn

    # Check end of file or abnormal connection drop,
    # then write the data to the vJTAG

    if {[eof $sock] || [catch {
	set addr [expr [read $sock 10]]
	set length [expr [read $sock 10]]
	set content [read $sock $length]}]} {
	close $sock
	puts "Close $conn(addr,$sock)"
	unset conn(addr,$sock)
	ClosePort
    } else {
	setMemContent $addr $content
	puts -nonewline $sock "1"
	flush $sock
    }
}


proc OpenPort {} {
    global usbblaster_name
    global test_device
    begin_memory_edit -hardware_name $usbblaster_name -device_name $test_device
}

proc ClosePort {} {
    end_memory_edit
}

proc setMemContent {addr content} {
    global instance_idx
    set content_words [expr [string length $content] / 9]
    puts "Setting $content_words at $addr to $content"
    write_content_to_memory -instance_index $instance_idx -start_address $addr -content $content -word_count $content_words -content_in_hex
}

#Start thet Server at Port 2540
Start_Server 2540
