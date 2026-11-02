module six_rom_arbiter(
    input clk, input rst_n,
    input req0, input [12:0] addr0,
    input req1, input [12:0] addr1,
    input req2, input [12:0] addr2,
    output [12:0] rom_addr,
    output reg valid0, output reg valid1, output reg valid2
);
    // Pipelined read arbiter, one logical ROM word per cycle.
    // A client must hold req/addr until its valid pulse. The grant is
    // combinational; the selected address goes straight to the synchronous
    // ROM, and the owner/valid tag is registered in the same cycle so that
    // rom_data and valid arrive together one cycle later.
    //
    // busy[c] blocks a new grant in the cycle where client c is consuming its
    // returned word, which prevents a held request from being accepted twice.
    reg [1:0] v_owner;
    reg [2:0] busy;
    reg prio_lo;

    wire r0 = req0 & ~busy[0];
    wire r1 = req1 & ~busy[1];
    wire r2 = req2 & ~busy[2];
    wire any = r0 | r1 | r2;

    // Client 0 (modal) has strict priority because it has the tightest
    // per-sample budget. Clients 1/2 round-robin when client 0 is idle.
    reg [1:0] chosen;
    always @* begin
        if(r0) chosen = 2'd0;
        else if(r1 && r2) chosen = prio_lo ? 2'd2 : 2'd1;
        else if(r1) chosen = 2'd1;
        else chosen = 2'd2;
    end

    assign rom_addr = (chosen==2'd0) ? addr0 :
                      (chosen==2'd1) ? addr1 : addr2;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            v_owner<=0; busy<=0; prio_lo<=0;
            valid0<=0; valid1<=0; valid2<=0;
        end else begin
            valid0<=0; valid1<=0; valid2<=0;
            if(valid0) busy[0]<=1'b0;
            if(valid1) busy[1]<=1'b0;
            if(valid2) busy[2]<=1'b0;

            if(any) begin
                v_owner<=chosen;
                busy[chosen]<=1'b1;
                if(chosen==2'd0) valid0<=1;
                else if(chosen==2'd1) begin valid1<=1; prio_lo<=1'b1; end
                else begin valid2<=1; prio_lo<=1'b0; end
            end
        end
    end
endmodule
