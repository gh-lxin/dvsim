// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package ${name}_agent_pkg;
  // dep packages
  import uvm_pkg::*;
  import dv_utils_pkg::*;

  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // parameters

  // local types
  // forward declare classes to allow typedefs below
  typedef class ${name}_item;
  typedef class ${name}_agent_cfg;

  // functions

  // package sources
  `include "${name}_item.sv"
  `include "${name}_agent_cfg.sv"
  `include "${name}_agent_cov.sv"
  `include "${name}_sequencer.sv"
  `include "${name}_driver.sv"
% if has_separate_host_device_driver:
  `include "${name}_host_driver.sv"
  `include "${name}_device_driver.sv"
% endif
  `include "${name}_monitor.sv"
  `include "${name}_agent.sv"
  `include "${name}_seq_list.sv"

endpackage: ${name}_agent_pkg
