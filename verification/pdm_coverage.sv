/* Eric Phong, rfp479, CME435, 11344905, Lab5 */

// Two inputs (upstream packets and downstream completed packets)
`uvm_analysis_imp_decl(_up)
`uvm_analysis_imp_decl(_dn)

//------------------------------------------------------------------------------
// Class: pdm_coverage
//
// Functional coverage collector. Samples OBSERVED behaviour from the monitors
// (not the sequence's intent).
//
// Required by the lab:
//   1. Destination ports         -> cg_upstream.cp_dest
//   2. Packet length             -> cg_upstream.cp_len
//   3. Destination x length      -> cg_upstream.cx_dest_len (16 bins)
// Additional:
//   * Port-to-port transitions (same port twice / switch ports)
//   * ACK latency 1..4 cycles (measured by the upstream monitor)
//   * Payload byte value classes (0x00, 0xFF, low, mid, high)
//   * Output port x output length (what the DUT actually produced)
//   * Measured PROCEED delay 1..4, and port x delay
//------------------------------------------------------------------------------
class pdm_coverage extends uvm_component;
  `uvm_component_utils(pdm_coverage)

  uvm_analysis_imp_up #(upstream_seq_item,   pdm_coverage) up_imp;
  uvm_analysis_imp_dn #(downstream_seq_item, pdm_coverage) dn_imp;

  //----------------------------------------------------------------------------
  // Input side: one sample per packet observed on the upstream bus
  //----------------------------------------------------------------------------
  covergroup cg_upstream with function sample(upstream_seq_item t);
    option.per_instance = 1;
    option.comment      = "PDM input packets";

    // bins port[] -> 4 separate bins (one per port). An explicit invalid bin
    // (it DOES count) proves negative tests ran; it is excluded from the cross.
    cp_dest : coverpoint t.destination {
      bins port[]  = {[1:4]};
      // bins invalid = {0, [5:255]};
    }

    // Same expression, transitions only (kept separate so the cross is not
    // multiplied by transition bins). 16 bins: 1=>1, 1=>2, ... 4=>4
    cp_dest_trans : coverpoint t.destination {
      bins trans[] = ([1:4] => [1:4]);
    }

    // bins len[] -> 4 bins. "default" catches illegal sizes but does not count.
    cp_len : coverpoint t.data_len {
      bins len[]  = {4, 8, 12, 16};
      bins others = default;
    }

    // Required cross: 4 ports x 4 lengths = 16 bins. Every combination is
    // legal per the spec, so nothing is ignored except the invalid dest bin.
    cx_dest_len : cross cp_dest, cp_len {
      // ignore_bins no_invalid = binsof(cp_dest.invalid);
    }

    // Spec: ACK 1..4 cycles after the terminating BND_PLSE.
    // A late ACK is already a monitor error, so it is not a coverage goal.
    cp_ack_latency : coverpoint t.ack_latency {
      bins lat[]        = {[1:4]};
      ignore_bins late  = {[5:$]};
    }
  endgroup : cg_upstream

  //----------------------------------------------------------------------------
  // Payload values: one sample per byte
  //----------------------------------------------------------------------------
  covergroup cg_payload_byte with function sample(bit [7:0] b);
    option.per_instance = 1;
    cp_byte : coverpoint b {
      bins zero = {8'h00};
      // bins min_plus_1 = {8'h01};
      bins low  = {[8'h01:8'h54]};
      bins mid  = {[8'h55:8'hAA]};
      bins high = {[8'hAB:8'hFE]};
      // bins max_minus_1 = {8'hFE};
      bins max  = {8'hFF};
    }
  endgroup : cg_payload_byte

  //----------------------------------------------------------------------------
  // Output side: one sample per completed packet on DATA_OUT_x
  //----------------------------------------------------------------------------
  covergroup cg_downstream with function sample(downstream_seq_item t);
    option.per_instance = 1;
    option.comment      = "PDM output packets";

    cp_port : coverpoint t.port_id {          // index 0..3 = DATA_OUT_1..4
      bins port[] = {[0:3]};
    }
    cp_len : coverpoint t.newdata_len {
      bins len[] = {4, 8, 12, 16};
    }
    cx_port_len : cross cp_port, cp_len;

    // Measured on the bus by the downstream monitor (not the requested delay)
    cp_proceed_delay : coverpoint t.meas_proceed_delay {
      bins dly[] = {[1:4]};
    }
    cx_port_delay : cross cp_port, cp_proceed_delay;
  endgroup : cg_downstream

  // Embedded covergroups may ONLY be constructed in the class constructor
  function new(string name = "pdm_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_upstream     = new();
    cg_payload_byte = new();
    cg_downstream   = new();
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    up_imp = new("up_imp", this);
    dn_imp = new("dn_imp", this);
  endfunction : build_phase

  function void write_up(upstream_seq_item t);
    if (t.operation != upstream_seq_item::DATA_TRANSFER) return;
    cg_upstream.sample(t);
    foreach (t.data[i]) cg_payload_byte.sample(t.data[i]);
  endfunction : write_up

  function void write_dn(downstream_seq_item t);
    if (t.kind != downstream_seq_item::RSP) return;
    cg_downstream.sample(t);
  endfunction : write_dn

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    $display("\n---------------------- COVERAGE SUMMARY ----------------------");
    $display("  cg_upstream     : %6.2f %%", cg_upstream.get_inst_coverage());
    $display("    dest          : %6.2f %%", cg_upstream.cp_dest.get_inst_coverage());
    $display("    length        : %6.2f %%", cg_upstream.cp_len.get_inst_coverage());
    $display("    dest x length : %6.2f %%", cg_upstream.cx_dest_len.get_inst_coverage());
    $display("  cg_payload_byte : %6.2f %%", cg_payload_byte.get_inst_coverage());
    $display("  cg_downstream   : %6.2f %%", cg_downstream.get_inst_coverage());
    $display("--------------------------------------------------------------\n");
  endfunction : report_phase

endclass : pdm_coverage
