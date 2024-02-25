// Default BlockRam implementation of Apple II memory
//
// (c) 2023,2024 Ed Anuff <ed@a2fpga.com> 
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//
// Description:
//
// Handles the writing of data to the shadow memory copy of the Apple II's
// memory that is kept in the FPGA display memory.
//

module apple_memory #(
    parameter VGC_MEMORY = 0  // 1 = extend aux memory to 32KB for VGC, 0 = 16KB
) (
    a2bus_if.slave a2bus_if,
    a2mem_if.master a2mem_if,
    
    input [15:0] video_address_i,
    input video_rd_i,
    output [31:0] video_data_o,

    input vgc_active_i,
    input [12:0] vgc_address_i,
    input vgc_rd_i,
    output [31:0] vgc_data_o

);

    wire write_strobe = !a2bus_if.rw_n && a2bus_if.data_in_strobe;
    wire read_strobe = a2bus_if.rw_n && a2bus_if.data_in_strobe;

   // II Soft switches
    reg SWITCHES_II[8];
    assign a2mem_if.TEXT_MODE = SWITCHES_II[0];
    assign a2mem_if.MIXED_MODE = SWITCHES_II[1];
    assign a2mem_if.PAGE2 = SWITCHES_II[2];
    assign a2mem_if.HIRES_MODE = SWITCHES_II[3];
    assign a2mem_if.AN0 = SWITCHES_II[4];
    assign a2mem_if.AN1 = SWITCHES_II[5];
    assign a2mem_if.AN2 = SWITCHES_II[6];
    assign a2mem_if.AN3 = SWITCHES_II[7];

    // ][e auxilary switches
    reg SWITCHES_IIE[8];
    assign a2mem_if.STORE80 = SWITCHES_IIE[0];
    assign a2mem_if.RAMRD = SWITCHES_IIE[1];
    assign a2mem_if.RAMWRT = SWITCHES_IIE[2];
    assign a2mem_if.CXROM = SWITCHES_IIE[3];
    assign a2mem_if.ALTZP = SWITCHES_IIE[4];
    assign a2mem_if.C3ROM = SWITCHES_IIE[5];
    assign a2mem_if.COL80 = SWITCHES_IIE[6];
    assign a2mem_if.ALTCHAR = SWITCHES_IIE[7];

    // capture the soft switches
    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.system_reset_n) begin
        if (!a2bus_if.system_reset_n) begin
            SWITCHES_II <= '{1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1};
        end else if ((a2bus_if.phi1_posedge) && (a2bus_if.addr[15:4] == 12'hC05) && !a2bus_if.m2sel_n)
            SWITCHES_II[a2bus_if.addr[3:1]] <= a2bus_if.addr[0];
    end

    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.system_reset_n) begin
        if (!a2bus_if.system_reset_n) begin
            SWITCHES_IIE <= '{8{1'b0}};
        end else if (!a2bus_if.rw_n && (a2bus_if.phi1_posedge) && (a2bus_if.addr[15:4] == 12'hC00) && !a2bus_if.m2sel_n) 
            SWITCHES_IIE[a2bus_if.addr[3:1]] <= a2bus_if.addr[0];
    end

    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.device_reset_n) begin
        if (!a2bus_if.device_reset_n) begin
            a2mem_if.BACKGROUND_COLOR <= 4'h0;
            a2mem_if.TEXT_COLOR <= 4'hF;
        end else if (write_strobe && (a2bus_if.addr == 16'hC022)) begin
            a2mem_if.BACKGROUND_COLOR <= a2bus_if.data[3:0];
            a2mem_if.TEXT_COLOR <= a2bus_if.data[7:4];
        end
    end

    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.device_reset_n) begin
        if (!a2bus_if.device_reset_n) begin
            a2mem_if.BORDER_COLOR <= 4'h0;
        end else if (write_strobe && (a2bus_if.addr == 16'hC034)) begin
            a2mem_if.BORDER_COLOR <= a2bus_if.data[3:0];
        end
    end

    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.system_reset_n) begin
        if (!a2bus_if.system_reset_n) begin
            a2mem_if.MONOCHROME_MODE <= 1'b0;
        end else if (write_strobe && (a2bus_if.addr == 16'hC021)) begin
            a2mem_if.MONOCHROME_MODE <= a2bus_if.data[7];
        end
    end

    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.system_reset_n) begin
        if (!a2bus_if.system_reset_n) begin
            a2mem_if.MONOCHROME_DHIRES_MODE <= 1'b0;
            a2mem_if.SHRG_MODE <= 1'b0;
        end else if (write_strobe && (a2bus_if.addr == 16'hC029)) begin
            a2mem_if.MONOCHROME_DHIRES_MODE <= a2bus_if.data[5];
            a2mem_if.SHRG_MODE <= a2bus_if.data[7];
        end
    end

    reg [7:0] keycode_r;
    reg keypress_strobe_r;

    always @(posedge a2bus_if.clk_logic or negedge a2bus_if.system_reset_n) begin
        if (!a2bus_if.system_reset_n) begin
            keycode_r <= 8'h00;
            keypress_strobe_r <= 1'b0;
        end else begin
            keypress_strobe_r <= 1'b0;
            if (read_strobe && (a2bus_if.addr == 16'hC000)) begin
                if (a2bus_if.data[7] & !keycode_r[7]) begin
                    keycode_r <= a2bus_if.data;
                    keypress_strobe_r <= 1'b1;
                end
            end else if (a2bus_if.data_in_strobe && (a2bus_if.addr == 16'hC010)) begin
                keycode_r[7] <= 1'b0;
            end
        end
    end

    assign a2mem_if.keycode = keycode_r;
    assign a2mem_if.keypress_strobe = keypress_strobe_r;

    reg aux_mem_r;
    
    always @(*)
    begin: aux_ctrl
        aux_mem_r = 1'b0;
        if (a2bus_if.addr[15:9] == 7'b0000000 | a2bus_if.addr[15:14] == 2'b11)		// Page 00,01,C0-FF
            aux_mem_r = a2mem_if.ALTZP;
        else if (a2bus_if.addr[15:10] == 6'b000001)		// Page 04-07
            aux_mem_r = (a2mem_if.STORE80 & a2mem_if.PAGE2) | ((~a2mem_if.STORE80) & (a2mem_if.RAMWRT & !a2bus_if.rw_n));
        else if (a2bus_if.addr[15:13] == 3'b001)		// Page 20-3F
            aux_mem_r = (a2mem_if.STORE80 & a2mem_if.PAGE2 & a2mem_if.HIRES_MODE) | (((~a2mem_if.STORE80) | (~a2mem_if.HIRES_MODE)) & (a2mem_if.RAMWRT & !a2bus_if.rw_n));
        else
            aux_mem_r = (a2mem_if.RAMWRT & !a2bus_if.rw_n);
    end
    assign a2mem_if.aux_mem = aux_mem_r;

    // Original 16-bit address space
    //                1111 1100 0000 0000
    //                5432 1098 7654 3210
    // 16'h0400 = 16'b0000_0100_0000_0000
    // 16'h0BFF = 16'b0000_1011_1111_1111
    // 16'h2000 = 16'b0010_0000_0000_0000
    // 16'h5FFF = 16'b0101_1111_1111_1111
    // 16'h6000 = 16'b0110_0000_0000_0000
    // 16'9FFFF = 16'b1001_1111_1111_1111

    // Text offset mapping
    // 16'h0000 = 16'b0000_0000_0000_0000 (0x0400)
    // 16'h07FF = 16'b0000_0111_1111_1111 (0x0BFF)

    // Hires offset mapping
    // 16'h0000 = 16'b0000_0000_0000_0000 (0x2000)
    // 16'h3FFF = 16'b0011_1111_1111_1111 (0x5FFF)
    // 16'h4000 = 16'b0100_0000_0000_0000 (0x6000)
    // 16'h7FFF = 16'b0111_1111_1111_1111 (0x9FFF)

    wire E1 = aux_mem_r || a2bus_if.m2b0;

    // Apple II bus address ranges
    wire bus_addr_0400_0BFF = a2bus_if.addr[15:10] inside {6'b000001, 3'b000010};
    wire bus_addr_2000_5FFF = a2bus_if.addr[15:13] inside {3'b001, 3'b010};
    wire bus_addr_6000_9FFF = a2bus_if.addr[15:13] inside {3'b011, 3'b100};
    wire bus_addr_2000_9FFF = bus_addr_2000_5FFF || bus_addr_6000_9FFF;

    // write offsets from the base addresses
    // only valid when address is in the range
    wire [11:0] text_write_offset = {!a2bus_if.addr[10], a2bus_if.addr[9:0], E1};
    wire [14:0] hires_write_offset = 15'({3'(a2bus_if.addr[15:13] - 1'b1), a2bus_if.addr[12:0]});

    // Apple II video scanner address ranges
    wire video_addr_0400_0BFF = video_address_i[15:10] inside {6'b000001, 3'b000010};
    wire video_addr_2000_5FFF = video_address_i[15:13] inside {3'b001, 3'b010};

    // read offsets from the base addresses
    // only valid when address is in the range
    wire [9:0] text_read_offset = {!video_address_i[10], video_address_i[9:1]};
    wire [11:0] hires_main_read_offset = {!video_address_i[13], video_address_i[12:2]};
    wire [12:0] hires_aux_read_offset = vgc_active_i ? vgc_address_i : {1'b0, hires_main_read_offset};

    wire [31:0] text_data;
    wire [31:0] hires_data_main;
    wire [31:0] hires_data_aux;

    assign vgc_data_o = vgc_active_i ? hires_data_aux : 32'b0;

    wire [31:0] hires_data_lo = {hires_data_aux[15:8], hires_data_main[15:8], hires_data_aux[7:0], hires_data_main[7:0]};
    wire [31:0] hires_data_hi = {hires_data_aux[31:24], hires_data_main[31:24], hires_data_aux[23:16], hires_data_main[23:16]};

    logic [31:0] video_data_w;
    always_comb begin
        if (vgc_active_i) video_data_w = 32'b0;
        else if (video_addr_0400_0BFF) video_data_w = text_data;
        else if (video_addr_2000_5FFF) video_data_w = video_address_i[1] ? hires_data_hi : hires_data_lo;
        else video_data_w  = 32'b0;
    end
    assign video_data_o = video_data_w;

    wire [31:0] write_word = {a2bus_if.data, a2bus_if.data, a2bus_if.data, a2bus_if.data};

    // Instantiate the video memory shadow copy in the BSRAM

    // Text memory
    // Main and Aux banks interleaved

    sdpram32 #(
        .ADDR_WIDTH(10)
    ) text_vram (
        .clk(a2bus_if.clk_logic),
        .write_addr(text_write_offset[11:2]),
        .write_data(write_word),
        .write_enable(write_strobe && bus_addr_0400_0BFF),
        .byte_enable(4'(1 << text_write_offset[1:0])),
        .read_addr(text_read_offset),
        .read_enable(1'b1),
        .read_data(text_data)
    );

    // Hires memory

    // Main memory bank, linear

    sdpram32 #(
        .ADDR_WIDTH(12)
    ) hires_main (
        .clk(a2bus_if.clk_logic),
        .write_addr(hires_write_offset[13:2]),
        .write_data(write_word),
        .write_enable(write_strobe && bus_addr_2000_5FFF && !E1),
        .byte_enable(4'(1 << hires_write_offset[1:0])),
        .read_addr(hires_main_read_offset[11:0]),
        .read_enable(1'b1),
        .read_data(hires_data_main)
    );  

    // Aux memory bank, linear

    localparam HIRES_AUX_ADDR_WIDTH = VGC_MEMORY? 13 : 12;
    wire write_aux_addr_valid = VGC_MEMORY ? bus_addr_2000_9FFF : bus_addr_2000_5FFF;

    sdpram32 #(
        .ADDR_WIDTH(HIRES_AUX_ADDR_WIDTH)
    ) hires_aux (
        .clk(a2bus_if.clk_logic),
        .write_addr(hires_write_offset[HIRES_AUX_ADDR_WIDTH + 1:2]),
        .write_data(write_word),
        .write_enable(write_strobe && write_aux_addr_valid && E1),
        .byte_enable(4'(1 << hires_write_offset[1:0])),
        .read_addr(hires_aux_read_offset[HIRES_AUX_ADDR_WIDTH - 1:0]),
        .read_enable(1'b1),
        .read_data(hires_data_aux)
    );

endmodule