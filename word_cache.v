// One-way, one-word-per-line cache for the existing synchronous SRAM interface.
// A miss has the backend's normal one-cycle latency; hits suppress backend reads.
// Stores always reach RAM (write-through), update hits, do not allocate misses.
module word_cache #(parameter INDEX_BITS=5, parameter ADDRESS_BITS=18)(
    input wire clk, reset, invalidate,
    input wire req, cacheable,
    input wire [3:0] we,
    input wire [31:0] addr, wdata,
    output wire [31:0] rdata,
    output wire mem_en,
    output wire [3:0] mem_we,
    output wire [31:0] mem_addr, mem_wdata,
    input wire [31:0] mem_rdata,
    output reg [31:0] hit_count, miss_count
);
localparam N=1<<INDEX_BITS;
reg [N-1:0] valid;
reg [ADDRESS_BITS-INDEX_BITS-3:0] tags[0:N-1];
reg [31:0] words[0:N-1];
wire [INDEX_BITS-1:0] idx=addr[INDEX_BITS+1:2];
wire [ADDRESS_BITS-INDEX_BITS-3:0] tag=addr[ADDRESS_BITS-1:INDEX_BITS+2];
reg pending;
reg [ADDRESS_BITS-3:0] pending_word;
wire refill_match=pending && pending_word==addr[ADDRESS_BITS-1:2];
wire replacing_index=pending && pending_word[INDEX_BITS-1:0]==idx;
// A pending fill replaces the old index at this edge. Do not hit the old tag:
// a simultaneous old-line store would otherwise corrupt the incoming new line.
wire hit=cacheable && !invalidate &&
         (refill_match || (!replacing_index && valid[idx] && tags[idx]==tag));
wire [31:0] lookup=refill_match ? mem_rdata : words[idx];
reg response_hit;
reg [31:0] response_data;
integer lane;
assign mem_en=req && ((|we) || !hit);
assign mem_we=we;
assign mem_addr=addr;
assign mem_wdata=wdata;
assign rdata=response_hit ? response_data : mem_rdata;
always @(posedge clk) begin
    if(reset) begin
        valid<=0; pending<=0; response_hit<=0; response_data<=0;
        hit_count<=0; miss_count<=0;
    end else if(invalidate) begin
        valid<=0; pending<=0; response_hit<=0;
    end else begin
        if(pending) begin
            valid[pending_word[INDEX_BITS-1:0]]<=1;
            tags[pending_word[INDEX_BITS-1:0]]<=pending_word[ADDRESS_BITS-3:INDEX_BITS];
            words[pending_word[INDEX_BITS-1:0]]<=mem_rdata;
        end
        pending<=req && cacheable && !(|we) && !hit;
        if(req && cacheable && !(|we) && !hit) pending_word<=addr[ADDRESS_BITS-1:2];
        if(req) begin
            response_hit<=hit;
            response_data<=lookup;
            if(cacheable && !(|we)) begin
                if(hit) hit_count<=hit_count+1'b1;
                else miss_count<=miss_count+1'b1;
            end
            if((|we) && hit) begin
                // Refill forwarding also handles a store immediately after a miss.
                for(lane=0;lane<4;lane=lane+1)
                    words[idx][lane*8+:8]<=we[lane] ? wdata[lane*8+:8] : lookup[lane*8+:8];
            end
        end
    end
end
endmodule
