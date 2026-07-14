// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_driver. With -s, host/device drivers extend this class.

class ${name}_driver extends uvm_driver #(.REQ(${name}_item), .RSP(${name}_item));
  `uvm_component_utils(${name}_driver)

  ${name}_agent_cfg cfg;

  `uvm_component_new

  // Runs reset_signals() and get_and_drive() in parallel.
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    fork
      reset_signals();
      get_and_drive();
    join
  endtask

  // Monitors cfg.in_reset and calls on_enter_reset / on_leave_reset.
  virtual task reset_signals();
    forever begin
      `uvm_info(get_full_name(), "Driver entering reset", UVM_HIGH)
      on_enter_reset();
      wait(!cfg.in_reset);
      `uvm_info(get_full_name(), "Driver leaving reset", UVM_HIGH)
      on_leave_reset();
      wait(cfg.in_reset);
    end
  endtask

  // Drive transactions received from the sequencer.
  // With -s, host/device drivers override this; without -s, fill in the TODO.
  virtual task get_and_drive();
% if has_separate_host_device_driver:
    `uvm_fatal(`gfn, "This task must be implemented by host/device driver subclasses.")
% else:
    forever begin
      seq_item_port.get_next_item(req);
      $cast(rsp, req.clone());
      rsp.set_id_info(req);
      `uvm_info(`gfn, $sformatf("rcvd item:\n%0s", req.sprint()), UVM_HIGH)
      // TODO: do the driving part
      //
      // send rsp back to seq
      `uvm_info(`gfn, "item sent", UVM_HIGH)
      seq_item_port.item_done(rsp);
    end
% endif
  endtask

  // Clear driven signals at the start of reset (must not consume time).
  virtual task on_enter_reset();
  endtask

  // Called when leaving reset.
  virtual function void on_leave_reset();
  endfunction

endclass
