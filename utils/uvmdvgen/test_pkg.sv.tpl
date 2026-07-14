// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package ${name}_test_pkg;
  // dep packages
  import uvm_pkg::*;
  import dv_utils_pkg::*;
  import ${name}_env_pkg::*;

  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // package sources
  `include "${name}_base_test.sv"

endpackage
