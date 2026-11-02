// Direct-mapped BTB with tagged PCs and two-bit saturating direction counters.
module branch_predictor #(parameter INDEX_BITS=4)(
    input wire clk, reset,
    input wire [31:0] query_pc,
    output wire [31:0] predicted_next,
    input wire update, is_branch, taken,
    input wire [31:0] update_pc, target
);
localparam N=1<<INDEX_BITS;
reg [N-1:0] valid;
reg [29-INDEX_BITS:0] tags[0:N-1];
reg [31:0] targets[0:N-1];
reg [1:0] counters[0:N-1];
wire [INDEX_BITS-1:0] qi=query_pc[INDEX_BITS+1:2];
wire [INDEX_BITS-1:0] ui=update_pc[INDEX_BITS+1:2];
wire qhit=valid[qi] && tags[qi]==query_pc[31:INDEX_BITS+2];
wire uhit=valid[ui] && tags[ui]==update_pc[31:INDEX_BITS+2];
assign predicted_next=qhit && counters[qi][1] ? targets[qi] : query_pc+32'd4;
always @(posedge clk) begin
    if(reset) valid<=0;
    else if(update) begin
        if(!is_branch) begin
            if(uhit) valid[ui]<=0;
        end else begin
            valid[ui]<=1;
            tags[ui]<=update_pc[31:INDEX_BITS+2];
            targets[ui]<=target;
            if(!uhit) counters[ui]<=taken ? 2'b10 : 2'b01;
            else if(taken && counters[ui]!=3) counters[ui]<=counters[ui]+1'b1;
            else if(!taken && counters[ui]!=0) counters[ui]<=counters[ui]-1'b1;
        end
    end
end
endmodule
