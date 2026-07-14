// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_test.
class ${name}_base_test extends uvm_test;

  `uvm_component_utils(${name}_base_test)
  `uvm_component_new

  ${name}_env     env;
  ${name}_env_cfg cfg;
  bit             run_test_seq = 1'b1;
  string          test_seq_s;

  uint   max_quit_count  = 1;
  uint64 test_timeout_ns = 200_000_000; // 200ms
  uint   drain_time_ns   = 2_000;  // 2us
  bit    poll_for_stop   = 1'b0;
  uint   poll_for_stop_interval_ns = 1000;
  bit    print_topology  = 1'b0;

  virtual function void build_phase(uvm_phase phase);
    uvm_object_wrapper cfg_type;
    uvm_object         base_cfg;

    dv_report_server  m_dv_report_server = new();
    dv_report_catcher m_report_catcher;
    uvm_report_server::set_server(m_dv_report_server);

    `uvm_create_obj(dv_report_catcher, m_report_catcher)
    add_message_demotes(m_report_catcher);
    uvm_report_cb::add(null, m_report_catcher);

    super.build_phase(phase);

    env = ${name}_env::type_id::create("env", this);

    if (!uvm_config_db#(uvm_object_wrapper)::get(this, "env", "cfg_type", cfg_type)) begin
      cfg_type = ${name}_env_cfg::get_type();
    end

    if (!uvm_config_db#(${name}_env_cfg)::get(this, "env", "cfg", cfg)) begin
      base_cfg = cfg_type.create_object("cfg");
      if (!base_cfg) begin
        `uvm_fatal(`gfn, $sformatf("Failed to create object of type %p", cfg_type))
      end
      if (!$cast(cfg, base_cfg)) begin
        `uvm_fatal(`gfn,
                   $sformatf("Failed to cast object of type %p to expected CFG_T class.", cfg_type))
      end
      initialize_env_cfg();
    end

    `DV_CHECK_RANDOMIZE_FATAL(cfg)
    uvm_config_db#(${name}_env_cfg)::set(this, "env", "cfg", cfg);

    void'($value$plusargs("en_scb=%0b", cfg.en_scb));
    void'($value$plusargs("en_scb_mem_chk=%0b", cfg.en_scb_mem_chk));
    void'($value$plusargs("zero_delays=%0b", cfg.zero_delays));
    void'($value$plusargs("en_cov=%0b", cfg.en_cov));
    void'($value$plusargs("smoke_test=%0b", cfg.smoke_test));
    void'($value$plusargs("print_topology=%0b", print_topology));
    uvm_top.enable_print_topology = print_topology;
    void'($value$plusargs("cdc_instrumentation_enabled=%d", cfg.en_dv_cdc));

    uvm_config_db#(${name}_env_cfg)::set(this, "*", "cfg", cfg);
  endfunction : build_phase

  virtual function void initialize_env_cfg();
    cfg.initialize();
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    void'($value$plusargs("max_quit_count=%0d", max_quit_count));
    set_max_quit_count(max_quit_count);
    void'($value$plusargs("test_timeout_ns=%0d", test_timeout_ns));
    uvm_top.set_timeout((test_timeout_ns * 1ns));
  endfunction : end_of_elaboration_phase

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    void'($value$plusargs("drain_time_ns=%0d", drain_time_ns));
    phase.phase_done.set_drain_time(this, (drain_time_ns * 1ns));
    void'($value$plusargs("poll_for_stop=%0b", poll_for_stop));
    void'($value$plusargs("poll_for_stop_interval_ns=%0d", poll_for_stop_interval_ns));
    if (poll_for_stop) dv_utils_pkg::poll_for_stop(.interval_ns(poll_for_stop_interval_ns));
    void'($value$plusargs("UVM_TEST_SEQ=%0s", test_seq_s));
    if (run_test_seq) begin
      run_seq(test_seq_s, phase);
    end
  endtask : run_phase

  virtual function void add_message_demotes(dv_report_catcher catcher);
  endfunction

  virtual task run_seq(string test_seq_s, uvm_phase phase);
    uvm_sequence test_seq = dv_utils_pkg::create_seq_by_name(test_seq_s);

    configure_sequence(test_seq);
    `DV_CHECK_RANDOMIZE_FATAL(test_seq)

    `uvm_info(`gfn, {"Starting test sequence ", test_seq_s}, UVM_MEDIUM)
    phase.raise_objection(this, $sformatf("%s objection raised", `gn));
    test_seq.start(env.virtual_sequencer);
    phase.drop_objection(this, $sformatf("%s objection dropped", `gn));
    `uvm_info(`gfn, {"Finished test sequence ", test_seq_s}, UVM_MEDIUM)
  endtask

  virtual function void configure_sequence(uvm_sequence seq);
    seq.set_sequencer(env.virtual_sequencer);
  endfunction

endclass : ${name}_base_test
