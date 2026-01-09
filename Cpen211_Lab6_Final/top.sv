// ================================================================
// Lab 6 - Single-file solution (kb_db + keyboard + combo + top)
// File: lab6_top.sv
// Satisfies: receiver 2FF synchronizers; sample 1 cycle after valid goes low;
// transmitter holds key_code/key_validn stable while pressed.
// ================================================================

// ------------------------------
// Debounce + keypad front-end
// ------------------------------
module kb_db #( DELAY=16 ) (
  input  logic        clk,
  input  logic        rst,
  inout  wire  [3:0]  row_wires, // could be 'output logic'
  inout  wire  [3:0]  col_wires, // could be 'input  logic'
  input  logic [3:0]  row_scan,
  output logic [3:0]  row,
  output logic [3:0]  col,
  output logic        valid,
  output logic        debounceOK
);
  logic [3:0] col_F1, col_F2;
  logic [3:0] row_F1, row_F2;
  logic       pressed, row_change, col_change;

  assign row_wires  = row_scan;
  assign pressed    = ~&( col_F2 );
  assign col_change = pressed ^ pressed_sync;
  assign row_change = |(row_scan ^ row_F1);

  logic [3:0] row_sync, col_sync;
  logic       pressed_sync;

  // synchronizer to the debouncer
  always_ff @( posedge clk ) begin
    row_F1   <= row_scan;   col_F1   <= col_wires;
    row_F2   <= row_F1;     col_F2   <= col_F1;
    row_sync <= row_F2;     col_sync <= col_F2;
    pressed_sync <= pressed;
  end

  // align row/col/valid
  always_ff @( posedge clk ) begin
    valid <= debounceOK & pressed_sync;
    if (debounceOK & pressed_sync) begin
      row <= row_sync;
      col <= col_sync;
    end else begin
      row <= 4'd0;
      col <= 4'd0;
    end
  end

  // debounce counter
  logic [DELAY:0] counter;
  initial counter = '0;
  always_ff @( posedge clk ) begin
    if (rst | row_change | col_change) begin
      counter <= '0;
    end else if (!debounceOK) begin
      counter <= counter + 1'b1;
    end
  end

  assign debounceOK = counter[DELAY];
endmodule


