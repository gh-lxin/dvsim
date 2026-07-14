// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_vseq.
class ${name}_base_vseq extends uvm_sequence;
  `uvm_object_utils(${name}_base_vseq)
  `uvm_declare_p_sequencer(${name}_virtual_sequencer)

  rand uint num_trans;

  constraint num_trans_c {
    num_trans inside {[1:20]};
  }

  ${name}_env_cfg cfg;
  ${name}_reg_block ral;
  ${name}_env_cov cov;

  bit do_dut_init       = 1'b1;
  bit do_apply_reset    = 1'b1;
  bit do_wait_for_reset = 1'b0;
  bit do_dut_shutdown   = 1'b1;
  bit enable_asserts_in_hw_reset_rand_wr = 1'b1;

  // various knobs to enable certain routines
  bit do_${name}_init = 1'b1;

  `uvm_object_new

  virtual function void set_handles();
    `DV_CHECK_NE_FATAL(p_sequencer, null, "Did you forget to call `set_sequencer()`?")
    cfg = p_sequencer.cfg;
    cov = p_sequencer.cov;
    ral = cfg.ral;
  endfunction

  virtual function void configure_vseq();
  endfunction

  function void pre_randomize();
    if (cfg == null) set_handles();
    configure_vseq();
  endfunction

  task pre_start();
    super.pre_start();
    if (cfg == null) set_handles();
    if (do_dut_init) dut_init("HARD");
    num_trans.rand_mode(0);
  endtask

  task post_start();
    super.post_start();
    if (do_dut_shutdown) dut_shutdown();
  endtask

  virtual task dut_init(string reset_kind = "HARD");
    if (do_apply_reset) begin
      apply_reset(reset_kind);
      post_apply_reset(reset_kind);
    end else if (do_wait_for_reset) wait_for_reset(reset_kind);
    #1ps;
    if (do_${name}_init) ${name}_init();
  endtask

  virtual task apply_reset(string kind = "HARD");
    if (kind == "HARD") begin
      if (cfg.clk_rst_vifs.size() > 0) begin
        fork
          begin : isolation_fork
            foreach (cfg.clk_rst_vifs[i]) begin
              automatic string ral_name = i;
              fork
                cfg.clk_rst_vifs[ral_name].apply_reset();
              join_none
            end
            wait fork;
          end : isolation_fork
        join
      end else begin
        cfg.clk_rst_vif.apply_reset();
      end
    end
  endtask

  virtual task apply_resets_concurrently(int reset_duration_ps = 0);
    int slowest_clk_period_ps = 0;
    int reset_duration_from_clks_ps;

    if (cfg.clk_rst_vifs.size() > 0) begin
      foreach (cfg.clk_rst_vifs[i]) begin
        slowest_clk_period_ps = max2(slowest_clk_period_ps, cfg.clk_rst_vifs[i].clk_period_ps);
      end
    end else begin
      slowest_clk_period_ps = cfg.clk_rst_vif.clk_period_ps;
    end

    reset_duration_from_clks_ps = $urandom_range(2, 10) * slowest_clk_period_ps;
    reset_duration_ps = max2(reset_duration_ps, reset_duration_from_clks_ps);

    if (cfg.clk_rst_vifs.size() > 0) begin
      foreach (cfg.clk_rst_vifs[i]) cfg.clk_rst_vifs[i].drive_rst_pin(0);
      #(reset_duration_ps * 1ps);
      foreach (cfg.clk_rst_vifs[i]) cfg.clk_rst_vifs[i].drive_rst_pin(1);
    end else begin
      cfg.clk_rst_vif.drive_rst_pin(0);
      #(reset_duration_ps * 1ps);
      cfg.clk_rst_vif.drive_rst_pin(1);
    end
  endtask

  virtual task post_apply_reset(string reset_kind = "HARD");
  endtask

  virtual task wait_for_reset(string reset_kind     = "HARD",
                              bit wait_for_assert   = 1,
                              bit wait_for_deassert = 1);
    if (wait_for_assert) begin
      `uvm_info(`gfn, "waiting for rst_n assertion...", UVM_MEDIUM)
      @(negedge cfg.clk_rst_vif.rst_n);
    end
    if (wait_for_deassert) begin
      `uvm_info(`gfn, "waiting for rst_n de-assertion...", UVM_MEDIUM)
      @(posedge cfg.clk_rst_vif.rst_n);
    end
    `uvm_info(`gfn, "wait_for_reset done", UVM_HIGH)
  endtask

  virtual task dut_shutdown();
    csr_utils_pkg::wait_no_outstanding_access();
    // check for pending ${name} operations and wait for them to complete
    // TODO
  endtask

  virtual task ${name}_init();
    `uvm_error(`gfn, "FIXME")
  endtask

  virtual task run_csr_vseq_wrapper(int num_times = 1, dv_base_reg_block models[$] = {});
    string csr_test_type;

    if (models.size() == 0) begin
      `DV_CHECK_GE_FATAL(cfg.ral_models.size(), 1)
    end

    void'($value$plusargs("csr_%0s", csr_test_type));

    for (int i = 1; i <= num_times; i++) begin
      `uvm_info(`gfn, $sformatf("Running csr %0s vseq iteration %0d/%0d.",
                                csr_test_type, i, num_times), UVM_LOW)
      run_csr_vseq(.csr_test_type(csr_test_type), .models(models));
    end
  endtask

  virtual task run_csr_vseq(string csr_test_type,
                            int    num_test_csrs = 0,
                            bit    do_rand_wr_and_reset = 1,
                            dv_base_reg_block models[$] = {},
                            string ral_name = "");
    csr_base_seq m_csr_seq;

    `DV_CHECK_GE_FATAL(cfg.ral_models.size(), 1)

    if (models.size() == 0) begin
      if (ral_name != "") begin
        `DV_CHECK_FATAL(cfg.ral_models.exists(ral_name))
        models.push_back(cfg.ral_models[ral_name]);
      end else begin
        foreach (cfg.ral_models[i]) models.push_back(cfg.ral_models[i]);
      end
    end

    case (csr_test_type)
      "hw_reset": csr_base_seq::type_id::set_type_override(csr_hw_reset_seq::get_type());
      "rw"      : csr_base_seq::type_id::set_type_override(csr_rw_seq::get_type());
      "bit_bash": csr_base_seq::type_id::set_type_override(csr_bit_bash_seq::get_type());
      "aliasing": csr_base_seq::type_id::set_type_override(csr_aliasing_seq::get_type());
      "mem_walk": csr_base_seq::type_id::set_type_override(csr_mem_walk_seq::get_type());
      default   : `uvm_fatal(`gfn, $sformatf("specified opt is invalid: +csr_%0s", csr_test_type))
    endcase

    foreach (models[i]) begin
      csr_excl_item csr_excl = csr_utils_pkg::get_excl_item(models[i]);
      if (csr_excl != null) csr_excl.print_exclusions();
    end

    if (csr_test_type == "hw_reset" && do_rand_wr_and_reset) begin
      string        reset_type = "HARD";
      csr_write_seq m_csr_write_seq;

      if (!enable_asserts_in_hw_reset_rand_wr) begin
        `DV_ASSERT_CTRL_REQ("dut_assert_en", 1'b0)
      end

      m_csr_write_seq = csr_write_seq::type_id::create("m_csr_write_seq");
      m_csr_write_seq.models = models;
      m_csr_write_seq.external_checker = cfg.en_scb;
      m_csr_write_seq.en_rand_backdoor_write = 1'b1;
      m_csr_write_seq.start(null);

      dut_shutdown();
      void'($value$plusargs("do_reset=%0s", reset_type));
      dut_init(reset_type);
      if (!enable_asserts_in_hw_reset_rand_wr) begin
        `DV_ASSERT_CTRL_REQ("dut_assert_en", 1'b1)
      end
    end

    m_csr_seq = csr_base_seq::type_id::create("m_csr_seq");
    m_csr_seq.models = models;
    m_csr_seq.external_checker = cfg.en_scb;
    m_csr_seq.max_num_test_csrs = num_test_csrs;
    m_csr_seq.start(null);
  endtask

  virtual function void set_csr_assert_en(bit enable, string path = "*");
    uvm_config_db#(bit)::set(null, path, "csr_assert_en", enable);
  endfunction

  virtual function uvm_sequence create_seq_by_name(string name);
    return dv_utils_pkg::create_seq_by_name(name);
  endfunction

endclass : ${name}_base_vseq
