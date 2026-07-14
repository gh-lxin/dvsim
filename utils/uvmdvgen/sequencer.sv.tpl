// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_sequencer.

class ${name}_sequencer extends uvm_sequencer #(.REQ(${name}_item), .RSP(${name}_item));
  `uvm_component_utils(${name}_sequencer)

  ${name}_agent_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass
