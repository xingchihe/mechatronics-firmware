/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013 ERC CISST, Johns Hopkins University.
 *
 * Module: UART interface for QLA board
 *
 * Purpose: Modules for UART communication
 * 
 * Revision history
 *     10/26/13    Zihan Chen    Initial revision
 */
 
 /**************************************************************
  * NOTE:
  *  - UART: Universal Asynchronous Receive & Transmit
  *  - Hardware Connection
  *       / TX  ----->    RX \
  *    PC                      FPGA 
  *       \ RX  <-----    TX / 
  *    
  *    Chip: USB -> COM  
  *    PC: /dev/ttyUSBx   
  *
  *  - Testing: 
  *     - picocom -b 115200 /dev/ttyUSB0 
  **/

// ---------------------------------------------  
//    1-bit Start 8-bit Data 0-bit Disparity 1-bit Stop 
//    Baud = 115200 
// --------------------------------------------- 


// -----------------------------------------------------------------------------
//  UART Control Module 
//    - 1 Rx Module + 1 Tx Module 
//    - Logical 
//  
//  The rest rx_rdata, rx_wdata, rx_addr will remain the same as 1394 interface. 
//  UART Protocal 
//    - 1 byte: 3-bit cmd + 5-bit data length
//    - 2 byte: 8-bit addr 
//    ------ END READ -------
//    - 3-n write byte
//   
//  Command Table 
//    000: quadlet read
//    001: block read
//    010: quadlet write
//    011: block write
//    100: start UART control
//    101: close UART control 
//  
//  NOTE: by default, system is under 1394 mode. UART mode needs to be switch
//        on/off manually using start/stop UART control cmd 
// 
//  Examples: 
// ------------------------------------------------------------------------------  

module CtrlUart (
    input  wire clk40m,
    input  wire reset,
    input  wire RxD,
    output wire TxD,
    
    // register access
    output reg[15:0] reg_raddr,    // read address to external file
    output reg[15:0] reg_waddr,    // write address to external file
    input  wire[31:0] reg_rdata,   // read data
    input  wire[31:0] reg_wdata,   // write data

    // bus hold for uart 
    output wire uart_mode           // indicate the start of uart mode 
);

    // ------- Reg -------------
    reg[7:0] tx_data;     // data send via UartTx
    wire[7:0] rx_data;     // data received via UartRx
    reg tx_trig;
    wire tx_busy;         // wire for tx_busy signal
    wire rx_int;          // rx interrupt

    // clock module
    wire clk_14_pll;
    wire clk_29_pll;
    reg[3:0] Baud;
    wire BaudClk;

    // processor buffer
    reg[31:0] procBuffer[63:0];
    reg[5:0] procRdInd;
    reg[5:0] procWtInd;
    
    // chipscope
    wire[35:0] control_uart_ctrl;
    wire[35:0] control_uart_tx;
    wire[35:0] control_uart_rx;

    parameter[3:0]
        ST_IDLE = 0,
        ST_RX = 1,
        ST_TX_QUAD = 2;


//-----------------------------------------------------
// hardware description
// ----------------------------------------------------
assign uart_mode = 1'b0;


//-------- Clock -----------
UartClkGen clkgen(
  .IN40(clk40m),
  .OUT14(clk_14_pll),
  .OUT29(clk_29_pll)
  );

// -- Generate BaudClk
always @(posedge clk_29_pll) 
begin
  Baud <= Baud + 1'b1;
end
// buffer the baud rate divider
BUFG clkbaudclk(.I(Baud[3]), .O(BaudClk));

//---------- Tx & Rx Module --------
// tx module
UartTx uart_tx(
  .clkuart(BaudClk),
  .reset(reset),
  .tx_data(tx_data),
  .tx_trig(tx_trig),
  .TxD(TxD),
  .tx_busy(tx_busy),
  .control(control_uart_tx)
  );

// rx module 
UartRx uart_rx(
  .clkuart(BaudClk),
  .reset(reset),
  .RxD(RxD),
  .rx_data(rx_data),
  .rx_int(rx_int),
  .control(control_uart_rx)
  );


// ----------- Control Logic ------------

