/* Eric Phong, rfp479, CME435, 11344905, Lab5 */

// Two inputs -> two write functions. These macros (package scope) create the
// classes uvm_analysis_imp_exp / uvm_analysis_imp_act, which call
// write_exp() / write_act() on this scoreboard.
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

//------------------------------------------------------------------------------
// Class: pdm_scoreboard
//
// In-order comparator with one FIFO of expected packets per output port.
//   write_exp : predictor -> push_back onto exp_q[port_id]
//   write_act : downstream monitor (all 4 ports share this imp; port_id says
//               which queue) -> empty queue = UNEXPECTED, else pop_front and
//               compare = MATCH / MISMATCH
//   check_phase : anything left in a queue = MISSING
//
// Why 4 queues and not 1: each port drains on its own PROCEED_x timing, so the
// spec only guarantees order WITHIN a port. A packet sent later to another port
// may legally come out first.
//
// Why pop_front and not a search: the spec says DATA_OUT_x carries packets in
// the order received. Searching would hide a dropped or reordered packet.
//
// Ordering note: the expected item always arrives first. The upstream monitor
// broadcasts at ACK (<= 4 cycles after the last byte, or 5 on timeout), while
// the earliest downstream completion is NEWDATA(+1) + PROCEED(+1) + 4 bytes.
//
// Reset (spec: async reset clears the internal buffer and drives outputs low):
//   Every packet inside the DUT is lost, so on reset ALL expected queues are
//   flushed and counted in n_flushed. Any packet that still appears after the
//   reset arrives at an empty queue -> UNEXPECTED, i.e. stale data leaked
//   through, which would be a DUT bug against the spec.
//   Partial output packets are discarded by the downstream monitor (its thread
//   is killed on reset), so they never reach write_act.
//------------------------------------------------------------------------------
class pdm_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(pdm_scoreboard)

  uvm_analysis_imp_exp #(downstream_seq_item, pdm_scoreboard) exp_imp;
  uvm_analysis_imp_act #(downstream_seq_item, pdm_scoreboard) act_imp;

  // exp_q[port_idx] : expected packets for DATA_OUT_(port_idx+1)
  downstream_seq_item exp_q[4][$];

  uvm_event reset_event;   // triggered by the upstream monitor on negedge rst_b

  // Statistics
  int unsigned n_expected   = 0;
  int unsigned n_match      = 0;
  int unsigned n_mismatch   = 0;
  int unsigned n_unexpected = 0;
  int unsigned n_missing    = 0;
  int unsigned n_flushed    = 0;
  int unsigned n_resets     = 0;

  function new(string name = "pdm_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    exp_imp     = new("exp_imp", this);
    act_imp     = new("act_imp", this);
    reset_event = uvm_event_pool::get_global("pdm_reset_event");
  endfunction : build_phase

  //----------------------------------------------------------------------------
  // Expected packet from the predictor
  //----------------------------------------------------------------------------
  function void write_exp(downstream_seq_item t);
    if (t.port_id > 3) begin
      `uvm_error("SB_PORT", $sformatf("Expected item with illegal port_id %0d", t.port_id))
      return;
    end
    exp_q[t.port_id].push_back(t);
    n_expected++;
  endfunction : write_exp

  //----------------------------------------------------------------------------
  // Actual packet observed on a DUT output port
  //----------------------------------------------------------------------------
  function void write_act(downstream_seq_item t);
    downstream_seq_item exp;
    string diff;

    if (t.kind != downstream_seq_item::RSP) return;   // only completed packets
    if (t.port_id > 3) begin
      `uvm_error("SB_PORT", $sformatf("Actual item with illegal port_id %0d", t.port_id))
      return;
    end

    // 1. Empty queue: nothing was predicted for this port
    if (exp_q[t.port_id].size() == 0) begin
      n_unexpected++;
      `uvm_error("SB_UNEXPECTED", $sformatf(
        "@%0t DATA_OUT_%0d produced a packet nobody predicted (len %0d, data %p)",
        $time, t.port_id + 1, t.newdata_len, t.data))
      return;
    end

    // 2. Always compare against the FRONT item only
    exp  = exp_q[t.port_id].pop_front();
    diff = compare_pkt(exp, t);

    if (diff == "") begin
      n_match++;
      `uvm_info("SB_MATCH", $sformatf("DATA_OUT_%0d len %0d matched",
                t.port_id + 1, t.newdata_len), UVM_MEDIUM)
    end else begin
      n_mismatch++;
      `uvm_error("SB_MISMATCH", $sformatf("@%0t DATA_OUT_%0d: %s\n  expected len %0d data %p\n  actual   len %0d data %p",
        $time, t.port_id + 1, diff, exp.newdata_len, exp.data, t.newdata_len, t.data))
    end
  endfunction : write_act

  // Returns "" on a match, otherwise a description of the FIRST difference.
  // Uses !== so X/Z on DATA_OUT is reported as a mismatch.
  function string compare_pkt(downstream_seq_item exp, downstream_seq_item act);
    if (exp.newdata_len !== act.newdata_len)
      return $sformatf("NEWDATA_LEN expected %0d got %0d", exp.newdata_len, act.newdata_len);
    if (exp.data.size() != act.data.size())
      return $sformatf("byte count expected %0d got %0d", exp.data.size(), act.data.size());
    foreach (exp.data[i])
      if (exp.data[i] !== act.data[i])
        return $sformatf("byte %0d expected 0x%02h got 0x%02h", i, exp.data[i], act.data[i]);
    return "";
  endfunction : compare_pkt

  //----------------------------------------------------------------------------
  // Reset handling: flush every expected queue (buffer is cleared by the DUT)
  //----------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    forever begin
      reset_event.wait_trigger();
      n_resets++;
      foreach (exp_q[p]) begin
        if (exp_q[p].size() > 0)
          `uvm_info("SB_FLUSH", $sformatf("Reset: discarding %0d expected packet(s) for DATA_OUT_%0d",
                    exp_q[p].size(), p + 1), UVM_MEDIUM)
        n_flushed += exp_q[p].size();
        exp_q[p].delete();
      end
    end
  endtask : run_phase

  //----------------------------------------------------------------------------
  // End of test: anything still expected never came out
  //----------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // Multi-dimensional foreach: p = port index, i = position in that queue
    foreach (exp_q[p, i]) begin
      n_missing++;
      `uvm_error("SB_MISSING", $sformatf("DATA_OUT_%0d never produced expected packet len %0d data %p",
                 p + 1, exp_q[p][i].newdata_len, exp_q[p][i].data))
    end
    if (n_expected > 0 && n_match == 0)
      `uvm_warning("SB_NOCHECK", "Packets were predicted but none were matched")
  endfunction : check_phase

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    $display("\n--------------------- SCOREBOARD SUMMARY ---------------------");
    $display("  Expected (predicted) : %0d", n_expected);
    $display("  MATCH                : %0d", n_match);
    $display("  MISMATCH             : %0d", n_mismatch);
    $display("  UNEXPECTED           : %0d", n_unexpected);
    $display("  MISSING              : %0d", n_missing);
    $display("  Resets seen / flushed: %0d / %0d", n_resets, n_flushed);
    $display("  SCOREBOARD RESULT    : %s",
             (n_mismatch + n_unexpected + n_missing == 0) ? "PASS" : "FAIL");
    $display("--------------------------------------------------------------\n");
  endfunction : report_phase

endclass : pdm_scoreboard
