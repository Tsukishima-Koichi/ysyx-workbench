// Auto-generated SRAM behavioral models

module array_0_0_ext(
    input  [8:0] R0_addr, input R0_en, input R0_clk, output [63:0] R0_data,
    input  [8:0] W0_addr, input W0_en, input W0_clk, input [63:0] W0_data,
    input  [1:0] W0_mask
);
    reg [63:0] mem [0:511];
    reg [63:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][31:0] <= W0_data[31:0];
        if (W0_mask[1]) mem[W0_addr][63:32] <= W0_data[63:32];
    end
endmodule

module btb_0_ext(
    input  [6:0] R0_addr, input R0_en, input R0_clk, output [55:0] R0_data,
    input  [6:0] W0_addr, input W0_en, input W0_clk, input [55:0] W0_data,
    input  [3:0] W0_mask
);
    reg [55:0] mem [0:127];
    reg [55:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][13:0] <= W0_data[13:0];
        if (W0_mask[1]) mem[W0_addr][27:14] <= W0_data[27:14];
        if (W0_mask[2]) mem[W0_addr][41:28] <= W0_data[41:28];
        if (W0_mask[3]) mem[W0_addr][55:42] <= W0_data[55:42];
    end
endmodule

module cc_banks_0_ext(
    input  [13:0] RW0_addr, input RW0_en, input RW0_clk, input RW0_wmode,
    input  [63:0] RW0_wdata, output [63:0] RW0_rdata
);
    reg [63:0] mem [0:16383];
    reg [63:0] rd;
    always @(posedge RW0_clk) begin
        if (RW0_en) begin
            if (RW0_wmode) mem[RW0_addr] <= RW0_wdata;
            else rd <= mem[RW0_addr];
        end
    end
    assign RW0_rdata = rd;
endmodule

module cc_dir_ext(
    input  [9:0] RW0_addr, input RW0_en, input RW0_clk, input RW0_wmode,
    input  [135:0] RW0_wdata, output [135:0] RW0_rdata, input [7:0] RW0_wmask
);
    reg [135:0] mem [0:1023];
    reg [135:0] rd;
    always @(posedge RW0_clk) begin
        if (RW0_en) begin
            if (RW0_wmode) begin
                if (RW0_wmask[0]) mem[RW0_addr][16:0] <= RW0_wdata[16:0];
                if (RW0_wmask[1]) mem[RW0_addr][33:17] <= RW0_wdata[33:17];
                if (RW0_wmask[2]) mem[RW0_addr][50:34] <= RW0_wdata[50:34];
                if (RW0_wmask[3]) mem[RW0_addr][67:51] <= RW0_wdata[67:51];
                if (RW0_wmask[4]) mem[RW0_addr][84:68] <= RW0_wdata[84:68];
                if (RW0_wmask[5]) mem[RW0_addr][101:85] <= RW0_wdata[101:85];
                if (RW0_wmask[6]) mem[RW0_addr][118:102] <= RW0_wdata[118:102];
                if (RW0_wmask[7]) mem[RW0_addr][135:119] <= RW0_wdata[135:119];
            end else
                rd <= mem[RW0_addr];
        end
    end
    assign RW0_rdata = rd;
endmodule

module dataArrayWay_0_ext(
    input  [8:0] RW0_addr, input RW0_en, input RW0_clk, input RW0_wmode,
    input  [63:0] RW0_wdata, output [63:0] RW0_rdata
);
    reg [63:0] mem [0:511];
    reg [63:0] rd;
    always @(posedge RW0_clk) begin
        if (RW0_en) begin
            if (RW0_wmode) mem[RW0_addr] <= RW0_wdata;
            else rd <= mem[RW0_addr];
        end
    end
    assign RW0_rdata = rd;
endmodule

module data_ext(
    input  [10:0] R0_addr, input R0_en, input R0_clk, output [7:0] R0_data,
    input  [10:0] W0_addr, input W0_en, input W0_clk, input [7:0] W0_data,
    input  [3:0] W0_mask
);
    reg [7:0] mem [0:2047];
    reg [7:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][1:0] <= W0_data[1:0];
        if (W0_mask[1]) mem[W0_addr][3:2] <= W0_data[3:2];
        if (W0_mask[2]) mem[W0_addr][5:4] <= W0_data[5:4];
        if (W0_mask[3]) mem[W0_addr][7:6] <= W0_data[7:6];
    end
endmodule

