/* Eric Phong, rfp479, CME435, 11344905, Lab5 */
`ifndef PDM_PAYLOAD_CORNER_SEQ_SV
`define PDM_PAYLOAD_CORNER_SEQ_SV

//------------------------------------------------------------------------------
// Sequence: pdm_payload_corner_seq
//
// Intent: drive payload-value corner cases to every port so the scoreboard is
// checked on extreme data (all 0x00, all 0xFF, alternating 0x55/0xAA) and the
// cg_payload_byte zero/max bins are closed. Random bytes alone hit 0x00/0xFF
// with only 1/256 probability each.
//------------------------------------------------------------------------------
class pdm_payload_corner_seq extends uvm_sequence #(upstream_seq_item);
  `uvm_object_utils(pdm_payload_corner_seq)

  typedef enum {ALL_ZERO, ALL_ONES, ALTERNATING} pattern_e;

  function new(string name = "pdm_payload_corner_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    upstream_seq_item pkt;
    pattern_e pat;

    for (int p = 1; p <= 4; p++) begin
      for (int k = 0; k < 3; k++) begin
        pat = pattern_e'(k);
        pkt = upstream_seq_item::type_id::create($sformatf("corner_p%0d_%s", p, pat.name()));
        start_item(pkt);
        if (!pkt.randomize() with {
          operation   == upstream_seq_item::DATA_TRANSFER;
          destination == p;
          foreach (data[i]) {
            (pat == ALL_ZERO)    -> data[i] == 8'h00;
            (pat == ALL_ONES)    -> data[i] == 8'hFF;
            (pat == ALTERNATING) -> data[i] == ((i % 2) ? 8'hAA : 8'h55);
          }
        }) `uvm_fatal("SEQRAND", "Failed to randomize payload corner packet")
        finish_item(pkt);
      end
    end
  endtask : body

endclass : pdm_payload_corner_seq

`endif // PDM_PAYLOAD_CORNER_SEQ_SV
