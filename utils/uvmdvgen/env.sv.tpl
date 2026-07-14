// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_env.
class ${name}_env extends uvm_env;
  `uvm_component_utils(${name}_env)

  ${name}_env_cfg           cfg;
  ${name}_virtual_sequencer virtual_sequencer;
  ${name}_scoreboard        scoreboard;
  ${name}_env_cov           cov;
% if env_agents != []:

% for agent in env_agents:
  ${agent}_agent m_${agent}_agent;
% endfor
% endif

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    string ral_models[$];

    super.build_phase(phase);
    if (!uvm_config_db#(${name}_env_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal(`gfn, $sformatf("failed to get %s from uvm_config_db", cfg.get_type_name()))
    end

    ral_models = cfg.get_ral_model_names();
    if (ral_models.size() > 0) begin
      string default_ral_name = cfg.ral.get_type_name();
      foreach (ral_models[i]) begin
        string ral_name = ral_models[i];
        configure_clk_rst_vif(ral_name, (ral_name == default_ral_name));
      end

      `DV_CHECK_FATAL(cfg.clk_rst_vifs.exists(default_ral_name))
      cfg.clk_rst_vif = cfg.clk_rst_vifs[default_ral_name];
    end else begin
      if (cfg.clk_rst_vif == null &&
          !uvm_config_db#(virtual clk_rst_if)::get(this, "", "clk_rst_vif", cfg.clk_rst_vif)) begin
        `uvm_fatal(get_full_name(), "Failed to get clk_rst_if from uvm_config_db")
      end
      cfg.clk_rst_vif.set_freq_mhz(cfg.clk_freq_mhz);
    end

    if (cfg.en_cov) begin
      cov = ${name}_env_cov::type_id::create("cov", this);
      cov.cfg = cfg;
    end

    if (cfg.is_active) begin
      virtual_sequencer = ${name}_virtual_sequencer::type_id::create("virtual_sequencer", this);
      virtual_sequencer.cfg = cfg;
      virtual_sequencer.cov = cov;
    end

    scoreboard = ${name}_scoreboard::type_id::create("scoreboard", this);
    scoreboard.cfg = cfg;
    scoreboard.cov = cov;
% for agent in env_agents:
    m_${agent}_agent = ${agent}_agent::type_id::create("m_${agent}_agent", this);
    uvm_config_db#(${agent}_agent_cfg)::set(this, "m_${agent}_agent*", "cfg", cfg.m_${agent}_agent_cfg);
    cfg.m_${agent}_agent_cfg.en_cov = cfg.en_cov;
% endfor
  endfunction

  local function void configure_clk_rst_vif(string ral_name, bit is_default_ral_name);
    string if_name = is_default_ral_name ? "clk_rst_vif" : {"clk_rst_vif_", ral_name};

    if (!cfg.clk_rst_vifs.exists(ral_name) &&
        !uvm_config_db#(virtual clk_rst_if)::get(this, "",
                                                 if_name, cfg.clk_rst_vifs[ral_name])) begin
      `uvm_fatal(get_full_name(), $sformatf("No clk_rst_if called %0s in uvm_config_db", ral_name))
    end

    cfg.clk_rst_vifs[ral_name].set_freq_mhz(cfg.clk_freqs_mhz[ral_name]);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
% if env_agents != []:
    if (cfg.en_scb) begin
% endif
% for agent in env_agents:
      m_${agent}_agent.monitor.analysis_port.connect(scoreboard.${agent}_fifo.analysis_export);
% endfor
% if env_agents != []:
    end
% endif
% for agent in env_agents:
    if (cfg.is_active && cfg.m_${agent}_agent_cfg.is_active) begin
      virtual_sequencer.${agent}_sequencer_h = m_${agent}_agent.sequencer;
    end
% endfor
  endfunction

endclass
