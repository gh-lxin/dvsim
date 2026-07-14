// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_agent_cfg + agent-specific vif.

class ${name}_agent_cfg extends uvm_object;

  // True if this is an active agent (has driver and sequencer). If false, passive (monitor only).
  bit is_active = 1'b1;

  // True if the agent should enable a monitor
  bit en_monitor = 1'b1;

  // True if the agent should collect functional coverage
  bit en_cov = 1'b1;

  // Interface mode on the bus: Host (drive DUT as device) or Device (respond to DUT as host).
  if_mode_e if_mode;

  // True if the agent has its own driver attached to the sequencer.
  bit has_driver = 1'b1;

  // Minimum time in ns the monitor expects ok_to_end high before dropping run_phase objection.
  int ok_to_end_delay_ns = 1000;

  // Indicates that the interface is under reset (maintained by the monitor).
  bit in_reset;

  // interface handle used by driver, monitor & the sequencer, via cfg handle
  virtual ${name}_if vif;

  `uvm_object_utils_begin(${name}_agent_cfg)
    `uvm_field_int (is_active,            UVM_DEFAULT)
    `uvm_field_int (en_monitor,           UVM_DEFAULT)
    `uvm_field_int (en_cov,               UVM_DEFAULT)
    `uvm_field_enum(if_mode_e, if_mode,   UVM_DEFAULT)
    `uvm_field_int (has_driver,           UVM_DEFAULT)
    `uvm_field_int (ok_to_end_delay_ns,   UVM_DEFAULT)
    `uvm_field_int (in_reset,             UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass
