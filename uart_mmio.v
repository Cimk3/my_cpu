// UART 8N1. Synchronous one-cycle MMIO read, byte-enable writes, RX interrupt.
// offsets: 00 DATA,04 STATUS,08 DIVISOR,0c IRQ_ENABLE,10 CLEAR (W1C).
// STATUS: bit0 TX ready, bit1 RX valid, bit2 overrun, bit3 frame error.
module uart_mmio #(parameter CLOCK_HZ=50000000, parameter BAUD=115200)(
    input wire clk, reset, en,
    input wire [3:0] we,
    input wire [4:0] addr,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    input wire rx,
    output wire tx, irq
);
reg [15:0] divisor;
reg rx_meta,rx_sync;
reg [9:0] tx_shift;
reg [3:0] tx_bits;
reg [15:0] tx_count;
reg [1:0] rx_state;
reg [15:0] rx_count;
reg [2:0] rx_bit;
reg [7:0] rx_shift,rx_data;
reg rx_valid,overrun,frame_error,irq_enable;
wire [15:0] baud_ticks=divisor<4 ? 16'd4 : divisor;
wire write_data=en && we[0] && addr[4:2]==0;
wire read_data=en && !(|we) && addr[4:2]==0;
wire clear_flags=en && we[0] && addr[4:2]==4;
assign tx=tx_bits==0 ? 1'b1 : tx_shift[0];
assign irq=irq_enable && rx_valid;
always @(posedge clk) begin
    if(reset) begin
        divisor<=CLOCK_HZ/BAUD;
        rx_meta<=1;rx_sync<=1;tx_shift<=10'h3ff;tx_bits<=0;tx_count<=0;
        rx_state<=0;rx_count<=0;rx_bit<=0;rx_shift<=0;rx_data<=0;
        rx_valid<=0;overrun<=0;frame_error<=0;irq_enable<=0;rdata<=0;
    end else begin
        rx_meta<=rx;rx_sync<=rx_meta;
        if(en) begin
            case(addr[4:2])
            0:rdata<={24'b0,rx_data};
            1:rdata<={28'b0,frame_error,overrun,rx_valid,(tx_bits==0)};
            2:rdata<={16'b0,divisor};
            3:rdata<={31'b0,irq_enable};
            default:rdata<=0;
            endcase
            if(addr[4:2]==2) begin
                if(we[0])divisor[7:0]<=wdata[7:0];
                if(we[1])divisor[15:8]<=wdata[15:8];
            end
            if(addr[4:2]==3 && we[0])irq_enable<=wdata[0];
        end
        if(read_data || (clear_flags && wdata[0]))rx_valid<=0;
        if(clear_flags && wdata[1])overrun<=0;
        if(clear_flags && wdata[2])frame_error<=0;
        if(write_data && tx_bits==0) begin
            tx_shift<={1'b1,wdata[7:0],1'b0};tx_bits<=10;tx_count<=baud_ticks-1'b1;
        end else if(tx_bits!=0) begin
            if(tx_count==0) begin
                tx_shift<={1'b1,tx_shift[9:1]};tx_bits<=tx_bits-1'b1;tx_count<=baud_ticks-1'b1;
            end else tx_count<=tx_count-1'b1;
        end
        case(rx_state)
        0:if(!rx_sync)begin rx_state<=1;rx_count<=(baud_ticks>>1)-1'b1;end
        1:if(rx_count!=0)rx_count<=rx_count-1'b1;
          else if(rx_sync)rx_state<=0;
          else begin rx_state<=2;rx_count<=baud_ticks-1'b1;rx_bit<=0;end
        2:if(rx_count!=0)rx_count<=rx_count-1'b1;
          else begin
              rx_shift[rx_bit]<=rx_sync;rx_count<=baud_ticks-1'b1;
              if(rx_bit==7)rx_state<=3;else rx_bit<=rx_bit+1'b1;
          end
        3:if(rx_count!=0)rx_count<=rx_count-1'b1;
          else begin
              rx_state<=0;
              if(!rx_sync)frame_error<=1;
              else begin
                  if(rx_valid && !read_data)overrun<=1;
                  rx_data<=rx_shift;rx_valid<=1;
              end
          end
        endcase
    end
end
endmodule
