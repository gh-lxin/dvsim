// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_monitor.

class ${name}_monitor extends uvm_monitor;
  `uvm_component_utils(${name}_monitor)

  ${name}_agent_cfg cfg;
  ${name}_agent_cov cov;

  // Indicates activity on the interface; driven within monitor_ready_to_end().
  protected bit ok_to_end = 1;

  // Ensures watchdog runs once at end of run phase.
  protected bit phase_ready_to_end_invoked = 0;

  // Analysis port for the collected transfer.
  uvm_analysis_port #(${name}_item) analysis_port;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_port = new("analysis_port", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    fork
      collect_trans();
    join
  endtask

  // Collect transactions forever.
  virtual protected task collect_trans();
    forever begin
      // TODO: detect event

      // TODO: sample the interface

      // TODO: sample the covergroups

      // TODO: write trans to analysis_port

      // TODO: remove the line below: it is added to prevent zero delay loop in template code
      #1us;
    end
  endtask

  // UVM callback invoked during phase sequencing.
  virtual function void phase_ready_to_end(uvm_phase phase);
    if (!phase.is(uvm_run_phase::get())) return;
    if (phase_ready_to_end_invoked) return;

    phase_ready_to_end_invoked = 1;
    fork
      monitor_ready_to_end();
      watchdog_ok_to_end(phase);
    join_none
  endfunction

  // Ensures ok_to_end stays asserted for ok_to_end_delay_ns before dropping objection.
  virtual task watchdog_ok_to_end(uvm_phase run_phase);
    bit objection_raised;
    bit watchdog_done;
    uint watchdog_restart_count = 1;

    forever begin
      if (!objection_raised) begin
        `uvm_info(`gfn, "watchdog_ok_to_end: raising objection", UVM_MEDIUM)
        run_phase.raise_objection(this, {`gfn, "objection raised"});
        objection_raised = 1'b1;
      end

      wait (ok_to_end);
      `uvm_info(`gfn, $sformatf("watchdog_ok_to_end: starting the timer (count: %0d)",
                                watchdog_restart_count++), UVM_MEDIUM)
      fork
        begin: isolation_fork
          fork
            begin
              watchdog_done = 1'b0;
              #(cfg.ok_to_end_delay_ns * 1ns);
              watchdog_done = 1'b1;
            end
            wait (!ok_to_end);
          join_any
          disable fork;
        end: isolation_fork
      join

      if (ok_to_end && watchdog_done) begin
        `uvm_info(`gfn, "watchdog_ok_to_end: dropping objection", UVM_MEDIUM)
        run_phase.drop_objection(this, {`gfn, "objection dropped"});
        objection_raised = 1'b0;
        wait (!ok_to_end);
      end
    end
  endtask

  // Override to assert/de-assert ok_to_end based on bus activity (forever loop).
  virtual task monitor_ready_to_end();
  endtask

endclass
