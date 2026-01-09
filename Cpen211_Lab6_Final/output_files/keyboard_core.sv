module keyboard_core(
    input  logic       clk,
    input  logic       rst,

    inout  wire [3:0]  col_wires,   
    inout  wire [3:0]  row_wires,   

    output logic [3:0] key_code,    // keypad code 
    output logic       key_validn 
);

    parameter int SLOWCLK_BITS = 16;
    logic [SLOWCLK_BITS-1:0] slowclk_div;
    logic [1:0]              row_idx;

//slowly scan through row 0-3
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            slowclk_div <= '0;
            row_idx     <= '0;
        end else begin
            slowclk_div <= slowclk_div + 1'b1;
            if (slowclk_div == {SLOWCLK_BITS{1'b0}})
                row_idx <= row_idx + 2'd1;
        end
    end

//when scans a 0 in anyrow
    logic [3:0] row_scan;
    always_comb begin
        unique case (row_idx)
            2'd0: row_scan = 4'b0111;
            2'd1: row_scan = 4'b1011;
            2'd2: row_scan = 4'b1101;
            default: row_scan = 4'b1110;
        endcase
    end

//input to kb_db
    logic [3:0] kb_row, kb_col;
    logic       kb_valid, kb_debounceOK;

    kb_db #(.DELAY(14)) u_db (
        .clk(clk), .rst(rst),
        .row_wires(row_wires), .col_wires(col_wires),
        .row_scan(row_scan),
        .row(kb_row), .col(kb_col),
        .valid(kb_valid), .debounceOK(kb_debounceOK)
    );


//decoder
function automatic logic [3:0] rc_to_code(input logic [3:0] r, c);
    unique case ({r, c})
        // Row0 (0111)
        8'b0111_0111: rc_to_code = 4'h1;
        8'b0111_1011: rc_to_code = 4'h2;
        8'b0111_1101: rc_to_code = 4'h3;
        8'b0111_1110: rc_to_code = 4'hA;

        // Row1 (1011)
        8'b1011_0111: rc_to_code = 4'h4;
        8'b1011_1011: rc_to_code = 4'h5;
        8'b1011_1101: rc_to_code = 4'h6;
        8'b1011_1110: rc_to_code = 4'hB;

        // Row2 (1101)
        8'b1101_0111: rc_to_code = 4'h7;
        8'b1101_1011: rc_to_code = 4'h8;
        8'b1101_1101: rc_to_code = 4'h9;
        8'b1101_1110: rc_to_code = 4'hC;

        // Row3 (1110)
        8'b1110_0111: rc_to_code = 4'hF; // '*'
        8'b1110_1011: rc_to_code = 4'h0; // '0'
        8'b1110_1101: rc_to_code = 4'hE; // '#'
        8'b1110_1110: rc_to_code = 4'hD; // 'D'

        default:      rc_to_code = 4'h0;
    endcase
endfunction



//fsm (idel-scan-confirm
    typedef enum logic [1:0] {A, B, C} st_t;
    st_t st;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            st         <= A;
            key_code   <= 4'h0;
            key_validn <= 1'b1;
        end else begin
            unique case (st)
                A: begin
                    key_validn <= 1'b1;           
                    if (kb_valid) begin
                        key_code   <= rc_to_code(kb_row, kb_col);
                        key_validn <= 1'b0;        
                        st         <= B;
                    end
                end
                B: begin
                    if (!kb_valid) begin           
                        key_validn <= 1'b1;
                        st         <= C;
                    end
                end
                C: begin
                    if (!kb_valid)                
                        st <= A;
                end
            endcase
        end
    end
endmodule
