//////////////////////////////////////////////////////////////////////////////////////////////
// Company:            University of Tokyo
// Engineer:           Kenta Uno

// Create Date:        25/Feb/2016

// Module Name:        Selection_Block
// Project Name:       ATLAS LATOME (LAr Trigger PrOcessing MEzzanine) FPGA

// Description:        selection criteria after filtering calculation

/////////////////////////////////!//////////////////////////////////////////////////////////////

import ipctrl_cst_sv::*;
import user_cst_sv::*;

module Selection_Block(
    ttc_240_clk,
    ttc_240_rst,
    transverse_e,
    filter_valid,
    data_in_sop,
    tau_output,
    sat_constants,
    transverse_e_with_selection,
    quality,
    global_control_sat,
    global_control_sel

    ,et_threshold_to_quality_check

);

    // parameter initialization
    parameter  boundary_energy     = 18'h320; // 10 GeV
    parameter  min_negative_energy = 18'h3ffb0; // -1 GeV
    //port declaration
    // clock reset
    input                                                                                   ttc_240_clk;                    // 240 MHz clock
    input                                                                                   ttc_240_rst;                    // 240 MHz synchronous reset

    // transverse energy and quality from Filtering Block
    input [USER_ENERGY_WIDTH-1:0]                                                           transverse_e;                   // transverse energy from Filtering Block
    input                                                                                   filter_valid;                   // valid signal with filter output
    input                                                                                   data_in_sop;                    // valid signal with filter output
    input [USER_ENERGY_TAU_WIDTH-1:0]                                                       tau_output;                     // energy times tau from Filtering Block

    // constants for detecting saturation pulse
    input signed [USER_ENERGY_TAU_WIDTH-1:0]                                                sat_constants [USER_SELECTION_SATURATION_BOX_CONSTANT_NUMBER-1:0] [USER_CODE_STREAM_NB_SAMPLES-1:0];

    // the output signal after selection criteria
    output [USER_ENERGY_WIDTH-1:0]                                                          transverse_e_with_selection;    // transverse energy with selection criteria
    output [USER_QUALITY_WIDTH-1:0]                                                         quality;                        // quality bit


    // ET threshold
    output signed [USER_ENERGY_WIDTH-1:0]                                                   et_threshold_to_quality_check; // ET threshold, assigned for saturation pulses


    input                                                                                   global_control_sat;             // Global control signal for saturation block
    input                                                                                   global_control_sel;             // Global control signal for selection block

    //wire reg declaration
    wire                                                                                    data_out_sop;                   // shiftted start of packet
    wire signed [USER_ENERGY_WIDTH-1:0]                                                     Boundary_Energy;                // the boundary energy for tau selection criteria
    wire signed [USER_ENERGY_WIDTH-1:0]                                                     Min_Negative_Energy;            // the minimum energy which we should consider
    wire signed [USER_ENERGY_WIDTH-1:0]                                                     ET_threshold [1:0] [USER_CODE_STREAM_NB_SAMPLES-1:0]; // ET threshold for detecting saturation pulse

    reg signed [USER_ENERGY_WIDTH-1:0]                                                      et_threshold_to_quality_check_reg; // ET threshold, assigned for saturation pulses
    wire signed [USER_ENERGY_WIDTH-1:0]                                                     et_threshold_to_quality_check;     // ET threshold, assigned for saturation pulses

    reg [USER_CODE_REGS_SC_TYPE_WIDTH-1:0]                                                  sel_number;                     // identify sel number

    wire [USER_ENERGY_TAU_WIDTH-1:0]                                                        transverse_e_4shift;            // 4 bit shift
    reg signed [USER_ENERGY_TAU_WIDTH -1:0]                                                 pos_16_times_transverse_e;      // 16  times energy
    reg signed [USER_ENERGY_TAU_WIDTH -1:0]                                                 neg_16_times_transverse_e;      // -16 times energy
    wire signed [USER_ENERGY_TAU_WIDTH -1:0]                                                pos_8_times_transverse_e;       // 8 times energy
    wire signed [USER_ENERGY_TAU_WIDTH -1:0]                                                neg_8_times_transverse_e;       // -8 times energy
    reg signed [USER_ENERGY_TAU_WIDTH -1:0]                                                 tau_pipeline_reg;               // first pipeline register for energy times tau
    reg                                                                                     negative_energy_flag_reg;       // result flag for tau selection for negative energy
    reg                                                                                     low_energy_flag_reg;            // result flag for tau selection for low energy
    reg                                                                                     high_energy_flag_reg;           // result flag for tau selection for high energy

    wire                                                                                    filter_out_valid;               // shiftted valid signal with filter output
    reg signed [USER_ENERGY_WIDTH-1:0]                                                      transverse_e_first_reg;         // first pipeline register for transverse energy
    reg signed [USER_ENERGY_WIDTH-1:0]                                                      transverse_e_second_reg;        // second pipeline register for transverse energy
    reg signed [USER_ENERGY_WIDTH-1:0]                                                      transverse_e_tau_selection_reg; // transverse energy with selection criteria
    reg        [2*USER_CODE_STREAM_NB_SAMPLES:0]                                            saturation_register_buffer;     // buffer for saturation flag
    reg                                                                                     saturation_type_reg;            // saturation flag for one SC
    reg                                                                                     bcav_s_flag_reg;                // Bunch Crossing Assignment Valid for saturation pulse
    reg                                                                                     bcav_s_flag_pipeline_reg;       // pipeline register : Bunch Crossing Assignment Valid for saturation pulse
    reg                                                                                     bcav_e_flag_reg;                // Bunch Crossing Assignment Valid for non-saturation pulse

    // initialization
    assign  Boundary_Energy     = boundary_energy;
    assign  Min_Negative_Energy = min_negative_energy;

    // Duplicate reset
    reg                                                                                                       ttc_240_rst_dup;         /* synthesis preserve */;

    // Register reset to ease timings
    always @(posedge ttc_240_clk) begin
        ttc_240_rst_dup <= ttc_240_rst;
    end

    user_delay_chain #(
        .d_width  (1),
        .d_depth  (USER_FIR_FILTER_LATENCY)
    )
    sop_shift_register (
        .clk      (ttc_240_clk),   // .clk
        .sig_in   (data_in_sop),   // .sig_in
        .sig_out  (data_out_sop)   // .sig_out
    );

    // selection criteria
    // low energy region : -8ET < ET*tau < 8ET because the timing precision is dominated by systematic errors in the electronics
    // high energy region : -2ET < ET*tau < 2ET

    assign transverse_e_4shift = transverse_e << (USER_ENERGY_TAU_WIDTH - USER_ENERGY_WIDTH); // 4 bits shift

    always @ (posedge ttc_240_clk)
    begin
        if(ttc_240_rst_dup)
        begin
            pos_16_times_transverse_e <= {USER_ENERGY_TAU_WIDTH{1'b0}};
            neg_16_times_transverse_e <= {USER_ENERGY_TAU_WIDTH{1'b0}};
            tau_pipeline_reg          <= {(USER_ENERGY_TAU_WIDTH){1'b0}};
        end
        else
        begin
            pos_16_times_transverse_e <= transverse_e_4shift;
            neg_16_times_transverse_e <= ~(transverse_e_4shift - 1'b1);
            tau_pipeline_reg          <= (filter_valid == 1'b1) ? tau_output :{1'b0, {(USER_ENERGY_TAU_WIDTH-1){1'b1}}};
        end
    end

   assign pos_8_times_transverse_e = {pos_16_times_transverse_e[USER_ENERGY_TAU_WIDTH-1:USER_ENERGY_TAU_WIDTH-1], (pos_16_times_transverse_e[USER_ENERGY_TAU_WIDTH-1:USER_ENERGY_TAU_WIDTH-1] == 1'b1) ? 1'b1 : 1'b0, pos_16_times_transverse_e[USER_ENERGY_TAU_WIDTH-2:1]};
   assign neg_8_times_transverse_e = {neg_16_times_transverse_e[USER_ENERGY_TAU_WIDTH-1:USER_ENERGY_TAU_WIDTH-1], (neg_16_times_transverse_e[USER_ENERGY_TAU_WIDTH-1:USER_ENERGY_TAU_WIDTH-1] == 1'b1) ? 1'b1 : 1'b0, neg_16_times_transverse_e[USER_ENERGY_TAU_WIDTH-2:1]};

    // negative,low,high enrgy tau flag
    // negative energy :  8ET < ET*tau < -8ET
    // low energy      : -8ET < ET*tau <  8ET
    // high energy     : -8ET < ET*tau < 16ET
    always @ (posedge ttc_240_clk)
    begin
        if(ttc_240_rst_dup)
        begin
            negative_energy_flag_reg    <= 1'b0;
            low_energy_flag_reg         <= 1'b0;
            high_energy_flag_reg        <= 1'b0;
        end
        else
        begin
            negative_energy_flag_reg <= (pos_8_times_transverse_e < tau_pipeline_reg && tau_pipeline_reg < neg_8_times_transverse_e)  ? 1'b1 : 1'b0;
            low_energy_flag_reg      <= (neg_8_times_transverse_e < tau_pipeline_reg && tau_pipeline_reg < pos_8_times_transverse_e)  ? 1'b1 : 1'b0;
            high_energy_flag_reg     <= (neg_8_times_transverse_e < tau_pipeline_reg && tau_pipeline_reg < pos_16_times_transverse_e) ? 1'b1 : 1'b0;
        end
    end

    // selection transverse e and calculate saturation flag
    typedef enum {XI_MIN_M1=0, XI_MAX_M1, ET_THR_M1, XI_MIN_0, XI_MAX_0, ET_THR_0} sat_constants_e;

    initial
    begin
        sel_number              <= {USER_CODE_REGS_SC_TYPE_WIDTH{1'b1}};
    end

    user_delay_chain #(
        .d_width  (1),
        .d_depth  (USER_SELECTION_LATENCY)
    )
    valid_shift_register (
        .clk      (ttc_240_clk),       // .clk
        .sig_in   (filter_valid),      // .sig_in
        .sig_out  (filter_out_valid)   // .sig_out
    );

    always @ (posedge ttc_240_clk)
    begin
        if(ttc_240_rst_dup)
        begin
            sel_number              <= {USER_CODE_REGS_SC_TYPE_WIDTH{1'b0}};
        end
        else
        begin
            sel_number              <= (data_out_sop == 1'b1) ? {USER_CODE_REGS_SC_TYPE_WIDTH{1'b0}} : sel_number + {{(USER_CODE_REGS_SC_TYPE_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    genvar constant_i;
    generate
        for(constant_i = 0 ; constant_i < USER_CODE_STREAM_NB_SAMPLES ; constant_i = constant_i + 1)
        begin : gen_ET_threshold
            assign ET_threshold[0][constant_i] = {sat_constants[ET_THR_M1][constant_i][USER_ENERGY_TAU_WIDTH-1:USER_ENERGY_TAU_WIDTH-1], sat_constants[ET_THR_M1][constant_i][USER_ENERGY_WIDTH-2:0]};
            assign ET_threshold[1][constant_i] = {sat_constants[ET_THR_0][constant_i][USER_ENERGY_TAU_WIDTH-1:USER_ENERGY_TAU_WIDTH-1],  sat_constants[ET_THR_0][constant_i][USER_ENERGY_WIDTH-2:0]};
        end
    endgenerate

    always @ (posedge ttc_240_clk)
    begin
        if(ttc_240_rst_dup)
        begin
            transverse_e_first_reg            <= {USER_ENERGY_WIDTH{1'b0}};
            transverse_e_second_reg           <= {USER_ENERGY_WIDTH{1'b0}};
            transverse_e_tau_selection_reg    <= {USER_ENERGY_WIDTH{1'b0}};
            saturation_register_buffer        <= {(2*USER_CODE_STREAM_NB_SAMPLES + 1){1'b0}};
            bcav_s_flag_reg                   <= 1'b0;
            bcav_s_flag_pipeline_reg          <= 1'b0;
            bcav_e_flag_reg                   <= 1'b0;
            saturation_type_reg               <= 1'b0;

            et_threshold_to_quality_check_reg <= {USER_ENERGY_WIDTH{1'b0}};

        end
        else
        begin
            // Saturation Criteria
            transverse_e_first_reg            <= (filter_valid == 1'b1) ? transverse_e : {USER_ENERGY_WIDTH{1'b0}};
            transverse_e_second_reg           <= transverse_e_first_reg;

            if(transverse_e_first_reg > ET_threshold[0][sel_number] && tau_pipeline_reg < sat_constants[XI_MAX_M1][sel_number] && tau_pipeline_reg > sat_constants[XI_MIN_M1][sel_number]) begin
                saturation_register_buffer    <= {saturation_register_buffer[2*USER_CODE_STREAM_NB_SAMPLES-1:0] , 1'b1};
                bcav_s_flag_reg               <= 1'b0;
            end else if(transverse_e_first_reg > ET_threshold[1][sel_number] && tau_pipeline_reg < sat_constants[XI_MAX_0][sel_number] && tau_pipeline_reg > sat_constants[XI_MIN_0][sel_number]) begin
                saturation_register_buffer    <= {saturation_register_buffer[2*USER_CODE_STREAM_NB_SAMPLES-1:0] , 1'b1};
                bcav_s_flag_reg               <= 1'b1;
            end else begin
                saturation_register_buffer    <= {saturation_register_buffer[2*USER_CODE_STREAM_NB_SAMPLES-1:0] , 1'b0};
                bcav_s_flag_reg               <= 1'b0;
            end
            saturation_type_reg               <= saturation_register_buffer[2*USER_CODE_STREAM_NB_SAMPLES] | saturation_register_buffer[USER_CODE_STREAM_NB_SAMPLES] | saturation_register_buffer[0];
            bcav_s_flag_pipeline_reg          <= bcav_s_flag_reg;

            et_threshold_to_quality_check_reg <= ET_threshold[1][sel_number];

            // Tau Criteria
            if (global_control_sel == 1'b1)
            begin
                if (Min_Negative_Energy < transverse_e_second_reg && transverse_e_second_reg <= 0) begin // -1 GeV ~ 0 GeV
                    transverse_e_tau_selection_reg <= (negative_energy_flag_reg == 1'b1) ? transverse_e_second_reg : {USER_ENERGY_WIDTH{1'b0}};
                    bcav_e_flag_reg                <= (negative_energy_flag_reg == 1'b1) ? 1'b1 : 1'b0;
                end else if (0 < transverse_e_second_reg && transverse_e_second_reg <= Boundary_Energy) begin // 0 GeV ~ 10 geV
                    transverse_e_tau_selection_reg <= (low_energy_flag_reg == 1'b1)      ? transverse_e_second_reg : {USER_ENERGY_WIDTH{1'b0}};
                    bcav_e_flag_reg                <= (low_energy_flag_reg == 1'b1)      ? 1'b1 : 1'b0;
                end else if (Boundary_Energy < transverse_e_second_reg) begin // > 10 GeV
                    transverse_e_tau_selection_reg <= (high_energy_flag_reg == 1'b1)     ? transverse_e_second_reg : {USER_ENERGY_WIDTH{1'b0}};
                    bcav_e_flag_reg                <= (high_energy_flag_reg == 1'b1)     ? 1'b1 : 1'b0;
                end else begin // < -1 GeV
                    transverse_e_tau_selection_reg <= {USER_ENERGY_WIDTH{1'b0}};
                    bcav_e_flag_reg                <= 1'b0;
                end
            end
            else
            begin
                transverse_e_tau_selection_reg        <= transverse_e_second_reg;
                bcav_e_flag_reg                       <= 1'b1;
            end
        end
    end

    assign transverse_e_with_selection   = transverse_e_tau_selection_reg;
        assign quality                       = (filter_out_valid == 1'b1) ?  (global_control_sat == 1'b1) ? {saturation_type_reg , {(USER_QUALITY_WIDTH-3){1'b0}}, bcav_s_flag_pipeline_reg, bcav_e_flag_reg} : {1'b0, {(USER_QUALITY_WIDTH-3){1'b0}}, 1'b0, bcav_e_flag_reg} : {USER_QUALITY_WIDTH{1'b0}};

    assign et_threshold_to_quality_check = et_threshold_to_quality_check_reg;

endmodule
