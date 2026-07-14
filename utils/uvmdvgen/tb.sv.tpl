// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
module tb;
  // dep packages
  import uvm_pkg::*;
  import dv_utils_pkg::*;
  import ${name}_env_pkg::*;
  import ${name}_test_pkg::*;

  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  wire clk, rst_n;
% if has_interrupts:
  wire [NUM_MAX_INTERRUPTS-1:0] interrupts;
% endif

  // interfaces
  clk_rst_if clk_rst_if(.clk(clk), .rst_n(rst_n));
% if has_interrupts:
  pins_if #(NUM_MAX_INTERRUPTS) intr_if(interrupts);
% endif
% for agent in env_agents:
  ${agent}_if ${agent}_if();
% endfor

% if has_alerts:
  `DV_ALERT_IF_CONNECT()
% endif
% if num_edn:
  // edn_clk, edn_rst_n and edn_if are defined and driven in below macro
  `DV_EDN_IF_CONNECT
% endif

  // dut
  ${name} dut (
    .clk_i (clk)
    // TODO: add remaining IOs and hook them
  );

  initial begin
    // drive clk and rst_n from clk_if
    clk_rst_if.set_active();
    uvm_config_db#(virtual clk_rst_if)::set(null, "*.env", "clk_rst_vif", clk_rst_if);
% if has_interrupts:
    uvm_config_db#(intr_vif)::set(null, "*.env", "intr_vif", intr_if);
% endif
% for agent in env_agents:
    uvm_config_db#(virtual ${agent}_if)::set(null, "*.env.m_${agent}_agent*", "vif", ${agent}_if);
% endfor
    $timeformat(-12, 0, " ps", 12);
    run_test();
  end

endmodule
