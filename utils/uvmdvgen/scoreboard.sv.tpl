// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_scoreboard.
class ${name}_scoreboard extends uvm_component;
  `uvm_component_utils(${name}_scoreboard)

  ${name}_env_cfg cfg;
  ${name}_reg_block ral;
  ${name}_env_cov cov;

  bit obj_raised      = 1'b0;
  bit under_pre_abort = 1'b0;

  // TLM agent fifos
% for agent in env_agents:
  uvm_tlm_analysis_fifo #(${agent}_item) ${agent}_fifo;
% endfor

  // local queues to hold incoming packets pending comparison
% for agent in env_agents:
  ${agent}_item ${agent}_q[$];
% endfor

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ral = cfg.ral;
% for agent in env_agents:
    ${agent}_fifo = new("${agent}_fifo", this);
% endfor
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    fork
      monitor_reset();
      sample_resets();
% for agent in env_agents:
      process_${agent}_fifo();
% endfor
    join_none
  endtask

  virtual task monitor_reset();
    forever begin
      if (!cfg.clk_rst_vif.rst_n) begin
        `uvm_info(`gfn, "reset occurred", UVM_HIGH)
        cfg.reset_asserted();
        @(posedge cfg.clk_rst_vif.rst_n);
        reset();
        cfg.reset_deasserted();
        csr_utils_pkg::clear_outstanding_access();
        `uvm_info(`gfn, "out of reset", UVM_HIGH)
      end
      else begin
        @(cfg.clk_rst_vif.rst_n);
      end
    end
  endtask

  virtual task sample_resets();
  endtask
% for agent in env_agents:

  virtual task process_${agent}_fifo();
    ${agent}_item item;
    forever begin
      ${agent}_fifo.get(item);
      `uvm_info(`gfn, $sformatf("received ${agent} item:\n%0s", item.sprint()), UVM_HIGH)
    end
  endtask
% endfor

  virtual function void reset(string kind = "HARD");
    foreach (cfg.ral_models[i]) cfg.ral_models[i].reset(kind);
    // reset local fifos queues and variables
  endfunction

  virtual function void pre_abort();
    super.pre_abort();
    if (has_uvm_fatal_occurred() &&
        !under_pre_abort &&
        m_current_phase != null &&
        m_current_phase.is(uvm_run_phase::get())) begin
      under_pre_abort = 1;
      check_phase(m_current_phase);
      under_pre_abort = 0;
    end
  endfunction : pre_abort

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // post test checks - ensure that all local fifos and queues are empty
  endfunction

endclass
