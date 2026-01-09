module kb_db #( parameter DELAY=16 ) (
    input  logic        clk, rst,
    inout  wire  [3:0]  row_wires, col_wires,
    input  logic [3:0]  row_scan,
    output logic [3:0]  row, col,
    output logic        valid, debounceOK
);
    logic [3:0] col_F1, col_F2, row_F1, row_F2;
    logic [3:0] row_sync, col_sync;
    logic       pressed, pressed_sync, row_change, col_change;

    assign row_wires  = row_scan;
    assign pressed    = ~&(col_F2);
    assign col_change = pressed ^ pressed_sync;
    assign row_change = |(row_scan ^ row_F1);

    always_ff @(posedge clk) begin
        row_F1   <= row_scan;   col_F1   <= col_wires;
        row_F2   <= row_F1;     col_F2   <= col_F1;
        row_sync <= row_F2;     col_sync <= col_F2;
        pressed_sync <= pressed;
    end

    always_ff @(posedge clk) begin
        valid <= debounceOK & pressed_sync;
        if (debounceOK & pressed_sync) begin
            row <= row_sync; col <= col_sync;
        end else begin
            row <= 4'd0; col <= 4'd0;
        end
    end

    logic [DELAY:0] counter;
    always_ff @(posedge clk) begin
        if (rst | row_change | col_change) counter <= '0;
        else if (!debounceOK)              counter <= counter + 1'b1;
    end
    assign debounceOK = counter[DELAY];
endmodule

