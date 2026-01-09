// ===================================================================
// Lab 6 - Single file (Board Settings compatible)
// File: lab6_board_top.sv
// Top Entity: de10lite_board_top
// Board I/O exposed: CLOCK_50, KEY, HEX0..HEX3, ARDUINO_IO[15:0]
// Rows -> ARDUINO_IO[7:4], Cols -> ARDUINO_IO[3:0]
// ===================================================================

// ------------------------------
// Debounce + keypad front-end (from lab)
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

  always_ff @( posedge clk ) begin
    row_F1   <= row_scan;   col_F1   <= col_wires;
    row_F2   <= row_F1;     col_F2   <= col_F1;
    row_sync <= row_F2;     col_sync <= col_F2;
    pressed_sync <= pressed;
  end

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

  // Slow row scanner; freeze while a key is valid (prevents resetting debounce)
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
    end
  end

  // Active-low one-hot row enable: 0001 << scan, then invert
  assign row_scan = ~(4'b0001 << scan);

  // keypad decode (active-low row/col)
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

  // Latch-once per press, hold while pressed; key_validn low during press
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
// Combo receiver (2FF sync + 1-cycle-later sample)
// ------------------------------
module combo (
  input  logic        clk,
  input  logic        rst,
  input  logic        key_validn,
  input  logic [3:0]  key_code,
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3
);
  // 2FF synchronizers (all 5 signals) — receiver requirement
  logic [3:0] key_code_s1, key_code_s2;
  logic       key_validn_s1, key_validn_s2;

  always_ff @(posedge clk) begin
    key_code_s1   <= key_code;
    key_code_s2   <= key_code_s1;
    key_validn_s1 <= key_validn;
    key_validn_s2 <= key_validn_s1;
  end

  // sample one cycle AFTER validn_sync goes low
  logic prev_validn, arm_sample, sampled_this_press;

  localparam logic [15:0] PASSWORD = 16'h123A; // 1,2,3,A
  logic [15:0] entered;
  logic [1:0]  count;
  logic        unlocked;

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

  localparam logic [6:0] SEG_DASH  = 7'b0111111;
  localparam logic [6:0] SEG_BLANK = 7'b1111111;
  localparam logic [6:0] SEG_O = 7'b1000000; // O≈0
  localparam logic [6:0] SEG_P = 7'b0001100;
  localparam logic [6:0] SEG_E = 7'b0000110;
  localparam logic [6:0] SEG_n = 7'b0101011;

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

      if (prev_validn == 1'b1 && key_validn_s2 == 1'b0) begin
        arm_sample         <= 1'b1;     // sample next cycle
        sampled_this_press <= 1'b0;
      end

      if (arm_sample) begin
        arm_sample <= 1'b0;
        if (key_validn_s2 == 1'b0 && !sampled_this_press) begin
          entered <= {entered[11:0], key_code_s2};
          if (count == 2'd3) begin
            unlocked <= ( {entered[11:0], key_code_s2} == PASSWORD );
            count    <= 2'd0;
          end else begin
            count <= count + 2'd1;
          end
          sampled_this_press <= 1'b1;
        end
      end

      if (key_validn_s2 == 1'b1) begin
        sampled_this_press <= 1'b0;
      end
    end
  end

  always_comb begin
    if (unlocked) begin
      HEX3 = SEG_O; HEX2 = SEG_P; HEX1 = SEG_E; HEX0 = SEG_n; // "OPEN"
    end else begin
      HEX3 = (count > 2'd1) ? seg_hex(entered[15:12]) : SEG_DASH;
      HEX2 = (count > 2'd0) ? seg_hex(entered[11:8 ]) : SEG_DASH;
      HEX1 = (count > 2'd2) ? seg_hex(entered[ 7:4 ]) : SEG_BLANK;
      HEX0 = (count > 2'd3) ? seg_hex(entered[ 3:0 ]) : SEG_BLANK;
    end
  end
endmodule


// ------------------------------
// BOARD TOP (DE10-Lite naming)
// Exposes board ports so Board Settings can auto-map by name.
// Rows -> ARDUINO_IO[7:4]; Cols -> ARDUINO_IO[3:0]
// Reset uses KEY[0] (active-low); clk uses CLOCK_50.
// ------------------------------
module de10lite_board_top (
  input  logic        CLOCK_50,
  input  logic [1:0]  KEY,
  inout  wire  [15:0] ARDUINO_IO,
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3
);
  logic rst;
  assign rst = ~KEY[0];  // active-high reset inside from active-low KEY[0]

  // Internal keyboard → combo wires
  logic [3:0] key_code;
  logic       key_validn;

  // Hook the keyboard to Arduino header slices directly (inouts)
  keyboard u_kb (
    .clk        (CLOCK_50),
    .rst        (rst),
    .row_wires  (ARDO_ROW_SEL), // declared below as a tri-slice of ARDUINO_IO[7:4]
    .col_wires  (ARDO_COL_SEL), // tri-slice of ARDUINO_IO[3:0]
    .key_code   (key_code),
    .key_validn (key_validn)
  );

  // Create typed aliases of the ARDUINO_IO buses to satisfy some Quartus analyzers
  wire [3:0] ARDO_COL_SEL;  // columns (inputs from keypad)
  wire [3:0] ARDO_ROW_SEL;  // rows    (outputs to keypad)
  assign ARDO_COL_SEL = ARDUINO_IO[3:0];
  assign ARDUINO_IO[7:4] = ARDO_ROW_SEL;

  combo u_combo (
    .clk        (CLOCK_50),
    .rst        (rst),
    .key_validn (key_validn),
    .key_code   (key_code),
    .HEX0       (HEX0),
    .HEX1       (HEX1),
    .HEX2       (HEX2),
    .HEX3       (HEX3)
  );

  // Leave other ARDUINO_IO pins unused/high-Z (no assignments here)
endmodule
