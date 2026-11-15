open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
foreach device [get_hw_devices] {puts "P7_HW_DEVICE=$device PART=[get_property PART $device]"}
close_hw_target
close_hw_manager
