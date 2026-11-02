module ble_event_fifo #(
    parameter integer WIDTH = 24,
    parameter integer ADDR_BITS = 4
)(
    input wclk,
    input wrst_n,
    input we,
    input [WIDTH-1:0] wdata,
    output full,
    input rclk,
    input rrst_n,
    input re,
    output [WIDTH-1:0] rdata,
    output empty
);
    localparam integer DEPTH = (1 << ADDR_BITS);
    localparam integer PTR_BITS = ADDR_BITS + 1;

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_BITS-1:0] wbin, wgray, rbin, rgray;
    reg [PTR_BITS-1:0] wgray_s1, wgray_s2;
    reg [PTR_BITS-1:0] rgray_s1, rgray_s2;

    wire [PTR_BITS-1:0] wbin_next = wbin + 1'b1;
    wire [PTR_BITS-1:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire [PTR_BITS-1:0] rbin_next = rbin + 1'b1;
    wire [PTR_BITS-1:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    assign full = (wgray_next == {~wgray_s2[PTR_BITS-1:PTR_BITS-2], wgray_s2[PTR_BITS-3:0]});
    assign empty = (rgray == rgray_s2);
    assign rdata = mem[rbin[ADDR_BITS-1:0]];

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin <= 0;
            wgray <= 0;
            wgray_s1 <= 0;
            wgray_s2 <= 0;
        end else begin
            wgray_s1 <= rgray;
            wgray_s2 <= wgray_s1;
            if (we && !full) begin
                mem[wbin[ADDR_BITS-1:0]] <= wdata;
                wbin <= wbin_next;
                wgray <= wgray_next;
            end
        end
    end

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin <= 0;
            rgray <= 0;
            rgray_s1 <= 0;
            rgray_s2 <= 0;
        end else begin
            rgray_s1 <= wgray;
            rgray_s2 <= rgray_s1;
            if (re && !empty) begin
                rbin <= rbin_next;
                rgray <= rgray_next;
            end
        end
    end
endmodule

