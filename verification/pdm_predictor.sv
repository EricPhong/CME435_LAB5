/* Eric Phong, rfp479, CME435, 11344905, Lab5 */

//------------------------------------------------------------------------------
// Class: pdm_predictor
//
// Reference model of the PDM *specification* (not the RTL).
// Input : upstream_seq_item from the upstream monitor (what went INTO the DUT)
// Output: downstream_seq_item (kind = RSP) describing what SHOULD come out.
//
// Spec mapping (one expected item per packet, not per byte):
//   destination 1..4          -> port_id 0..3   (port_id = destination - 1)
//   payload size (4/8/12/16)  -> newdata_len    (dest byte is stripped, no -1)
//   payload bytes             -> data           (same bytes, same order)
//
// Design decisions for behaviour the spec does not define (also in report):
//   * Destination outside 1..4 or length not in {4,8,12,16}: the spec gives no
//     behaviour, so we predict NO output and count the packet in n_dropped.
//     If the DUT does output something, the scoreboard flags it as UNEXPECTED.
//   * Reset between the terminating BND_PLSE and ACK: the upstream monitor's
//     observe thread is killed by reset before it broadcasts, so this packet
//     never reaches the predictor -> predicted as discarded (buffer is cleared).
//   * Mid-packet reset: same mechanism, the partial packet is never predicted.
//------------------------------------------------------------------------------
class pdm_predictor extends uvm_subscriber #(upstream_seq_item);
  `uvm_component_utils(pdm_predictor)

  // Expected downstream packets -> scoreboard
  uvm_analysis_port #(downstream_seq_item) ap;

  // Statistics
  int unsigned n_predicted = 0;
  int unsigned n_dropped   = 0;

  function new(string name = "pdm_predictor", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);              // ports are built with new(), never the factory
  endfunction : build_phase

  // Called by upstream_monitor.upstream_txn_ap.write() via analysis_export
  function void write(upstream_seq_item t);
    downstream_seq_item exp;

    // Only real packets create expectations (resets are handled by the scoreboard)
    if (t.operation != upstream_seq_item::DATA_TRANSFER) return;

    // Unspecified inputs -> predict no output (see header comment)
    if (!(t.destination inside {[1:4]}) || !(t.data.size() inside {4, 8, 12, 16})) begin
      n_dropped++;
      `uvm_info("PRED", $sformatf(
        "Invalid packet (dest=%0d, len=%0d): spec undefined, predicting NO output",
        t.destination, t.data.size()), UVM_MEDIUM)
      return;
    end

    // A NEW object per prediction: the scoreboard stores this handle in a queue
    exp             = downstream_seq_item::type_id::create("exp_pkt");
    exp.kind        = downstream_seq_item::RSP;
    exp.port_id     = t.destination - 1;           // pin/dest 1..4 -> index 0..3
    exp.newdata_len = t.data.size();
    exp.data = new[t.data.size()];               // size the 4-state array
    foreach (t.data[i]) exp.data[i] = t.data[i]; // element copy: bit -> logic is legal
    
    n_predicted++;
    `uvm_info("PRED", $sformatf("Predict port_idx %0d (DATA_OUT_%0d) len %0d",
              exp.port_id, exp.port_id + 1, exp.newdata_len), UVM_HIGH)
    ap.write(exp);
  endfunction : write

  function void report_phase(uvm_phase phase);
    `uvm_info("PRED", $sformatf("Predicted %0d packets, dropped %0d invalid packets",
              n_predicted, n_dropped), UVM_LOW)
  endfunction : report_phase

endclass : pdm_predictor
