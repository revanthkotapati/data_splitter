`timescale 1ps/1ps

module tb_stream_splitter_dp_ram;
  // Parameters
  parameter int TOTAL_SAMPLES = 3276;
  parameter int IDLE_CYCLES   = 1172;

  // 1.Port List
  logic clk;
  logic rst_n;

  // AXI-Stream Slave (input to DUT)
  logic        s_tvalid;
  logic [63:0] s_tdata;
  logic        s_tready;

  // AXI-Stream Masters (outputs from DUT)
  logic        m0_tvalid;
  logic [31:0] m0_tdata;
  logic        m0_tready;

  logic        m1_tvalid;
  logic [31:0] m1_tdata;
  logic        m1_tready;

  // 2.Internal Variables
  int read_fd;
  int expected0_fd;
  int expected1_fd;
  int wait_n;
  int data_counter;
  logic [63:0] input_val;
  logic [31:0] expected0_val;
  logic [31:0] expected1_val;

  // 3.Input Files and Output Files
  localparam string INPUT_DATA_FILE      = "stream_input_data.csv"; // 64-bit hex, one per line
  localparam string EXPECTED_M0_FILE     = "stream_expected_m0.csv";      // lower 32-bit expected
  localparam string EXPECTED_M1_FILE     = "stream_expected_m1.csv";      // upper 32-bit expected

  // 4.Design Module Instantiation
  stream_splitter_dp_ram #(
    .TOTAL_SAMPLES(TOTAL_SAMPLES),
    .IDLE_CYCLES  (IDLE_CYCLES)
  ) DUT (
    .clk      (clk),
    .rst_n    (rst_n),
    .s_tdata  (s_tdata),
    .s_tvalid (s_tvalid),
    .s_tready (s_tready),
    .m0_tdata (m0_tdata),
    .m0_tvalid(m0_tvalid),
    .m0_tready(m0_tready),
    .m1_tdata (m1_tdata),
    .m1_tvalid(m1_tvalid),
    .m1_tready(m1_tready)
  );

  // 5.Clock Generation (10ns period)
  initial clk = 0;
  always #1 clk = ~clk;

  // 6.Reset Task (rst_n is active-low in DUT)
  task automatic reset_task;
  begin
    rst_n <= 0;
    repeat (3) @(posedge clk);
    rst_n <= 1;
    $display("INFO: Reset released at time %0t", $time);
  end
  endtask

  // 7. Input Conditions / Top-level orchestration
  initial begin
    // init
    clk = 0;
    rst_n = 0;
    s_tvalid = 0;
    s_tdata  = 64'h0;
    m0_tready = 0;
    m1_tready = 0;
    data_counter = 0;
    m0_tready = 1;
    m1_tready = 1;

    // Apply reset
    repeat (1) @(posedge clk);
    reset_task();

    // Start tasks: send input and verify outputs
    // Throttle parameter controls random idle delays inside tasks
    fork
      send_input_from_file(INPUT_DATA_FILE, 0);
      begin
        // give some time for data to flow into DUT before checking outputs
        repeat (800000) @(posedge clk);
        read_and_check_outputs(EXPECTED_M0_FILE, EXPECTED_M1_FILE, 2);
      end
    join

    $display("TESTBENCH: Simulation completed at time %0t.", $time);
    #900000;
   // $finish;
  end

  // 8. Input Data Feeding Task
  // Reads 64-bit hex words (one per line) and drives s_tdata/s_tvalid using handshake with s_tready.
  task automatic send_input_from_file(input string FILE_NAME, input int throttle);
  begin
    read_fd = $fopen(FILE_NAME, "r");
    if (read_fd == 0) begin
      $fatal("ERROR: Could not open input file '%s'.", FILE_NAME);
    end

    data_counter = 0;
    // Drive inputs while there are lines in the file
    while ($fscanf(read_fd, "%h\n", input_val) == 1) begin
      // Wait a clock edge and try to send
      @(posedge clk);
      s_tdata  <= input_val;
      s_tvalid <= 1;
      // wait for slave ready
//      while (!s_tready) begin
//        @(posedge clk);
//      end
      // One more cycle to register the handshake
     // @(posedge clk);
      data_counter <= data_counter + 1;
      $display("INFO: Sent input #%0d : %016h at time %0t", data_counter, input_val, $time);
      //s_tvalid <= 1;
      // random throttle / idle between samples (keeps variable spacing at input)
      wait_n = $urandom % throttle;
      //repeat (wait_n) @(posedge clk);
    end

    $fclose(read_fd);
    $display("INFO: All input data from '%s' sent (%0d lines).", FILE_NAME, data_counter);
  end
  endtask
int out_count = 0;
  // 9. Self-Checking Task
  // Reads expected outputs from two files and checks DUT outputs when m?_tvalid asserted.
  task automatic read_and_check_outputs(input string FILE_M0, input string FILE_M1, input int throttle);
  begin
    expected0_fd = $fopen(FILE_M0, "r");
    if (expected0_fd == 0) $fatal("ERROR: Could not open expected M0 file '%s'.", FILE_M0);
    expected1_fd = $fopen(FILE_M1, "r");
    if (expected1_fd == 0) $fatal("ERROR: Could not open expected M1 file '%s'.", FILE_M1);

    // Set consumers ready
//    m0_tready <= 1;
//    m1_tready <= 1;

   // int out_count = 0;
    // Keep checking until both expected files are exhausted
    while (!$feof(expected0_fd) || !$feof(expected1_fd)) begin
      @(posedge clk);

      // When both valids appear, read and compare corresponding expected lines
      if (m0_tvalid) begin
        if ($fscanf(expected0_fd, "%h\n", expected0_val) != 1) begin
          $fatal("ERROR: Unexpected EOF or format error in '%s' at output #%0d", FILE_M0, out_count+1);
        end
        if (m0_tdata === expected0_val) begin
          $display("PASS M0: #%0d time %0t -> got %08h expected %08h", out_count+1, $time, m0_tdata, expected0_val);
        end else begin
          $display("FAIL M0: #%0d time %0t -> got %08h expected %08h", out_count+1, $time, m0_tdata, expected0_val);
          $fatal("TEST FAILED (M0 mismatch) at time %0t", $time);
        end
      end

      if (m1_tvalid) begin
        if ($fscanf(expected1_fd, "%h\n", expected1_val) != 1) begin
          $fatal("ERROR: Unexpected EOF or format error in '%s' at output #%0d", FILE_M1, out_count+1);
        end
        if (m1_tdata === expected1_val) begin
          $display("PASS M1: #%0d time %0t -> got %08h expected %08h", out_count+1, $time, m1_tdata, expected1_val);
        end else begin
          $display("FAIL M1: #%0d time %0t -> got %08h expected %08h", out_count+1, $time, m1_tdata, expected1_val);
          $fatal("TEST FAILED (M1 mismatch) at time %0t", $time);
        end
      end

      // When either valid was seen, increment out_count (approximate, counts events)
      if (m0_tvalid || m1_tvalid) out_count++;

      // optional random throttle between checks
      wait_n = $urandom % throttle;
      repeat (wait_n) @(posedge clk);
    end

    // Close files
    $fclose(expected0_fd);
    $fclose(expected1_fd);
    $display("INFO: Output verification completed successfully.");
  end
  endtask

endmodule