// echo interface
 always @(posedge(BaudClk) or negedge(reset)) begin
     if (reset == 0) begin
          tx_trig <= 1'b0;  
     end
     else if (rx_int) begin
         tx_trig <= 1'b1;
         tx_data <= rx_data;
     end
     else if (tx_trig == 1'b1) begin
         tx_trig <= 1'b0;   
     end
 end

//always @(posedge(BaudClk) or negedge(reset)) begin
//    if (reset == 0) begin
//
//    end
//    else if (rx_int) begin
//        if (rx_data == `UART_DELIMINATOR) begin
//            procWtInd <= 6'd0;
//            procRdInd <= 6'd0;
//        end
//    end
//end
//
//always @(posedge clk or posedge rst) begin
//  if (rst) begin
//    // reset
//    
//  end
//  else begin
//      case (state)
//
//      ST_IDLE:
//      begin
//          
//      end
//
//      ST_RX:
//      begin
//          
//      end
//
//      ST_TX_QUAD:
//      begin
//          if (tx_busy) begin
//              tx_data <= reg_rdata;
//              tx_trig <= 1'b1;
//          end
//      end
//
//      endcase
//  end
//end


// -------------------
// chipscope
// -------------------
icon_uart icon(
    .CONTROL0(control_uart_ctrl),
    .CONTROL1(control_uart_tx),
    .CONTROL2(control_uart_rx)
);

ila_3_8_8_8 ila_tx(
    .CONTROL(control_uart_ctrl),
    .CLK(clkuart),
    .TRIG0({3'b0}),           // 3-bit
    .TRIG1(rx_data),        // 8-bit
    .TRIG2(rx_data),    // 8-bit
    .TRIG3(tx_data)        // 8-bit
);

endmodule





// ---------------------------------------------
// NOTE on UART data packet 
//   - This is a limited implementation 
//   - Data format
//     - 1 start bit 
//     - 8 data bit 
//     - 0 odd/even parity bit 
//     - 1 stop bit
//   - Baud rate = 115200 bps
// ---------------------------------------------


// ---------------------------------------------  
//  UART Tx Module
//     - Assumption on clkuart 
//        - 115200 x 256 / 16 = 29.491 MHz / 16 = 1.8432 MHz  
//        - input clk should be close enough 
// ---------------------------------------------  
module UartTx (
    input  wire clkuart,          // uart clock 1.8432 MHz (ideal clk)
    input  wire reset,            // reset
    input  wire[7:0] tx_data,     // tx data
    input  wire tx_trig,          // trigger to start

    output reg  TxD,              // UART Tx Data Pin
    output reg tx_busy,           // HIGH when tranxmitting 

    input wire[35:0] control
);

reg[7:0] tx_counter;    // tx time counter
reg[7:0] tx_reg;     // reg to latch tx_data 

// tx_counter 
//    counts from 0x00 -> 0x97, then stop
//    when tx_trig, clear and start counting
 always @(posedge(clkuart) or negedge(reset)) begin
     if (reset == 0) begin
         tx_counter <= 8'h97;    // stop counter
         tx_busy <= 1'b0;  
     end
     else if (tx_trig) begin
         tx_counter <= 8'h00;   // start counting
         tx_reg <= tx_data;     // latch data
         tx_busy <= 1'b1;       // set tx_busy
     end
     else if (tx_counter < 8'h97) begin
         tx_counter <= tx_counter + 1'b1;
     end
     else if (tx_counter == 8'h97) begin
         tx_busy <= 1'b0;       // clear tx_busy
     end
 end

// transmit data out (debug periodically)
//always @(posedge(clkuart) or negedge(reset)) begin
//    if (reset == 0) begin
//        tx_counter <= 8'd0;
//        tx_reg <= 8'd100;
//    end
//    else begin
//        tx_counter <= tx_counter + 1'b1;
//    end
//end



// transmit data out
always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        TxD <= 1'b1;
    end
    else if (tx_counter[3:0] == 4'h2) begin
        if      (tx_counter[7:4]==4'h0) TxD <= 1'b0;       // start bit
        else if (tx_counter[7:4]==4'h1) TxD <= tx_reg[0];  // data 
        else if (tx_counter[7:4]==4'h2) TxD <= tx_reg[1];  
        else if (tx_counter[7:4]==4'h3) TxD <= tx_reg[2];  
        else if (tx_counter[7:4]==4'h4) TxD <= tx_reg[3];  
        else if (tx_counter[7:4]==4'h5) TxD <= tx_reg[4];  
        else if (tx_counter[7:4]==4'h6) TxD <= tx_reg[5];  
        else if (tx_counter[7:4]==4'h7) TxD <= tx_reg[6];
        else if (tx_counter[7:4]==4'h8) TxD <= tx_reg[7];  
        else                            TxD <= 1'b1;       // stop bit, then idle bus 
    end
end


wire[2:0] tx_status;
assign tx_status = {TxD, tx_busy, tx_trig};

ila_3_8_8_8 ila_tx(
    .CONTROL(control),
    .CLK(clkuart),
    .TRIG0(tx_status),           // 3-bit
    .TRIG1(tx_reg),        // 8-bit
    .TRIG2(tx_counter),    // 8-bit
    .TRIG3(tx_data)        // 8-bit
);

endmodule




// -----------------------------------------------------------------------------  
//  UART Rx Module 
//   - step 1: receive and connect to chipscope 
//   ????? DO I REALLY care if the rx is busy ? 
// -----------------------------------------------------------------------------  
module UartRx (
    input  wire clkuart,           // uart clock 1.8432 MHz (ideal clk)
    input  wire reset,             // reset
    input  wire RxD,               // UART Rx Data Pin 
    output reg[7:0] rx_data,       // rx data, hold till next data byte
    output reg rx_int,             // rx interrupt, rx received

    input wire[35:0] control
);

// ---- Receive Start Detection ---------------
reg rxd0, rxd1, rxd2, rxd3;      // RxD cache for filtering
wire rxd_negedge;  

// if reset sets rxdx to 1, it may false trigger
always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        rxd0 <= 1'b0; rxd1 <= 1'b0; 
        rxd2 <= 1'b0; rxd3 <= 1'b0;   
    end
    else begin
        rxd0 <= RxD; rxd1 <= rxd0;
        rxd2 <= rxd1; rxd3 <= rxd2;
    end
end

// set rxd_negedge HIGH for 1 clk cycle, if neg edge
assign rxd_negedge = (rxd3 & rxd2 & ~rxd1 & ~rxd0);  

// ----- Receive counter -------------
reg[7:0] rx_counter;    // rx time counter
reg rx_recv;            // uart_rx receiving 

always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        rx_counter <= 8'h97;    // stop rx_counter
        rx_int <= 1'b0;
        rx_recv <= 1'b0;
    end
    else if (rxd_negedge && ~rx_recv) begin
        rx_counter <= 8'h00;    // start rx counter
        rx_recv <= 1'b1;
        rx_int <= 1'b0;
    end
    else if (rx_counter < 8'h97) begin
        rx_counter <= rx_counter + 1'b1;
    end
    else if (rx_counter == 8'h97) begin
        rx_counter <= rx_counter + 1'b1;
        rx_int <= 1'b1;
    end
    else if (rx_counter == 8'h98) begin
        rx_recv <= 1'b0;
        rx_int <= 1'b0;        // clear 
    end
end

// ----- Latch data --------------------
reg[7:0] rx_reg;        // reg to hold temp rx value

always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        rx_reg <= 8'h00;        // clear tmp rx_reg
    end
    else if (rx_counter[3:0] == 4'h2) begin                // start bit nothing
        if      (rx_counter[7:4]==4'h1) rx_reg[0] <= RxD;  // data bit 0
        else if (rx_counter[7:4]==4'h2) rx_reg[1] <= RxD;  
        else if (rx_counter[7:4]==4'h3) rx_reg[2] <= RxD;  
        else if (rx_counter[7:4]==4'h4) rx_reg[3] <= RxD;  
        else if (rx_counter[7:4]==4'h5) rx_reg[4] <= RxD;  
        else if (rx_counter[7:4]==4'h6) rx_reg[5] <= RxD;  
        else if (rx_counter[7:4]==4'h7) rx_reg[6] <= RxD;  // data bit 7
        else if (rx_counter[7:4]==4'h8) rx_data <= rx_reg; // latch data to rx_data
    end
end


wire[2:0] rx_status;
assign rx_status = {RxD, rxd_negedge, rx_int};

ila_3_8_8_8 ila_rx(
    .CONTROL(control),
    .CLK(clkuart),
    .TRIG0(rx_status),     // 3-bit
    .TRIG1(rx_reg),        // 8-bit
    .TRIG2(rx_counter),    // 8-bit
    .TRIG3(rx_data)        // 8-bit
);


endmodule





// ---------------------------------------------  
//  UART BAUD Clk Generator 
// ---------------------------------------------  
module UartClkGen (
	input  IN40,    // 40.000 MHz Clock In
	output OUT14,   // 14.476 MHz Clock signal (PLL Generated)
	output OUT29    // 29.491 MHz Clock signal (PLL Generated)
	);

wire clkfb;    // Click feedback
wire _out29;   // 29.491 MHz Clock signal
wire _out14;   // 14.746 MHz Clock signal
wire _ref40;   // 40.000 MHz Clock reference (Input)

//-----------------------------------------------------------------------------
//
// PLL Primitive
//
//   The "Base PLL" primitive has a PLL, a feedback path and 6 clock outputs,
//   each with its own 7 bit divider to generate 6 different output frequencies
//   that are integer division of the PLL frequency. The "Base" PLL provides
//   basic PLL/Clock-Generation capabilities. For detailed information, see
//   Chapter 3, "General Usage Description" section of the Spartan-6 FPGA 
//   Clocking Resource, Xilinx Document # UG382.
//
//   The PLL has a dedicated Feedback Output and Feedback Input. This output
//   must be connected to this input outside the primitive. For applications
//   where the phase relationship between the reference input and the output
//   clock is not critical (present application), this connection can be made
//   in the module. Where this phase relationship is critical, the feedback
//   path can include routing on the FPGA or even off-chip connections.
//
//   The Input/Output of the PLL module are ordinary signals, NOT clocks.
//   These signals must be routed through specialized buffers in order for
//   them to be connected to the global clock buses and be used as clocks.
//
//-----------------------------------------------------------------------------
PLL_BASE # (.BANDWIDTH         ("OPTIMIZED"),
	.CLK_FEEDBACK      ("CLKFBOUT"),
	.COMPENSATION      ("INTERNAL"),
	.DIVCLK_DIVIDE     (1),
            .CLKFBOUT_MULT     (14),        // VCO = 40.000* 14/1 = 560.0000MHz
            .CLKFBOUT_PHASE    (0.000),
            .CLKOUT0_DIVIDE    (  19  ),    // CLK0 = 560.00/19 = 29.474
            .CLKOUT0_PHASE     (  0.00),
            .CLKOUT0_DUTY_CYCLE(  0.50),
            .CLKOUT1_DIVIDE    (  38  ),    // CLK1 = 560.00/38 = 14.737
            .CLKOUT1_PHASE     (  0.00),
            .CLKOUT1_DUTY_CYCLE(  0.50),
            .CLKOUT2_DIVIDE    (  32  ),    // Unused Output. The divider still needs a
            .CLKOUT3_DIVIDE    (  32  ),    //    reasonable value because the clock is
            .CLKOUT4_DIVIDE    (  32  ),    //    still being generated even if unconnected.
            .CLKOUT5_DIVIDE    (  32  ))    //
_PLL1 (     .CLKFBOUT          (clkfb),     // The FB-Out is connected to FB-In inside
            .CLKFBIN           (clkfb),     //    the module.
            .CLKIN             (_ref40),    // 40.00 MHz reference clock
            .CLKOUT0           (_out29),    // 29.49 MHz Output signal
            .CLKOUT1           (_out14),    // 14.75 MHz Output signal
            .CLKOUT2           (),          // Unused outputs
            .CLKOUT3           (),          //
            .CLKOUT4           (),          //
            .CLKOUT5           (),          //
            .LOCKED            (),          //
            .RST               (1'b0));     // Reset Disable



//-----------------------------------------------------------------------------
//
// Input/Output Buffering
//
//   The Inputs/Outputs of the PLL module are regular signals, NOT clocks.
//
//   The output signals have to connected to BUFG buffers, which are among the
//   specialized primitives that can drive the global clock lines.
//
//   Similarly, an external reference clock connected to a clock pin on the
//   FPGA needs to be routed through an IBUFG primitive to get an ordinary
//   signal that can be used by the PLL Module
//
//-----------------------------------------------------------------------------
BUFG  clk_buf1 (.I(IN40),    .O(_ref40));
BUFG  clk_buf2 (.I(_out29),  .O(OUT29 ));
BUFG  clk_buf3 (.I(_out14),  .O(OUT14 ));

endmodule  // UartClkGen 
