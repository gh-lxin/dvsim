// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
{
  // Name of the sim cfg - typically same as the name of the DUT.
  name: ${name}

  // Top level dut name (sv module).
  dut: ${name}

  // Top level testbench name (sv module).
  tb: tb

  // Simulator used to sign off this block
  tool: vcs

  // Fusesoc core file used for building the file list.
  //fusesoc_core: ${vendor}:dv:${name}_sim:0.1
  //TODO: provide  TB flistlist...
  sv_flist: "xx1/xx2/xx3/design.f"
  // Testplan hjson file.
  //testplan: "{proj_root}/hw/ip/${name}/data/${name}_testplan.hjson"

% if has_ral:
  // RAL spec - used to generate the RAL model.
  ral_spec: "{proj_root}/hw/ip/${name}/data/${name}.hjson"
% endif

  // Import additional common sim cfg files.
  import_cfgs: [// Project wide common sim cfg file
                "{dvsim_root}/tools/dvsim/common_sim_cfg.hjson"
  ]

  // Add additional tops for simulation.
  sim_tops: ["${name}_bind"]

  // Default iterations for all tests - each test entry can override this.
  reseed: 1

  // Default UVM test and seq class name.
  uvm_test: ${name}_base_test
  uvm_test_seq: ${name}_base_vseq

  // List of test specifications.
  tests: [
    {
      name: ${name}_smoke
      uvm_test_seq: ${name}_smoke_vseq
    }

    // TODO: add more tests here
  ]

  // List of regressions.
  regressions: [
    {
      name: smoke
      tests: ["${name}_smoke"]
    }
  ]
}
