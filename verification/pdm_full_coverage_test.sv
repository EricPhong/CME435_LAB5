/* Eric Phong, rfp479, CME435, 11344905, Lab5 */
`ifndef PDM_FULL_COVERAGE_TEST_SV
`define PDM_FULL_COVERAGE_TEST_SV

//------------------------------------------------------------------------------
// Test: pdm_full_coverage_test
//
// Intent: one run that closes the required coverage (dest, length, dest x len)
// and exercises the predictor/scoreboard on every port/length combination.
//   Phase 1: directed sweep, 4 ports x 4 lengths   -> cx_dest_len = 100%
//   Phase 2: payload corners (0x00, 0xFF, 55/AA)    -> byte zero/max bins
//   Phase 3: constrained random traffic             -> port transitions,
//            ACK latency and PROCEED delay spread
//   Phase 4: reset between and during packets       -> scoreboard flush path
// Use this test for the coverage screenshot in the report.
//------------------------------------------------------------------------------
class pdm_full_coverage_test extends pdm_test_base;
  `uvm_component_utils(pdm_full_coverage_test)

  function new(string name = "pdm_full_coverage_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual task run_phase(uvm_phase phase);
    pdm_pkt_len_seq        len_seq;
    pdm_payload_corner_seq corner_seq;
    pdm_random_traffic_seq rand_seq;
    pdm_reset_traffic_seq  rst_seq;

    phase.raise_objection(this);
    start_downstream_reactive_vseq();

    if (env_cfg.upstream_cfg.vif.rst_b !== 1'b1)
      @(posedge env_cfg.upstream_cfg.vif.rst_b);
    repeat (5) @(posedge env_cfg.upstream_cfg.vif.clk);

    `uvm_info(get_type_name(), "--- Phase 1: directed sweep of all 16 port x length combinations ---", UVM_LOW)
    len_seq = pdm_pkt_len_seq::type_id::create("len_seq");
    if (!len_seq.randomize() with { mode == pdm_pkt_len_seq::SWEEP_ALL; })
      `uvm_fatal("TESTRAND", "Failed to randomize sweep sequence")
    len_seq.start(env_cfg.upstream_cfg.sqr_h);

    `uvm_info(get_type_name(), "--- Phase 2: payload value corners on every port ---", UVM_LOW)
    corner_seq = pdm_payload_corner_seq::type_id::create("corner_seq");
    corner_seq.start(env_cfg.upstream_cfg.sqr_h);

    `uvm_info(get_type_name(), "--- Phase 3: 60 constrained-random packets ---", UVM_LOW)
    rand_seq = pdm_random_traffic_seq::type_id::create("rand_seq");
    if (!rand_seq.randomize() with { count == 60; })
      `uvm_fatal("TESTRAND", "Failed to randomize random traffic sequence")
    rand_seq.start(env_cfg.upstream_cfg.sqr_h);

    `uvm_info(get_type_name(), "--- Phase 4: resets between and during packets ---", UVM_LOW)
    rst_seq = pdm_reset_traffic_seq::type_id::create("rst_seq");
    if (!rst_seq.randomize() with { iterations == 2; })
      `uvm_fatal("TESTRAND", "Failed to randomize reset sequence")
    rst_seq.start(env_cfg.upstream_cfg.sqr_h);

    // Drain: let the last PROCEED/DATA_OUT handshakes finish before check_phase
    #1us;
    phase.drop_objection(this);
  endtask : run_phase

endclass : pdm_full_coverage_test

`endif // PDM_FULL_COVERAGE_TEST_SV
