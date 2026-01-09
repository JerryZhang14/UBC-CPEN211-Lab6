module keyboard(
    input  logic       clk,
    input  logic       rst,

    inout  wire [3:0]  col_wires,   // keypad column bundle (inputs; enable weak pull-ups)
    inout  wire [3:0]  row_wires,   // keypad row bundle (driven inside kb_db)

    output logic [3:0] key_code,    // 0..9, A..D, #=E, *=F
    output logic       key_validn   // active-LOW while key is held
);
    // -------- row scanner (about ~1.3ms per row @50MHz when SCAN_BITS=16) -------
    parameter int SCAN_BITS = 16;
    logic [SCAN_BITS-1:0] slow;
    logic [1:0]           row_sel;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            slow    <= '0;
            row_sel <= '0;
        end else begin
            slow <= slow + 1'b1;
            if (slow == {SCAN_BITS{1'b0}})
                row_sel <= row_sel + 2'd1;
        end
    end

    // active row drives 0 (others 1) per lab convention
    logic [3:0] row_scan;
    always_comb begin
        unique case (row_sel)
            2'd0: row_scan = 4'b0111;
            2'd1: row_scan = 4'b1011;
            2'd2: row_scan = 4'b1101;
            default: row_scan = 4'b1110;
        endcase
    end

    // -------- lab debounce/sync block (drives row_wires internally) -------------
    logic [3:0] kb_row, kb_col;
    logic       kb_valid, kb_debounceOK;

    kb_db #(.DELAY(14)) u_db (
        .clk(clk), .rst(rst),
        .row_wires(row_wires), .col_wires(col_wires),
        .row_scan(row_scan),
        .row(kb_row), .col(kb_col),
        .valid(kb_valid), .debounceOK(kb_debounceOK)
    );

    // -------- column orientation fix (set to 0 if your wiring already matches) --
    localparam bit COL_REVERSE = 1;
    wire [3:0] col_fix;
    assign col_fix = (COL_REVERSE)
                   ? {kb_col[0], kb_col[1], kb_col[2], kb_col[3]}
                   : kb_col;

    // -------- encoder: rows/cols to nibble (layout: 1 2 3 A / 4 5 6 B / 7 8 9 C / * 0 # D)
    function automatic logic [3:0] rc_to_code(input logic [3:0] r, c);
        unique case ({r, c})
            // Row0 (0111): 1 2 3 A
            8'b0111_1110: rc_to_code = 4'h1;
            8'b0111_1101: rc_to_code = 4'h2;
            8'b0111_1011: rc_to_code = 4'h3;
            8'b0111_0111: rc_to_code = 4'hA;
            // Row1 (1011): 4 5 6 B
            8'b1011_1110: rc_to_code = 4'h4;
            8'b1011_1101: rc_to_code = 4'h5;
            8'b1011_1011: rc_to_code = 4'h6;
            8'b1011_0111: rc_to_code = 4'hB;
            // Row2 (1101): 7 8 9 C
            8'b1101_1110: rc_to_code = 4'h7;
            8'b1101_1101: rc_to_code = 4'h8;
            8'b1101_1011: rc_to_code = 4'h9;
            8'b1101_0111: rc_to_code = 4'hC;
            // Row3 (1110): * 0 # D
            8'b1110_1110: rc_to_code = 4'hF; // '*'
            8'b1110_1101: rc_to_code = 4'h0; // '0'
            8'b1110_1011: rc_to_code = 4'hE; // '#'
            8'b1110_0111: rc_to_code = 4'hD; // 'D'
            default:      rc_to_code = 4'h0;
        endcase
    endfunction

    // -------- one-code-per-press; key_validn low while held ---------------------
    typedef enum logic [1:0] {IDLE, SEND, WAIT_REL} st_t;
    st_t st;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            st         <= IDLE;
            key_code   <= 4'h0;
            key_validn <= 1'b1;
        end else begin
            unique case (st)
                IDLE: begin
                    key_validn <= 1'b1;
                    if (kb_valid) begin
                        key_code   <= rc_to_code(kb_row, col_fix);
                        key_validn <= 1'b0;
                        st         <= SEND;
                    end
                end
                SEND: begin
                    if (!kb_valid) begin
                        key_validn <= 1'b1;
                        st         <= WAIT_REL;
                    end
                end
                WAIT_REL: begin
                    if (!kb_valid)
                        st <= IDLE;
                end
            endcase
        end
    end
endmodule