// ------------------------------
// Keyboard transmitter
// - scans rows slowly
// - holds key_validn low and key_code stable while pressed
// ------------------------------
module keyboard (
  input  logic        clk,
  input  logic        rst,
  inout  wire  [3:0]  row_wires,
  inout  wire  [3:0]  col_wires,
  output logic [3:0]  key_code,
  output logic        key_validn   // active-low while key is pressed
);

  logic [3:0] row, col;
  logic [3:0] row_scan;
  logic       valid;
  logic       debounceOK;

  kb_db #(.DELAY(16)) u_db (
    .clk        (clk),
    .rst        (rst),
    .row_wires  (row_wires),
    .col_wires  (col_wires),
    .row_scan   (row_scan),
    .row        (row),
    .col        (col),
    .valid      (valid),
    .debounceOK (debounceOK)
  );

  // --- slow row scanner; freeze while a key is valid to keep signals stable
  logic [15:0] scan_div;
  logic [1:0]  scan;

  always_ff @(posedge clk) begin
    if (rst) begin
      scan_div <= '0;
      scan     <= 2'd0;
    end else begin
      if (!valid) begin
        scan_div <= scan_div + 16'd1;
        if (&scan_div) begin
          scan_div <= '0;
          scan     <= scan + 2'd1;
        end
      end
      // else: freeze scan while key is pressed/debounced
    end
  end

  // active-low one-hot row enable
  assign row_scan = ~(4'b0001 << scan);

  // --- keypad decode (active-low sense)
  function automatic logic [3:0] decode_key (input logic [3:0] r, c);
    case ({r,c})
      8'b1110_1110: decode_key = 4'h1;
      8'b1110_1101: decode_key = 4'h2;
      8'b1110_1011: decode_key = 4'h3;
      8'b1110_0111: decode_key = 4'hA;
      8'b1101_1110: decode_key = 4'h4;
      8'b1101_1101: decode_key = 4'h5;
      8'b1101_1011: decode_key = 4'h6;
      8'b1101_0111: decode_key = 4'hB;
      8'b1011_1110: decode_key = 4'h7;
      8'b1011_1101: decode_key = 4'h8;
      8'b1011_1011: decode_key = 4'h9;
      8'b1011_0111: decode_key = 4'hC;
      8'b0111_1110: decode_key = 4'hE; // #
      8'b0111_1101: decode_key = 4'h0;
      8'b0111_1011: decode_key = 4'hF; // *
      8'b0111_0111: decode_key = 4'hD;
      default:      decode_key = 4'h0;
    endcase
  endfunction

  // --- Latch code on first valid, hold while pressed; key_validn low during press
  typedef enum logic [1:0] { A_SCAN, C_HOLD, D_REL } sta_t;
  sta_t st;

  always_ff @(posedge clk) begin
    if (rst) begin
      st         <= A_SCAN;
      key_code   <= 4'h0;
      key_validn <= 1'b1;   // idle high
    end else begin
      unique case (st)
        A_SCAN: begin
          key_validn <= 1'b1;
          if (valid) begin
            key_code   <= decode_key(row, col); // debounced -> latch
            key_validn <= 1'b0;                 // assert valid during press
            st         <= C_HOLD;
          end
        end
        C_HOLD: begin
          key_validn <= 1'b0;                   // keep asserted
          if (!valid) st <= D_REL;
        end
        D_REL: begin
          key_validn <= 1'b1;                   // deassert
          st         <= A_SCAN;
        end
      endcase
    end
  end
endmodule


// ------------------------------
// Combo receiver
// - 2FF synchronizers for key_validn and key_code[3:0]
// - sample code ONE CYCLE AFTER key_validn_sync goes low
// - simple 4-nibble password; shows OPEN on success, progress otherwise
// ------------------------------
module combo (
  input  logic        clk,
  input  logic        rst,
  input  logic        key_validn,        // from keyboard (active-low)
  input  logic [3:0]  key_code,          // from keyboard
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3
);
  // ---------- 2FF synchronizers (all 5 signals)
  logic [3:0] key_code_s1, key_code_s2;
  logic       key_validn_s1, key_validn_s2;

  always_ff @(posedge clk) begin
    key_code_s1   <= key_code;
    key_code_s2   <= key_code_s1;
    key_validn_s1 <= key_validn;
    key_validn_s2 <= key_validn_s1;
  end

  // ---------- sample one cycle AFTER seeing valid go low
  logic prev_validn;           // for edge detect (high->low)
  logic arm_sample;            // set on edge, consume next cycle
  logic sampled_this_press;    // block repeats while still low

  // password and entry buffer
  localparam logic [15:0] PASSWORD = 16'h123A; // 1,2,3,A
  logic [15:0] entered;
  logic [1:0]  count;          // 0..3 nibbles filled
  logic        unlocked;

  // 7-seg patterns (common anode on DE10-Lite: 1=off, 0=segment on)
  function automatic logic [6:0] seg_hex(input logic [3:0] x);
    case (x)
      4'h0: seg_hex = 7'b1000000;
      4'h1: seg_hex = 7'b1111001;
      4'h2: seg_hex = 7'b0100100;
      4'h3: seg_hex = 7'b0110000;
      4'h4: seg_hex = 7'b0011001;
      4'h5: seg_hex = 7'b0010010;
      4'h6: seg_hex = 7'b0000010;
      4'h7: seg_hex = 7'b1111000;
      4'h8: seg_hex = 7'b0000000;
      4'h9: seg_hex = 7'b0010000;
      4'hA: seg_hex = 7'b0001000; // A
      4'hB: seg_hex = 7'b0000011; // b
      4'hC: seg_hex = 7'b1000110; // C
      4'hD: seg_hex = 7'b0100001; // d
      4'hE: seg_hex = 7'b0000110; // E
      4'hF: seg_hex = 7'b0001110; // F
    endcase
  endfunction

  // simple dash ("-") and blank
  localparam logic [6:0] SEG_DASH  = 7'b0111111;
  localparam logic [6:0] SEG_BLANK = 7'b1111111;

  // "OPEN" = O P E n (approx)
  localparam logic [6:0] SEG_O = 7'b1000000; // 0 looks like O
  localparam logic [6:0] SEG_P = 7'b0001100; // P
  localparam logic [6:0] SEG_E = 7'b0000110; // E
  localparam logic [6:0] SEG_n = 7'b0101011; // small n (approx with 7-seg)

  always_ff @(posedge clk) begin
    if (rst) begin
      prev_validn        <= 1'b1;
      arm_sample         <= 1'b0;
      sampled_this_press <= 1'b0;
      entered            <= 16'd0;
      count              <= 2'd0;
      unlocked           <= 1'b0;
    end else begin
      prev_validn <= key_validn_s2;

      // detect high->low edge of validn (since active-low)
      if (prev_validn == 1'b1 && key_validn_s2 == 1'b0) begin
        arm_sample         <= 1'b1;     // ask to sample next cycle
        sampled_this_press <= 1'b0;
      end

      // one cycle later (while still low) -> actually sample
      if (arm_sample) begin
        arm_sample <= 1'b0;
        if (key_validn_s2 == 1'b0 && !sampled_this_press) begin
          // shift in nibble
          entered <= {entered[11:0], key_code_s2};
          if (count == 2'd3) begin
            // 4th nibble -> compare, then reset count
            unlocked <= ( {entered[11:0], key_code_s2} == PASSWORD );
            count    <= 2'd0;
          end else begin
            count <= count + 2'd1;
          end
          sampled_this_press <= 1'b1;   // only once per press
        end
      end

      // when validn returns high, allow next press
      if (key_validn_s2 == 1'b1) begin
        sampled_this_press <= 1'b0;
      end
    end
  end

  // Display: show progress until unlocked, then "OPEN"
  always_comb begin
    if (unlocked) begin
      // OPEN
      HEX3 = SEG_O; HEX2 = SEG_P; HEX1 = SEG_E; HEX0 = SEG_n;
    end else begin
      // show last two entered nibbles (right), dashes (left)
      HEX3 = (count > 2'd1) ? seg_hex(entered[15:12]) : SEG_DASH;
      HEX2 = (count > 2'd0) ? seg_hex(entered[11:8 ]) : SEG_DASH;
      HEX1 = (count > 2'd2) ? seg_hex(entered[ 7:4 ]) : SEG_BLANK;
      HEX0 = (count > 2'd3) ? seg_hex(entered[ 3:0 ]) : SEG_BLANK;
    end
  end
endmodule


// ------------------------------
// Top-level: internal loopback (single-board demo)
// - Connect keypad to row/col, keyboard -> combo signals internally
// - Drive HEX3..0 from combo
// ------------------------------
module top (
  input  logic        clk,
  input  logic        rst,
  inout  wire  [3:0]  row_wires,
  inout  wire  [3:0]  col_wires,
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3
);
  logic [3:0] key_code;
  logic       key_validn;

  keyboard u_kb (
    .clk        (clk),
    .rst        (rst),
    .row_wires  (row_wires),
    .col_wires  (col_wires),
    .key_code   (key_code),
    .key_validn (key_validn)
  );

  combo u_combo (
    .clk        (clk),
    .rst        (rst),
    .key_validn (key_validn),
    .key_code   (key_code),
    .HEX0       (HEX0),
    .HEX1       (HEX1),
    .HEX2       (HEX2),
    .HEX3       (HEX3)
  );
endmodule