module ebtb_ext(
    input  [6:0] R0_addr, input R0_en, input R0_clk, output [31:0] R0_data,
    input  [6:0] W0_addr, input W0_en, input W0_clk, input [31:0] W0_data
);
    reg [31:0] mem [0:127];
    reg [31:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) mem[W0_addr] <= W0_data;
endmodule

module ghist_0_ext(
    input  [3:0] R0_addr, input R0_en, input R0_clk, output [71:0] R0_data,
    input  [3:0] W0_addr, input W0_en, input W0_clk, input [71:0] W0_data
);
    reg [71:0] mem [0:15];
    reg [71:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) mem[W0_addr] <= W0_data;
endmodule

module hi_us_0_ext(
    input  [7:0] R0_addr, input R0_en, input R0_clk, output [3:0] R0_data,
    input  [7:0] W0_addr, input W0_en, input W0_clk, input [3:0] W0_data,
    input  [3:0] W0_mask
);
    reg [3:0] mem [0:255];
    reg [3:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][0:0] <= W0_data[0:0];
        if (W0_mask[1]) mem[W0_addr][1:1] <= W0_data[1:1];
        if (W0_mask[2]) mem[W0_addr][2:2] <= W0_data[2:2];
        if (W0_mask[3]) mem[W0_addr][3:3] <= W0_data[3:3];
    end
endmodule

module hi_us_ext(
    input  [6:0] R0_addr, input R0_en, input R0_clk, output [3:0] R0_data,
    input  [6:0] W0_addr, input W0_en, input W0_clk, input [3:0] W0_data,
    input  [3:0] W0_mask
);
    reg [3:0] mem [0:127];
    reg [3:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][0:0] <= W0_data[0:0];
        if (W0_mask[1]) mem[W0_addr][1:1] <= W0_data[1:1];
        if (W0_mask[2]) mem[W0_addr][2:2] <= W0_data[2:2];
        if (W0_mask[3]) mem[W0_addr][3:3] <= W0_data[3:3];
    end
endmodule

module l2_tlb_ram_ext(
    input  [8:0] RW0_addr, input RW0_en, input RW0_clk, input RW0_wmode,
    input  [37:0] RW0_wdata, output [37:0] RW0_rdata
);
    reg [37:0] mem [0:511];
    reg [37:0] rd;
    always @(posedge RW0_clk) begin
        if (RW0_en) begin
            if (RW0_wmode) mem[RW0_addr] <= RW0_wdata;
            else rd <= mem[RW0_addr];
        end
    end
    assign RW0_rdata = rd;
endmodule

module mem_ext(
    input  [12:0] RW0_addr, input RW0_en, input RW0_clk, input RW0_wmode,
    input  [63:0] RW0_wdata, output [63:0] RW0_rdata, input [7:0] RW0_wmask
);
    reg [63:0] mem [0:8191];
    reg [63:0] rd;
    always @(posedge RW0_clk) begin
        if (RW0_en) begin
            if (RW0_wmode) begin
                if (RW0_wmask[0]) mem[RW0_addr][7:0] <= RW0_wdata[7:0];
                if (RW0_wmask[1]) mem[RW0_addr][15:8] <= RW0_wdata[15:8];
                if (RW0_wmask[2]) mem[RW0_addr][23:16] <= RW0_wdata[23:16];
                if (RW0_wmask[3]) mem[RW0_addr][31:24] <= RW0_wdata[31:24];
                if (RW0_wmask[4]) mem[RW0_addr][39:32] <= RW0_wdata[39:32];
                if (RW0_wmask[5]) mem[RW0_addr][47:40] <= RW0_wdata[47:40];
                if (RW0_wmask[6]) mem[RW0_addr][55:48] <= RW0_wdata[55:48];
                if (RW0_wmask[7]) mem[RW0_addr][63:56] <= RW0_wdata[63:56];
            end else
                rd <= mem[RW0_addr];
        end
    end
    assign RW0_rdata = rd;
endmodule

module meta_0_ext(
    input  [6:0] R0_addr, input R0_en, input R0_clk, output [91:0] R0_data,
    input  [6:0] W0_addr, input W0_en, input W0_clk, input [91:0] W0_data,
    input  [3:0] W0_mask
);
    reg [91:0] mem [0:127];
    reg [91:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][22:0] <= W0_data[22:0];
        if (W0_mask[1]) mem[W0_addr][45:23] <= W0_data[45:23];
        if (W0_mask[2]) mem[W0_addr][68:46] <= W0_data[68:46];
        if (W0_mask[3]) mem[W0_addr][91:69] <= W0_data[91:69];
    end
