//============================================================
// 1-to-2 Stream Conversion using Dual-Port RAM (4-Always FSM)
//============================================================
// - Accepts 64-bit AXI-Stream input
// - Stores data into Dual-Port RAM
// - Splits into two 32-bit outputs
// - FSM-controlled read bursts (TOTAL_SAMPLES) and idle gaps (IDLE_CYCLES)
//============================================================

`timescale 1ps/1ps

module stream_splitter_dp_ram #(
    parameter int TOTAL_SAMPLES = 3276,     // number of valid samples
    parameter int IDLE_CYCLES   = 1172,     // number of idle cycles
    parameter int MEM_DEPTH     = 3276*4    // total depth
)(
    input  logic        clk,
    input  logic        rst_n,

    // AXI-Stream Slave Input (64-bit)
    input  logic [63:0] s_tdata,
    input  logic        s_tvalid,
    output logic        s_tready,

    // AXI-Stream Master Outputs (2x 32-bit)
    output logic [31:0] m0_tdata,
    output logic        m0_tvalid,
    input  logic        m0_tready,

    output logic [31:0] m1_tdata,
    output logic        m1_tvalid,
    input  logic        m1_tready
);

    //========================================================
    // 1. FSM State Declaration
    //========================================================
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        BURST = 2'b01,
        GAP   = 2'b10
    } state_t;

    state_t current_state, next_state;

    //========================================================
    // 2. Internal Signals
    //========================================================
    logic [63:0] ram [0:MEM_DEPTH-1];
    logic [$clog2(MEM_DEPTH)-1:0] wr_addr, rd_addr;
    logic [63:0] rd_data;

    logic [15:0] burst_cnt;
    logic [15:0] gap_cnt;

    logic ram_en, wr_en;

    //========================================================
    // 3. SEQ #1 — State Register
    //========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    //========================================================
    // 4. COMB #1 — Next-State Logic
    //========================================================
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE:  if (wr_addr > 0)                next_state = BURST;  // start output when data present
            BURST: if (burst_cnt == TOTAL_SAMPLES) next_state = GAP;
            GAP:   if (gap_cnt   == IDLE_CYCLES)   next_state = IDLE;
        endcase
    end

    //========================================================
    // 5. SEQ #2 — Counters, RAM Access, Pointers
    //========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_addr   <= 0;
            rd_addr   <= 0;
            burst_cnt <= 0;
            gap_cnt   <= 0;
            rd_data   <= 0;
        end else begin
            // Input write (parallel)
            if (s_tvalid && s_tready) begin
                ram[wr_addr] <= s_tdata;
                wr_addr <= wr_addr + 1;
            end

            // FSM controlled output logic
            case (current_state)
                IDLE: begin
                    burst_cnt <= 0;
                    gap_cnt   <= 0;
                    rd_addr   <= 0;
                end

                BURST: begin
                    if (ram_en) begin
                        rd_data   <= ram[rd_addr];
                        rd_addr   <= rd_addr + 1;
                        burst_cnt <= burst_cnt + 1;
                    end
                end

                GAP: begin
                    gap_cnt <= gap_cnt + 1;
                end
            endcase
        end
    end

    //========================================================
    // 6. COMB #2 — Output / Handshake Logic
    //========================================================
    always_comb begin
        // Defaults
        s_tready  = 1'b1;  // always ready to receive input
        m0_tdata  = rd_data[31:0];
        m1_tdata  = rd_data[63:32];
        m0_tvalid = 1'b0;
        m1_tvalid = 1'b0;
        ram_en    = 1'b0;

        case (current_state)
            BURST: begin
                if (m0_tready && m1_tready) begin
                    m0_tvalid = 1'b1;
                    m1_tvalid = 1'b1;
                    ram_en    = 1'b1;
                end
            end

            GAP: begin
                m0_tvalid = 1'b0;
                m1_tvalid = 1'b0;
                ram_en    = 1'b0;
            end

            IDLE: begin
                // prepare for next burst
                ram_en    = 1'b0;
            end
        endcase
    end

endmodule
