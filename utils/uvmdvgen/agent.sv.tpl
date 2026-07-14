// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// ${name}_agent: inlined from dv_base_agent (cfg/cov/driver/sequencer/monitor create & connect)
// plus agent-specific vif lookup.

class ${name}_agent extends uvm_agent;
  `uvm_component_utils(${name}_agent)

  ${name}_agent_cfg cfg;
  ${name}_agent_cov cov;
  // With -s, host/device drivers extend ${name}_driver.
  ${name}_driver    driver;
  ${name}_sequencer sequencer;
  ${name}_monitor   monitor;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null && !uvm_config_db#(${name}_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal(`gfn, $sformatf("failed to get %s from uvm_config_db", cfg.get_type_name()))
    end
    `uvm_info(`gfn, $sformatf("\n%0s", cfg.sprint()), UVM_HIGH)

    // get ${name}_if handle
    if (!uvm_config_db#(virtual ${name}_if)::get(this, "", "vif", cfg.vif)) begin
      `uvm_fatal(`gfn, "failed to get ${name}_if handle from uvm_config_db")
    end

    if (cfg.en_cov) begin
      cov = ${name}_agent_cov::type_id::create("cov", this);
      cov.cfg = cfg;
    end

    monitor = ${name}_monitor::type_id::create("monitor", this);
    monitor.cfg = cfg;
    monitor.cov = cov;

    if (cfg.is_active) begin
      sequencer = ${name}_sequencer::type_id::create("sequencer", this);
      sequencer.cfg = cfg;

      if (cfg.has_driver) begin
% if has_separate_host_device_driver:
        if (cfg.if_mode == Host) begin
          driver = ${name}_host_driver::type_id::create("driver", this);
        end else begin
          driver = ${name}_device_driver::type_id::create("driver", this);
        end
% else:
        driver = ${name}_driver::type_id::create("driver", this);
% endif
        driver.cfg = cfg;
      end
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active && cfg.has_driver) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass
