// Radix-2 restoring division. Each request performs 32 quotient-bit iterations.
// Outputs and complete remain stable until the next request, including EX stalls.
module divider32(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,//开始标志：1为开始
    input  wire        div_signed,//符号控制
    input  wire [31:0] dividend,//被除数
    input  wire [31:0] divisor,//除数
    output reg         busy,//计算状态：1为正在计算
    output reg         complete,//完成标志：1为已完成
    output reg  [31:0] quotient,//商
    output reg  [31:0] remainder//余数
);

reg [31:0] quotient_work;//保存迭代中的商，同时最初存放被除数
reg [31:0] remainder_work;//保存当前的部分余数
reg [31:0] divisor_abs;//除数绝对值
reg [5:0]  count;//计算次数
reg        quotient_negative;//商是否为负
reg        remainder_negative;//余数是否为负

wire dividend_negative = div_signed && dividend[31];
wire divisor_negative  = div_signed && divisor[31];
wire [31:0] dividend_abs = dividend_negative ? (~dividend + 32'd1) : dividend;
wire [31:0] divisor_magnitude = divisor_negative ? (~divisor + 32'd1) : divisor;
wire [32:0] shifted_remainder = {remainder_work, quotient_work[31]};
wire can_subtract = shifted_remainder >= {1'b0, divisor_abs};
wire [32:0] next_remainder = can_subtract ?
                            shifted_remainder - {1'b0, divisor_abs} : shifted_remainder;
wire [31:0] next_quotient = {quotient_work[30:0], can_subtract};

always @(posedge clk) begin
    if (reset) begin
        busy               <= 1'b0;
        complete           <= 1'b0;
        quotient           <= 32'd0;
        remainder          <= 32'd0;
        quotient_work      <= 32'd0;
        remainder_work     <= 32'd0;
        divisor_abs        <= 32'd0;
        count              <= 6'd0;
        quotient_negative  <= 1'b0;
        remainder_negative <= 1'b0;
    end else if (start && !busy) begin
        busy               <= 1'b1;
        complete           <= 1'b0;
        quotient_work      <= dividend_abs;
        remainder_work     <= 32'd0;
        divisor_abs        <= divisor_magnitude;
        count              <= 6'd0;
        quotient_negative  <= dividend_negative ^ divisor_negative;
        remainder_negative <= dividend_negative;
    end else if (busy) begin
        quotient_work  <= next_quotient;
        remainder_work <= next_remainder[31:0];
        count          <= count + 6'd1;
        if (count == 6'd31) begin
            busy      <= 1'b0;
            complete  <= 1'b1;
            quotient  <= quotient_negative ? (~next_quotient + 32'd1) : next_quotient;
            remainder <= remainder_negative ? (~next_remainder[31:0] + 32'd1) :
                                               next_remainder[31:0];
        end
    end
end

endmodule
