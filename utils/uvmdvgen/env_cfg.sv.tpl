// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_env_cfg.
class ${name}_env_cfg extends uvm_object;

  bit is_active = 1;
  bit en_scb = 1;
  bit en_scb_mem_chk = 1;
  bit en_cov = 0;
  bit en_dv_cdc = 0;
  bit under_reset = 0;
  protected bit is_initialized = 0;
  bit smoke_test = 0;
  rand bit zero_delays;

  protected string ral_type_name = ${name}_reg_block::type_name;

  typedef string string_queue_t[$];
  protected string_queue_t ral_model_names;

  function string_queue_t get_ral_model_names();
    return ral_model_names;
  endfunction

  dv_base_reg_block ral_models[string];
  virtual clk_rst_if clk_rst_vifs[string];
  rand uint clk_freqs_mhz[string];
  ${name}_reg_block ral;
  virtual clk_rst_if clk_rst_vif;
  rand uint clk_freq_mhz;

  // ext component cfgs
% for agent in env_agents:
  rand ${agent}_agent_cfg m_${agent}_agent_cfg;
% endfor

  constraint zero_delays_c {
    zero_delays dist {1'b0 := 6, 1'b1 := 4};
  }

  constraint clk_freq_mhz_c {
    `DV_COMMON_CLK_CONSTRAINT(clk_freq_mhz)
    foreach (clk_freqs_mhz[i]) {
      `DV_COMMON_CLK_CONSTRAINT(clk_freqs_mhz[i])
    }
  }

  `uvm_object_utils_begin(${name}_env_cfg)
    `uvm_field_int              (is_active,       UVM_DEFAULT)
    `uvm_field_int              (en_scb,          UVM_DEFAULT)
    `uvm_field_int              (en_scb_mem_chk,  UVM_DEFAULT)
    `uvm_field_int              (en_cov,          UVM_DEFAULT)
    `uvm_field_int              (en_dv_cdc,       UVM_DEFAULT)
    `uvm_field_int              (smoke_test,      UVM_DEFAULT)
    `uvm_field_int              (zero_delays,     UVM_DEFAULT)
    `uvm_field_queue_string     (ral_model_names, UVM_DEFAULT)
    `uvm_field_aa_object_string (ral_models,      UVM_DEFAULT)
    `uvm_field_aa_int_string    (clk_freqs_mhz,   UVM_DEFAULT)
% for agent in env_agents:
    `uvm_field_object(m_${agent}_agent_cfg, UVM_DEFAULT)
% endfor
  `uvm_object_utils_end

  `uvm_object_new

  function void pre_randomize();
    if (!is_initialized) `uvm_fatal(`gfn, "Run initialize() before randomizing this object.")
  endfunction

  function void post_randomize();
    if (clk_freqs_mhz.size > 0) begin
      `DV_CHECK_FATAL(clk_freqs_mhz.exists(ral_type_name))
      clk_freqs_mhz[ral_type_name] = clk_freq_mhz;
    end
  endfunction

  virtual function void initialize_ral(int unsigned addr_width,
                                       int unsigned data_width,
                                       int unsigned be_width);
    if (is_initialized) `uvm_fatal(`gfn, "Cannot call initialize_ral when already initialized")

    ral_model_names.push_front(ral_type_name);
    is_initialized = 1'b1;
    make_ral_models(addr_width, data_width, be_width);
    foreach (ral_model_names[i]) begin
      clk_freqs_mhz[ral_model_names[i]] = 0;
    end
  endfunction

  protected virtual function void pre_build_ral_settings(dv_base_reg_block ral);
  endfunction

  protected virtual function void post_build_ral_settings(dv_base_reg_block ral);
  endfunction

  virtual function void reset_asserted();
    this.under_reset = 1;
    csr_utils_pkg::reset_asserted();
  endfunction

  virtual function void reset_deasserted();
    this.under_reset = 0;
    csr_utils_pkg::reset_deasserted();
  endfunction

  local function void make_ral_models(int unsigned addr_width,
                                      int unsigned data_width,
                                      int unsigned be_width);
    foreach (ral_model_names[i]) begin
      make_ral_model(ral_model_names[i], addr_width, data_width, be_width);
    end
    if (!ral_models.exists(ral_type_name)) begin
      `uvm_fatal(get_name(),
                 $sformatf("The generated RAL models don't include ral_type_name=%0s.",
                           ral_type_name))
    end
  endfunction

  local function void make_ral_model(string       ral_model_name,
                                     int unsigned addr_width,
                                     int unsigned data_width,
                                     int unsigned be_width);
    dv_base_reg_block reg_blk;

    if (ral_models.exists(ral_model_name)) begin
      reg_blk = ral_models[ral_model_name];
    end else begin
      reg_blk = create_ral_by_name(ral_model_name);
      pre_build_ral_settings(reg_blk);
      reg_blk.build(.base_addr(0), .csr_excl(null));
      reg_blk.addr_width = addr_width;
      reg_blk.data_width = data_width;
      reg_blk.be_width   = be_width;
      post_build_ral_settings(reg_blk);
      reg_blk.lock_model();
      ral_models[ral_model_name] = reg_blk;
      if (reg_blk.get_name() == ral_type_name) `downcast(ral, reg_blk)
    end

    if (!reg_blk.is_locked()) begin
      `uvm_fatal(`gfn, $sformatf("ral_models[%s] is not locked.", ral_model_name))
    end

    reg_blk.set_base_addr(.base_addr(0), .randomize_base_addr(1));
    ral_models[ral_model_name] = reg_blk;
  endfunction

  protected virtual function dv_base_reg_block create_ral_by_name(string name);
    uvm_object        obj;
    uvm_factory       factory;
    dv_base_reg_block ral_blk;

    factory = uvm_factory::get();
    obj = factory.create_object_by_name(.requested_type_name(name), .name(name));
    if (obj == null) begin
      factory.print();
      `uvm_fatal(`gfn,
                 $sformatf({"Could not create %0s as a RAL model. ",
                            "See above for a list of type/instance overrides"},
                           name))
    end
    if (!$cast(ral_blk, obj)) begin
      `uvm_fatal(`gfn, $sformatf("Cast failed - %0s is not a dv_base_reg_block", name))
    end
    return ral_blk;
  endfunction

  virtual function void initialize();
% if has_ral:
    initialize_ral(bus_params_pkg::BUS_AW, bus_params_pkg::BUS_DW, bus_params_pkg::BUS_DBW);
% else:
    is_initialized = 1'b1;
% endif
% for agent in env_agents:
    // create ${agent} agent config obj
    m_${agent}_agent_cfg = ${agent}_agent_cfg::type_id::create("m_${agent}_agent_cfg");
% endfor
  endfunction

endclass
