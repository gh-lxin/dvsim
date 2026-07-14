// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inlined from dv_base_virtual_sequencer.
class ${name}_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(${name}_virtual_sequencer)

  ${name}_env_cfg cfg;
  ${name}_env_cov cov;

  // Dynamic associative array to store sub-sequencers
  uvm_sequencer_base sub_sequencers[string];

% for agent in env_agents:
  ${agent}_sequencer ${agent}_sequencer_h;
% endfor

  `uvm_component_new

  function void register_sequencer(string name, uvm_sequencer_base sequencer);
    `DV_CHECK_FATAL(!sub_sequencers.exists(name))
    sub_sequencers[name] = sequencer;
  endfunction

  function uvm_sequencer_base get_sequencer(string name);
    `DV_CHECK_FATAL(sub_sequencers.exists(name))
    return sub_sequencers[name];
  endfunction

endclass
