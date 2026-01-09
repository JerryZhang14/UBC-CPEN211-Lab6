module combo_core(
    input  logic       clk,
    input  logic       rst,
    input  logic [3:0] key_code_sync,
    input  logic       key_validn_sync,       // active-LOW while key held
    output logic [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output logic [9:0] LEDR
);

    logic key_pressed;
    logic key_validn_prev;
    logic [23:0] debounce_counter; // 250ms 
    logic debounce_active;
    
    always_ff @(posedge clk or posedge rst) begin
	 
        if (rst) begin
            key_validn_prev   <= 1'b1;
            key_pressed       <= 1'b0;
            debounce_counter  <= 24'b0;
            debounce_active   <= 1'b0;
        end else begin
            key_validn_prev <= key_validn_sync;

            if (key_validn_prev && ~key_validn_sync && ~debounce_active) begin
                key_pressed      <= 1'b1;
                debounce_active  <= 1'b1;
                debounce_counter <= 24'b0;
            end else begin
                key_pressed <= 1'b0;
            end

            if (debounce_active) begin
                if (debounce_counter == 24'd12_500_000) begin 
                    debounce_active <= 1'b0;
                end else begin
                    debounce_counter <= debounce_counter + 1;
                end
            end
        end
    end

    logic [3:0] digit1;
	 logic [3:0] digit2;
	 logic [3:0] digit3;
	 logic [3:0] digit4;
	 logic [3:0] digit5;
	 logic [3:0] digit6;	 
    logic [3:0] stored_pass1;
	 logic [3:0] stored_pass2;
	 logic [3:0] stored_pass3;
	 logic [3:0] stored_pass4;
	 logic [3:0] stored_pass5;
	 logic [3:0] stored_pass6;
    logic       locked;
    logic [2:0] digit_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize
            digit1 <= 4'hF; 
				digit2 <= 4'hF; 
				digit3 <= 4'hF;
            digit4 <= 4'hF; 
				digit5 <= 4'hF; 
				digit6 <= 4'hF;
				stored_pass1 <= 4'h1; 
				stored_pass2 <= 4'h2; 
				stored_pass3 <= 4'h3;
            stored_pass4 <= 4'h4; 
				stored_pass5 <= 4'h5; 
				stored_pass6 <= 4'h6;
            locked      <= 1'b0;
            digit_count <= 3'b0;

        end else if (key_pressed) begin
            case (key_code_sync)
                4'hF: begin //*
                    digit1 <= 4'hF; digit2 <= 4'hF; digit3 <= 4'hF;
                    digit4 <= 4'hF; digit5 <= 4'hF; digit6 <= 4'hF;
                    digit_count <= 3'b0;
                end

                4'hE: begin //#
                    if (digit_count == 3'd6) begin //6 digit input
                        if (!locked) begin
                            //storing password
                            stored_pass1 <= digit1; 
									 stored_pass2 <= digit2; 
									 stored_pass3 <= digit3;
                            stored_pass4 <= digit4; 
									 stored_pass5 <= digit5; 
									 stored_pass6 <= digit6;
                            locked <= 1'b1;
                        end else begin
                            //check if matches
                            if (digit1 == stored_pass1 && digit2 == stored_pass2 &&
                                digit3 == stored_pass3 && digit4 == stored_pass4 &&
                                digit5 == stored_pass5 && digit6 == stored_pass6) begin
                                locked <= 1'b0;
                            end
                        end
                        //clearing 
                        digit1 <= 4'hF; 
								digit2 <= 4'hF;
								digit3 <= 4'hF;
                        digit4 <= 4'hF; 
								digit5 <= 4'hF; 
								digit6 <= 4'hF;
                        digit_count <= 3'b0;
                    end
                end

                //assigning each hex display
                default: begin : assign_display
                    if (digit_count < 3'd6) begin
                        unique case (digit_count)
                            3'd0: digit1 <= key_code_sync;
                            3'd1: digit2 <= key_code_sync;
                            3'd2: digit3 <= key_code_sync;
                            3'd3: digit4 <= key_code_sync;
                            3'd4: digit5 <= key_code_sync;
                            3'd5: digit6 <= key_code_sync;
                            default:;
                        endcase
                        digit_count <= digit_count + 3'b1;
                    end
                end
            endcase
        end
    end

    // ENCODER
    function automatic [7:0] sevenseg(input logic [3:0] n);
        case (n)
            4'h0: sevenseg = 8'b1100_0000;  
				4'h1: sevenseg = 8'b1111_1001;
            4'h2: sevenseg = 8'b1010_0100; 
				4'h3: sevenseg = 8'b1011_0000;
            4'h4: sevenseg = 8'b1001_1001; 
				4'h5: sevenseg = 8'b1001_0010;
            4'h6: sevenseg = 8'b1000_0010; 
				4'h7: sevenseg = 8'b1111_1000;
            4'h8: sevenseg = 8'b1000_0000;  
				4'h9: sevenseg = 8'b1001_0000;
            4'hA: sevenseg = 8'b1000_1000;  
				4'hB: sevenseg = 8'b1000_0011;
            4'hC: sevenseg = 8'b1100_0110;  
				4'hD: sevenseg = 8'b1010_0001;
            4'hE: sevenseg = 8'b1000_0110;  
				4'hF: sevenseg = 8'b1111_1111;
            default: sevenseg = 8'b1111_1111;
        endcase
    endfunction

//displays
    always_comb begin
        if (digit_count == 0) begin
            if (locked) begin
                // LOCKED
                HEX5 = 8'b1100_0111;
                HEX4 = 8'b1100_0000;
                HEX3 = 8'b1100_0110;
                HEX2 = 8'b1000_1001;
                HEX1 = 8'b1000_0110;
                HEX0 = 8'b1010_0001;
            end else begin
                // OPEN 
                HEX5 = 8'b1111_1111;
                HEX4 = 8'b1100_0000; 
                HEX3 = 8'b1000_1100; 
                HEX2 = 8'b1000_0110;
                HEX1 = 8'b1010_1011;
                HEX0 = 8'b1111_1111;
            end
        end else begin
            HEX5 = sevenseg(digit1);
            HEX4 = sevenseg(digit2);
            HEX3 = sevenseg(digit3);
            HEX2 = sevenseg(digit4);
            HEX1 = sevenseg(digit5);
            HEX0 = sevenseg(digit6);
        end
    end

    //LED 
    assign LEDR[0]   = locked;
    assign LEDR[1]   = (digit_count > 0);
    assign LEDR[2]   = key_pressed;
    assign LEDR[3]   = debounce_active;
    assign LEDR[6:4] = key_code_sync[2:0];
    assign LEDR[9:7] = digit_count;

endmodule