endmodule

module meta_ext(
    input  [3:0] R0_addr, input R0_en, input R0_clk, output [119:0] R0_data,
    input  [3:0] W0_addr, input W0_en, input W0_clk, input [119:0] W0_data
);
    reg [119:0] mem [0:15];
    reg [119:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) mem[W0_addr] <= W0_data;
endmodule

module table_0_ext(
    input  [7:0] R0_addr, input R0_en, input R0_clk, output [47:0] R0_data,
    input  [7:0] W0_addr, input W0_en, input W0_clk, input [47:0] W0_data,
    input  [3:0] W0_mask
);
    reg [47:0] mem [0:255];
    reg [47:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][11:0] <= W0_data[11:0];
        if (W0_mask[1]) mem[W0_addr][23:12] <= W0_data[23:12];
        if (W0_mask[2]) mem[W0_addr][35:24] <= W0_data[35:24];
        if (W0_mask[3]) mem[W0_addr][47:36] <= W0_data[47:36];
    end
endmodule

module table_1_ext(
    input  [6:0] R0_addr, input R0_en, input R0_clk, output [51:0] R0_data,
    input  [6:0] W0_addr, input W0_en, input W0_clk, input [51:0] W0_data,
    input  [3:0] W0_mask
);
    reg [51:0] mem [0:127];
    reg [51:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][12:0] <= W0_data[12:0];
        if (W0_mask[1]) mem[W0_addr][25:13] <= W0_data[25:13];
        if (W0_mask[2]) mem[W0_addr][38:26] <= W0_data[38:26];
        if (W0_mask[3]) mem[W0_addr][51:39] <= W0_data[51:39];
    end
endmodule

module table_ext(
    input  [6:0] R0_addr, input R0_en, input R0_clk, output [43:0] R0_data,
    input  [6:0] W0_addr, input W0_en, input W0_clk, input [43:0] W0_data,
    input  [3:0] W0_mask
);
    reg [43:0] mem [0:127];
    reg [43:0] rd;
    always @(posedge R0_clk) if (R0_en) rd <= mem[R0_addr];
    assign R0_data = rd;
    always @(posedge W0_clk) if (W0_en) begin
        if (W0_mask[0]) mem[W0_addr][10:0] <= W0_data[10:0];
        if (W0_mask[1]) mem[W0_addr][21:11] <= W0_data[21:11];
        if (W0_mask[2]) mem[W0_addr][32:22] <= W0_data[32:22];
        if (W0_mask[3]) mem[W0_addr][43:33] <= W0_data[43:33];
    end
endmodule

module tag_array_0_ext(
    input  [5:0] RW0_addr, input RW0_en, input RW0_clk, input RW0_wmode,
    input  [79:0] RW0_wdata, output [79:0] RW0_rdata, input [3:0] RW0_wmask
);
    reg [79:0] mem [0:63];
    reg [79:0] rd;
    always @(posedge RW0_clk) begin
        if (RW0_en) begin
            if (RW0_wmode) begin
                if (RW0_wmask[0]) mem[RW0_addr][19:0] <= RW0_wdata[19:0];
                if (RW0_wmask[1]) mem[RW0_addr][39:20] <= RW0_wdata[39:20];
                if (RW0_wmask[2]) mem[RW0_addr][59:40] <= RW0_wdata[59:40];
                if (RW0_wmask[3]) mem[RW0_addr][79:60] <= RW0_wdata[79:60];
            end else
                rd <= mem[RW0_addr];
        end
    end
    assign RW0_rdata = rd;
endmodule

module tag_array_ext(
    input  [5:0] RW0_addr, input RW0_en, input RW0_clk, input RW0_wmode,
    input  [87:0] RW0_wdata, output [87:0] RW0_rdata, input [3:0] RW0_wmask
);
    reg [87:0] mem [0:63];
    reg [87:0] rd;
    always @(posedge RW0_clk) begin
        if (RW0_en) begin
            if (RW0_wmode) begin
                if (RW0_wmask[0]) mem[RW0_addr][21:0] <= RW0_wdata[21:0];
                if (RW0_wmask[1]) mem[RW0_addr][43:22] <= RW0_wdata[43:22];
                if (RW0_wmask[2]) mem[RW0_addr][65:44] <= RW0_wdata[65:44];
                if (RW0_wmask[3]) mem[RW0_addr][87:66] <= RW0_wdata[87:66];
            end else
                rd <= mem[RW0_addr];
        end
    end
    assign RW0_rdata = rd;
endmodule

