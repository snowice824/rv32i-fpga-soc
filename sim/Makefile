CWD=$(shell pwd)

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# RTL sources live one directory up
VERILOG_SOURCES = $(CWD)/../rtl/*.v

# The top-level Verilog module to simulate (rtl/riscv_top.v)
TOPLEVEL = RISCV_Top

# The name of the Python testbench file (without the .py extension)
MODULE := riscv_test

COCOTB_HDL_TIMEUNIT=1ns
COCOTB_HDL_TIMEPRECISION=1ns

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
