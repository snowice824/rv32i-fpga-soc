# Recreate the Vivado project for the Nexys A7-100T.
#
# Usage (from the repository root):
#   vivado -mode batch -source create_project.tcl
# or, from the Vivado Tcl console:
#   source create_project.tcl
#
# The project is generated in ./vivado_project (git-ignored).

set script_dir [file normalize [file dirname [info script]]]
set proj_name  riscv
set proj_dir   [file join $script_dir vivado_project]

create_project $proj_name $proj_dir -part xc7a100tcsg324-1 -force
set_property board_part digilentinc.com:nexys-a7-100t:part0:1.2 [current_project]
set_property target_language Verilog [current_project]

# RTL sources
add_files -fileset sources_1 [glob [file join $script_dir rtl *.v]]

# Program image loaded by $readmemh("Instructions.hex", ...) in the memories.
# Adding it to the project lets Vivado find it during synthesis and simulation.
add_files -fileset sources_1 [file join $script_dir sim Instructions.hex]

set_property top Nexys_A7 [get_filesets sources_1]
set_property top Nexys_A7 [get_filesets sim_1]

# Pin constraints
add_files -fileset constrs_1 [file join $script_dir constraints Nexys-A7-100T-Master.xdc]

update_compile_order -fileset sources_1

puts "Project created in $proj_dir"
puts "Next: launch_runs impl_1 -to_step write_bitstream -jobs 4"
