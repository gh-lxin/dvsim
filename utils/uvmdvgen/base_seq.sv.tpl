// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_seq.

class ${name}_base_seq extends uvm_sequence#(${name}_item);
  `uvm_object_utils(${name}_base_seq)
  `uvm_declare_p_sequencer(${name}_sequencer)

  ${name}_agent_cfg cfg;

  `uvm_object_new

  task pre_start();
    super.pre_start();
    cfg = p_sequencer.cfg;
  endtask

  virtual task body();
    `uvm_fatal(`gtn, "Need to override this when you extend from this class!")
  endtask

endclass
