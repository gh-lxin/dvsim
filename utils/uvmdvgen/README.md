# Uvmdvgen: Initial testbench auto-generation tool

`uvmdvgen` is a Python based tool to generate the boilerplate code for a UVM
agent as well as the complete UVM testbench for a given DUT. The tool generates
all the relevant UVM-based classes including the package and the fusesoc core
file to make it quickly plug-and-playable. The packages import the standard
utility and library packages wherever applicable, to conform to our existing
methodology and style.

When starting with a new DV effort, the user typically goes through a copy-paste
exercise to replicate an existing UVM testbench code to the current one and has
to go through several debug cycles to get it working. This tool aims to
eliminate that. Also, as a part of our
[DV methodology](../../doc/contributing/dv/methodology/README.md#code-reuse),
we provide utilities and base class structures that contain several
pieces of common code which can be reused when setting up a new DV environment.

### Help switch (-h)
Running the tool with `-h` switch provides a brief description of all available
switches.
```console
$ util/uvmdvgen.py -h
usage: uvmdvgen.py [-h] [-a] [-s] [-e] [-hr] [-hi] [-ha] [-ne NUM_EDN]
                   [-ea agt1 agt2 [agt1 agt2 ...]] [-ao [hw/dv/sv]]
                   [-eo [hw/ip/<ip>]] [-v VENDOR]
                   [ip/block name]

Command-line tool to autogenerate boilerplate DV testbench code with inlined dv_base_* templates

positional arguments:
  [ip/block name]       Name of the ip/block for which the UVM TB is being
                        auto-generated

optional arguments:
  -h, --help            show this help message and exit
  -a, --gen-agent       Generate UVM agent code extended from DV library
  -s, --has-separate-host-device-driver
                        IP / block agent creates a separate driver for host
                        and device modes. (ignored if -a switch is not passed)
  -e, --gen-env         Generate testbench UVM env code
  -hr, --has-ral        Specify whether the DUT has CSRs and thus needs a UVM
                        RAL model.
  -hi, --has-interrupts
                        Create interrupts interface in tb
  -ha, --has-alerts     Create alerts interface in tb
  -ne NUM_EDN, --num-edn NUM_EDN
                        Create edn pull interface in tb
  -ea agt1 agt2 [agt1 agt2 ...], --env-agents agt1 agt2 [agt1 agt2 ...]
                        Env creates an interface agent specified here. They
                        are assumed to already exist. Note that the list is
                        space-separated, and not comma-separated. (ignored if
                        -e switch is not passed)
  -ao [hw/dv/sv], --agent-outdir [hw/dv/sv]
                        Path to place the agent code. A directory called
                        <name>_agent is created at this location. (default set
                        to './<name>')
  -eo [hw/ip/<ip>], --env-outdir [hw/ip/<ip>]
                        Path to place the full testbench code. It creates 3
                        directories - dv, data and doc. The DV document and the
                        testplan Hjson files are placed in the doc and data
                        directories respectively. These are to be merged into
                        the IP's root directory (with the existing data and
                        doc directories). Under dv, it creates 3 sub-
                        directories - env, tb and tests to place all of the
                        testbench sources. (default set to './<name>')
  -v VENDOR, --vendor VENDOR
                        Name of the vendor / entity developing the testbench.
                        This is used to set the VLNV of the FuesSoC core
                        files.
```

### Generating UVM agent
The boilerplate code for a UVM agent for an interface can be generated using the
`-a` switch. This results in the generation of complete agent with classes that
extend from inlined `dv_base_*` templates (see `dvsim/dv_libs/`). Please see
that description for more details.

The tool generates an interface, item, cfg, cov, monitor, driver and sequence
library classes. Let's take `jtag` as the argument passed for the name of the
IP. The following describes their contents in each source generated:
* `jtag_if`

    This is an empty shell of an interface. User is required to add content.

* `jtag_item`

    This is an empty transaction packet extended from `uvm_sequence_item`.

* `jtag_agent_cfg`

    This is the agent configuration object, it contains the virtual interface
    handle for `jtag_if` and is called `vif`.

* `jtag_agent_cov`

    This is a coverage component inlined from `dv_base_agent_cov`.

* `jtag_monitor`

    This is the monitor component inlined from `dv_base_monitor`. It provides
    the following items:

    * `virtual protected task collect_trans()`

        This is a shell task within which user is required to add logic to detect
        an event, sample the interface and create a transaction object and write
        to the analysis port. This task is called in `dv_base_monitor::run_phase`.

* `jtag_driver`

    This is the driver component inlined from `dv_base_driver`. It provides the
    following items:

    * `virtual task reset_signals()`

        This task is for resetting the initial value of the `vif` signals.

    * `virtual task get_and_drive()`

        This task is used to get the next item from the sequencer, apply it to the
        interface and return the response back. This is again, an empty task at the
        moment.

    If the `-s` switch is passed, the tool creates `jtag_host_driver` and
    `jtag_device_driver` instead, and their contents are exactly the same.

* `seq_lib/jtag_base_seq`

    This is inlined from `dv_base_seq`.

* `seq_lib/jtag_seq_list`

    This is a list of sequences included in one place.

* `jtag_agent_pkg`

    This is the package file that includes all of the above sources and the
    imports the dependent packages.

* `jtag_agent.core`

    This is the fusesoc core file that is used to generate the filelist for
    the build.

The tool generates dedicated `jtag_sequencer` and `jtag_agent` classes with
`dv_base_*` logic inlined (see `agent.sv.tpl`).

### Generating UVM environment & testbench
The boilerplate code for a UVM environment and the testbench for a DUT can be
generated using the `-e` switch. Generated classes inline `dv_base_*` logic
from templates. With `-ea` switch, user can provide a list of downstream agents
to create within the environment.

The tool generates not only the UVM environment, but also the base test,
testbench, top level fusesoc core file with sim target, Makefile that already
includes the smoke and CSR test suite and more. With just a few tweaks, this
enables the user to reach the V1 stage much quicker.  Let's take `i2c_host`
as the argument passed for the name of the IP. The following is the list of
files generated with a brief description of their contents:

Switches to indicate whether the DUT contains interrupts or alerts are
provided by `-hi` and `-ha` respectively. By default, these are set to 'False'
(don't create interrupts or alerts). When set, it will create `intr_if` and
alert interfaces in the testbench and set them into `uvm_config_db`.
* `env/i2c_host_env_cfg`

    This is the env cfg object. It creates the downstream agent cfg objects that
    were passed using the `-ea` switch in the `initialize()` function which is
    called in the `dv_base_test::build_phase()`. Since the cfg handle is passed to
    all env components, those downstream agent cfg objects can be hierarchically
    referenced.

* `env/i2c_host_env_cov`

    This is the coverage component class. A handle of this class is passed to the
    scoreboard and the virtual sequencer so that covergroups can be sampled in the
    scoreboard as well as sequences.

* `env/i2c_host_reg_block`

    This is the UVM reg based RAL model. This is created for completeness. The
    actual RAL model needs to be generated prior to running simulations using the
    [regtool](../reggen/doc/setup_and_use.md).

* `env/i2c_host_scoreboard`

    This is the scoreboard component that already creates the analysis FIFOs and
    queues for the agents passed via `-ea` switch. It adds starter tasks for
    processing each fifo in a forever loop and invokes them in the `run_phase`
    using `fork-join` statement.

* `env/i2c_host_virtual_sequencer`

    This is the virtual sequencer used by all test sequences to run the traffic.
    It adds handles to downstream agent sequencers passed via `-ea` switch.
    Sub-sequences can be started on them via the `p_sequencer` handle.

* `env/seq_lib/i2c_host_base_vseq`

    This is the base virtual sequence that user can use to add common tasks,
    functions and variables that other extended test sequences can reuse. For
    starters, it provides the `i2c_host_init()` task and `do_i2c_host_init` knob
    for controllability.

* `env/seq_lib/i2c_host_smoke_vseq`

    This is the smoke test sequence that user needs to develop as the first
    test sequence. It extends from `i2c_host_base_vseq`.

* `env/seq_lib/i2c_host_csr_vseq`

    This is the test sequence for the entire CSR suite of tests. It calls
    `dv_base_vseq::run_csr_vseq_wrapper()` task which is a complete test sequence.
    All the user needs to do is run the CSR tests and add exclusions if needed
    using the `add_csr_exclusions()` function provided.

* `env/seq_lib/i2c_host_vseq_list`

    This is a list of test sequences included in one place.

* `env/i2c_host_env`

    This is the env class that creates the downstream agents passed via `-ea`
    switch. It sets their corresponding cfg objects (which are members of env cfg
    object) into the `uvm_config_db`. It also makes the analysis port connections
    in the `connect_phase` and sets the sequencer handles in the virtual
    sequencer.

* `env/i2c_host_env_pkg`

    This is the env pkg file which includes all env classes and imports the
    dependent packages.

* `env/i2c_host_env.core`

    This is the fusesoc core file for the env pkg compile unit.

* `tests/i2c_host_base_test`

    This is the base test class. The base test class it extends from already
    creates the `env` and `cfg` objects, which are available for manipulation in
    UVM phases. This class's name would be supplied to UVM_TESTNAME plusarg to run
    tests using the UVM methodology.

* `tests/i2c_host_test_pkg`

    This is the test pkg file which includes all test classes and imports the
    dependent packages.

* `tests/i2c_host_test.core`

    This is the fusesoc core file for the test pkg compile unit.

* `tb/i2c_host_bind`

    This is the assertion bind file that is compiled along with the testbench in a
    multi-top architecture.

* `tb/tb`

    This is the top level testbench module that instantiates the DUT along with
    some of the interfaces that are required to be instantiated and connected and
    passed on the `uvm_config_db`. The user needs to look through the RTL and make additional
    connections as needed.

* `i2c_host_sim.core`

    This is the top level fusesoc core file with the sim target. It adds the RTL
    and DV dependencies to construct the complete filelist to pass to simulator's
    build step.

* `i2c_host_dv_doc.md`

  This is the initial DV document that will describe the entire testbench. This
  is equivalent to the template available [here](https://github.com/lowRISC/opentitan/blob/master/hw/dv/doc/dv_doc_template.md).

The [VLNV](https://fusesoc.readthedocs.io/en/stable/user/build_system/core_files.html#naming-the-core-file)
name in the generated FuseSoC core files is set using the `--vendor` switch for
the 'vendor' field. By default, it is set to "lowrisc". It can be overridden
by supplying the `--vendor <vendor-name>` switch on the command line.

#### Examples
```console
$ util/uvmdvgen.py i2c -a
```
This will create `./i2c/i2c_agent` and place all sources there.

```console
$ util/uvmdvgen.py jtag -a -ao hw/dv/sv
```
This will create `hw/dv/sv/jtag_agent` directory and place all the sources
there.

```console
$ util/uvmdvgen.py i2c -a -s -ao hw/dv/sv
```
This will create the I2C agent with separate 'host' mode and 'device' mode drivers.

```console
$ util/uvmdvgen.py i2c_host -e -hi -hr -ea i2c -eo hw/ip/i2c_host/dv
```
This will create the complete `i2c_host` DV testbench and will instantiate
`i2c_agent`. It will also create and hook up the interrupt interface in the
testbench.

```console
$ util/uvmdvgen.py foo -e -hi -ha -hr -ea foo -eo hw/ip/foo/dv
```
This will create the complete foo DV testbench and will instantiate `foo_agent`.
It will also create and hook up the interrupt and alerts interfaces in the
testbench.

```console
$ util/uvmdvgen.py aes -e -hr -ea i2c -eo hw/ip/aes/dv
```
This will create the complete aes DV testbench and will instantiate `i2c_agent`.

```console
$ util/uvmdvgen.py dma -e -eo hw/ip/dma/dv
```
This will create the complete dma DV testbench. It does not
instantiate any downstream agents due to absence of `-ea` switch.

```console
$ util/uvmdvgen.py chip -e -ea uart i2c jtag -eo hw/top_earlgrey/dv
```
This will create the complete chip testbench and will instantiate
`uart_agent`, `i2c_agent` and `jtag_agent` in the env.
