`timescale 1ns / 1ps

module mnist_img_tb;

    reg clk;
    reg rst;
    always #5 clk = ~clk;

    reg  rx;
    wire tx;

    localparam BIT_PERIOD = 8680;

    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx u_rx (
        .clk     (clk),
        .rst     (rst),
        .rx      (rx),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    wire [7:0] tx_data;
    wire       tx_start;
    wire tx_busy;

    mnist_core dut (
        .clk     (clk),
        .rst     (rst),
        .rx_data (rx_data),
        .rx_valid(rx_valid),
        .tx_data (tx_data),
        .tx_start(tx_start),
        .tx_busy (tx_busy)
    );

    uart_tx u_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (tx),
        .tx_busy (tx_busy),
        .tx_done ()
    );

    // ── 픽셀 배열 ──────────────────────────────
    // Python 출력 여기에 복붙
    reg [7:0] pixels [0:783];
    initial begin
            pixels[  0] = 8'h00;
    pixels[  1] = 8'h00;
    pixels[  2] = 8'h00;
    pixels[  3] = 8'h00;
    pixels[  4] = 8'h00;
    pixels[  5] = 8'h00;
    pixels[  6] = 8'h00;
    pixels[  7] = 8'h00;
    pixels[  8] = 8'h00;
    pixels[  9] = 8'h00;
    pixels[ 10] = 8'h00;
    pixels[ 11] = 8'h00;
    pixels[ 12] = 8'h00;
    pixels[ 13] = 8'h00;
    pixels[ 14] = 8'h00;
    pixels[ 15] = 8'h00;
    pixels[ 16] = 8'h00;
    pixels[ 17] = 8'h00;
    pixels[ 18] = 8'h00;
    pixels[ 19] = 8'h00;
    pixels[ 20] = 8'h00;
    pixels[ 21] = 8'h00;
    pixels[ 22] = 8'h00;
    pixels[ 23] = 8'h00;
    pixels[ 24] = 8'h00;
    pixels[ 25] = 8'h00;
    pixels[ 26] = 8'h00;
    pixels[ 27] = 8'h00;
    pixels[ 28] = 8'h00;
    pixels[ 29] = 8'h00;
    pixels[ 30] = 8'h00;
    pixels[ 31] = 8'h00;
    pixels[ 32] = 8'h00;
    pixels[ 33] = 8'h00;
    pixels[ 34] = 8'h00;
    pixels[ 35] = 8'h00;
    pixels[ 36] = 8'h00;
    pixels[ 37] = 8'h00;
    pixels[ 38] = 8'h00;
    pixels[ 39] = 8'h00;
    pixels[ 40] = 8'h00;
    pixels[ 41] = 8'h00;
    pixels[ 42] = 8'h00;
    pixels[ 43] = 8'h00;
    pixels[ 44] = 8'h00;
    pixels[ 45] = 8'h00;
    pixels[ 46] = 8'h00;
    pixels[ 47] = 8'h00;
    pixels[ 48] = 8'h00;
    pixels[ 49] = 8'h00;
    pixels[ 50] = 8'h00;
    pixels[ 51] = 8'h00;
    pixels[ 52] = 8'h00;
    pixels[ 53] = 8'h00;
    pixels[ 54] = 8'h00;
    pixels[ 55] = 8'h00;
    pixels[ 56] = 8'h00;
    pixels[ 57] = 8'h00;
    pixels[ 58] = 8'h00;
    pixels[ 59] = 8'h00;
    pixels[ 60] = 8'h00;
    pixels[ 61] = 8'h00;
    pixels[ 62] = 8'h00;
    pixels[ 63] = 8'h00;
    pixels[ 64] = 8'h00;
    pixels[ 65] = 8'h00;
    pixels[ 66] = 8'h00;
    pixels[ 67] = 8'h00;
    pixels[ 68] = 8'h00;
    pixels[ 69] = 8'h00;
    pixels[ 70] = 8'h00;
    pixels[ 71] = 8'h00;
    pixels[ 72] = 8'h00;
    pixels[ 73] = 8'h00;
    pixels[ 74] = 8'h00;
    pixels[ 75] = 8'h00;
    pixels[ 76] = 8'h00;
    pixels[ 77] = 8'h00;
    pixels[ 78] = 8'h00;
    pixels[ 79] = 8'h00;
    pixels[ 80] = 8'h00;
    pixels[ 81] = 8'h00;
    pixels[ 82] = 8'h00;
    pixels[ 83] = 8'h00;
    pixels[ 84] = 8'h00;
    pixels[ 85] = 8'h00;
    pixels[ 86] = 8'h00;
    pixels[ 87] = 8'h00;
    pixels[ 88] = 8'h00;
    pixels[ 89] = 8'h00;
    pixels[ 90] = 8'h00;
    pixels[ 91] = 8'h00;
    pixels[ 92] = 8'h00;
    pixels[ 93] = 8'h00;
    pixels[ 94] = 8'h00;
    pixels[ 95] = 8'h00;
    pixels[ 96] = 8'h00;
    pixels[ 97] = 8'h00;
    pixels[ 98] = 8'h00;
    pixels[ 99] = 8'h00;
    pixels[100] = 8'h00;
    pixels[101] = 8'h00;
    pixels[102] = 8'h00;
    pixels[103] = 8'h00;
    pixels[104] = 8'h00;
    pixels[105] = 8'h00;
    pixels[106] = 8'h00;
    pixels[107] = 8'h00;
    pixels[108] = 8'h00;
    pixels[109] = 8'h00;
    pixels[110] = 8'h00;
    pixels[111] = 8'h00;
    pixels[112] = 8'h00;
    pixels[113] = 8'h00;
    pixels[114] = 8'h00;
    pixels[115] = 8'h00;
    pixels[116] = 8'h00;
    pixels[117] = 8'h00;
    pixels[118] = 8'h00;
    pixels[119] = 8'h00;
    pixels[120] = 8'h00;
    pixels[121] = 8'h00;
    pixels[122] = 8'h00;
    pixels[123] = 8'h00;
    pixels[124] = 8'h00;
    pixels[125] = 8'h00;
    pixels[126] = 8'h00;
    pixels[127] = 8'h00;
    pixels[128] = 8'h02;
    pixels[129] = 8'h0F;
    pixels[130] = 8'h06;
    pixels[131] = 8'h00;
    pixels[132] = 8'h00;
    pixels[133] = 8'h00;
    pixels[134] = 8'h00;
    pixels[135] = 8'h00;
    pixels[136] = 8'h00;
    pixels[137] = 8'h00;
    pixels[138] = 8'h00;
    pixels[139] = 8'h00;
    pixels[140] = 8'h00;
    pixels[141] = 8'h00;
    pixels[142] = 8'h00;
    pixels[143] = 8'h00;
    pixels[144] = 8'h00;
    pixels[145] = 8'h00;
    pixels[146] = 8'h00;
    pixels[147] = 8'h00;
    pixels[148] = 8'h00;
    pixels[149] = 8'h00;
    pixels[150] = 8'h00;
    pixels[151] = 8'h00;
    pixels[152] = 8'h00;
    pixels[153] = 8'h00;
    pixels[154] = 8'h00;
    pixels[155] = 8'h00;
    pixels[156] = 8'h05;
    pixels[157] = 8'h0F;
    pixels[158] = 8'h05;
    pixels[159] = 8'h00;
    pixels[160] = 8'h00;
    pixels[161] = 8'h00;
    pixels[162] = 8'h00;
    pixels[163] = 8'h00;
    pixels[164] = 8'h00;
    pixels[165] = 8'h00;
    pixels[166] = 8'h00;
    pixels[167] = 8'h00;
    pixels[168] = 8'h00;
    pixels[169] = 8'h00;
    pixels[170] = 8'h00;
    pixels[171] = 8'h00;
    pixels[172] = 8'h00;
    pixels[173] = 8'h00;
    pixels[174] = 8'h00;
    pixels[175] = 8'h00;
    pixels[176] = 8'h00;
    pixels[177] = 8'h00;
    pixels[178] = 8'h00;
    pixels[179] = 8'h00;
    pixels[180] = 8'h00;
    pixels[181] = 8'h00;
    pixels[182] = 8'h00;
    pixels[183] = 8'h00;
    pixels[184] = 8'h08;
    pixels[185] = 8'h0E;
    pixels[186] = 8'h00;
    pixels[187] = 8'h00;
    pixels[188] = 8'h00;
    pixels[189] = 8'h00;
    pixels[190] = 8'h00;
    pixels[191] = 8'h00;
    pixels[192] = 8'h00;
    pixels[193] = 8'h00;
    pixels[194] = 8'h00;
    pixels[195] = 8'h00;
    pixels[196] = 8'h00;
    pixels[197] = 8'h00;
    pixels[198] = 8'h00;
    pixels[199] = 8'h00;
    pixels[200] = 8'h00;
    pixels[201] = 8'h00;
    pixels[202] = 8'h00;
    pixels[203] = 8'h00;
    pixels[204] = 8'h00;
    pixels[205] = 8'h00;
    pixels[206] = 8'h00;
    pixels[207] = 8'h00;
    pixels[208] = 8'h00;
    pixels[209] = 8'h00;
    pixels[210] = 8'h00;
    pixels[211] = 8'h03;
    pixels[212] = 8'h0E;
    pixels[213] = 8'h09;
    pixels[214] = 8'h00;
    pixels[215] = 8'h00;
    pixels[216] = 8'h00;
    pixels[217] = 8'h00;
    pixels[218] = 8'h00;
    pixels[219] = 8'h00;
    pixels[220] = 8'h00;
    pixels[221] = 8'h00;
    pixels[222] = 8'h00;
    pixels[223] = 8'h00;
    pixels[224] = 8'h00;
    pixels[225] = 8'h00;
    pixels[226] = 8'h00;
    pixels[227] = 8'h00;
    pixels[228] = 8'h00;
    pixels[229] = 8'h00;
    pixels[230] = 8'h00;
    pixels[231] = 8'h00;
    pixels[232] = 8'h00;
    pixels[233] = 8'h00;
    pixels[234] = 8'h00;
    pixels[235] = 8'h00;
    pixels[236] = 8'h00;
    pixels[237] = 8'h00;
    pixels[238] = 8'h00;
    pixels[239] = 8'h05;
    pixels[240] = 8'h0F;
    pixels[241] = 8'h04;
    pixels[242] = 8'h00;
    pixels[243] = 8'h00;
    pixels[244] = 8'h00;
    pixels[245] = 8'h00;
    pixels[246] = 8'h00;
    pixels[247] = 8'h00;
    pixels[248] = 8'h00;
    pixels[249] = 8'h00;
    pixels[250] = 8'h00;
    pixels[251] = 8'h00;
    pixels[252] = 8'h00;
    pixels[253] = 8'h00;
    pixels[254] = 8'h00;
    pixels[255] = 8'h00;
    pixels[256] = 8'h00;
    pixels[257] = 8'h00;
    pixels[258] = 8'h00;
    pixels[259] = 8'h00;
    pixels[260] = 8'h00;
    pixels[261] = 8'h00;
    pixels[262] = 8'h00;
    pixels[263] = 8'h00;
    pixels[264] = 8'h00;
    pixels[265] = 8'h00;
    pixels[266] = 8'h00;
    pixels[267] = 8'h0C;
    pixels[268] = 8'h0D;
    pixels[269] = 8'h01;
    pixels[270] = 8'h00;
    pixels[271] = 8'h00;
    pixels[272] = 8'h00;
    pixels[273] = 8'h00;
    pixels[274] = 8'h00;
    pixels[275] = 8'h00;
    pixels[276] = 8'h00;
    pixels[277] = 8'h00;
    pixels[278] = 8'h00;
    pixels[279] = 8'h00;
    pixels[280] = 8'h00;
    pixels[281] = 8'h00;
    pixels[282] = 8'h00;
    pixels[283] = 8'h00;
    pixels[284] = 8'h00;
    pixels[285] = 8'h00;
    pixels[286] = 8'h00;
    pixels[287] = 8'h00;
    pixels[288] = 8'h00;
    pixels[289] = 8'h00;
    pixels[290] = 8'h00;
    pixels[291] = 8'h00;
    pixels[292] = 8'h00;
    pixels[293] = 8'h00;
    pixels[294] = 8'h02;
    pixels[295] = 8'h0F;
    pixels[296] = 8'h0D;
    pixels[297] = 8'h00;
    pixels[298] = 8'h00;
    pixels[299] = 8'h00;
    pixels[300] = 8'h00;
    pixels[301] = 8'h00;
    pixels[302] = 8'h00;
    pixels[303] = 8'h00;
    pixels[304] = 8'h00;
    pixels[305] = 8'h00;
    pixels[306] = 8'h00;
    pixels[307] = 8'h00;
    pixels[308] = 8'h00;
    pixels[309] = 8'h00;
    pixels[310] = 8'h00;
    pixels[311] = 8'h00;
    pixels[312] = 8'h00;
    pixels[313] = 8'h00;
    pixels[314] = 8'h00;
    pixels[315] = 8'h00;
    pixels[316] = 8'h00;
    pixels[317] = 8'h00;
    pixels[318] = 8'h00;
    pixels[319] = 8'h00;
    pixels[320] = 8'h00;
    pixels[321] = 8'h00;
    pixels[322] = 8'h06;
    pixels[323] = 8'h0F;
    pixels[324] = 8'h0B;
    pixels[325] = 8'h00;
    pixels[326] = 8'h00;
    pixels[327] = 8'h00;
    pixels[328] = 8'h00;
    pixels[329] = 8'h00;
    pixels[330] = 8'h00;
    pixels[331] = 8'h00;
    pixels[332] = 8'h00;
    pixels[333] = 8'h00;
    pixels[334] = 8'h00;
    pixels[335] = 8'h00;
    pixels[336] = 8'h00;
    pixels[337] = 8'h00;
    pixels[338] = 8'h00;
    pixels[339] = 8'h00;
    pixels[340] = 8'h00;
    pixels[341] = 8'h00;
    pixels[342] = 8'h00;
    pixels[343] = 8'h00;
    pixels[344] = 8'h00;
    pixels[345] = 8'h00;
    pixels[346] = 8'h00;
    pixels[347] = 8'h00;
    pixels[348] = 8'h00;
    pixels[349] = 8'h00;
    pixels[350] = 8'h08;
    pixels[351] = 8'h0F;
    pixels[352] = 8'h05;
    pixels[353] = 8'h00;
    pixels[354] = 8'h00;
    pixels[355] = 8'h00;
    pixels[356] = 8'h00;
    pixels[357] = 8'h00;
    pixels[358] = 8'h00;
    pixels[359] = 8'h00;
    pixels[360] = 8'h00;
    pixels[361] = 8'h00;
    pixels[362] = 8'h00;
    pixels[363] = 8'h00;
    pixels[364] = 8'h00;
    pixels[365] = 8'h00;
    pixels[366] = 8'h00;
    pixels[367] = 8'h00;
    pixels[368] = 8'h00;
    pixels[369] = 8'h00;
    pixels[370] = 8'h00;
    pixels[371] = 8'h00;
    pixels[372] = 8'h00;
    pixels[373] = 8'h00;
    pixels[374] = 8'h00;
    pixels[375] = 8'h00;
    pixels[376] = 8'h00;
    pixels[377] = 8'h03;
    pixels[378] = 8'h0E;
    pixels[379] = 8'h0C;
    pixels[380] = 8'h00;
    pixels[381] = 8'h00;
    pixels[382] = 8'h00;
    pixels[383] = 8'h00;
    pixels[384] = 8'h00;
    pixels[385] = 8'h00;
    pixels[386] = 8'h00;
    pixels[387] = 8'h00;
    pixels[388] = 8'h00;
    pixels[389] = 8'h00;
    pixels[390] = 8'h00;
    pixels[391] = 8'h00;
    pixels[392] = 8'h00;
    pixels[393] = 8'h00;
    pixels[394] = 8'h00;
    pixels[395] = 8'h00;
    pixels[396] = 8'h00;
    pixels[397] = 8'h00;
    pixels[398] = 8'h00;
    pixels[399] = 8'h00;
    pixels[400] = 8'h00;
    pixels[401] = 8'h00;
    pixels[402] = 8'h00;
    pixels[403] = 8'h00;
    pixels[404] = 8'h00;
    pixels[405] = 8'h07;
    pixels[406] = 8'h0F;
    pixels[407] = 8'h0A;
    pixels[408] = 8'h00;
    pixels[409] = 8'h00;
    pixels[410] = 8'h00;
    pixels[411] = 8'h00;
    pixels[412] = 8'h00;
    pixels[413] = 8'h00;
    pixels[414] = 8'h00;
    pixels[415] = 8'h00;
    pixels[416] = 8'h00;
    pixels[417] = 8'h00;
    pixels[418] = 8'h00;
    pixels[419] = 8'h00;
    pixels[420] = 8'h00;
    pixels[421] = 8'h00;
    pixels[422] = 8'h00;
    pixels[423] = 8'h00;
    pixels[424] = 8'h00;
    pixels[425] = 8'h00;
    pixels[426] = 8'h00;
    pixels[427] = 8'h00;
    pixels[428] = 8'h00;
    pixels[429] = 8'h00;
    pixels[430] = 8'h00;
    pixels[431] = 8'h00;
    pixels[432] = 8'h00;
    pixels[433] = 8'h0A;
    pixels[434] = 8'h0F;
    pixels[435] = 8'h05;
    pixels[436] = 8'h00;
    pixels[437] = 8'h00;
    pixels[438] = 8'h00;
    pixels[439] = 8'h00;
    pixels[440] = 8'h00;
    pixels[441] = 8'h00;
    pixels[442] = 8'h00;
    pixels[443] = 8'h00;
    pixels[444] = 8'h00;
    pixels[445] = 8'h00;
    pixels[446] = 8'h00;
    pixels[447] = 8'h00;
    pixels[448] = 8'h00;
    pixels[449] = 8'h00;
    pixels[450] = 8'h00;
    pixels[451] = 8'h00;
    pixels[452] = 8'h00;
    pixels[453] = 8'h00;
    pixels[454] = 8'h00;
    pixels[455] = 8'h00;
    pixels[456] = 8'h00;
    pixels[457] = 8'h00;
    pixels[458] = 8'h00;
    pixels[459] = 8'h00;
    pixels[460] = 8'h01;
    pixels[461] = 8'h0E;
    pixels[462] = 8'h0D;
    pixels[463] = 8'h00;
    pixels[464] = 8'h00;
    pixels[465] = 8'h00;
    pixels[466] = 8'h00;
    pixels[467] = 8'h00;
    pixels[468] = 8'h00;
    pixels[469] = 8'h00;
    pixels[470] = 8'h00;
    pixels[471] = 8'h00;
    pixels[472] = 8'h00;
    pixels[473] = 8'h00;
    pixels[474] = 8'h00;
    pixels[475] = 8'h00;
    pixels[476] = 8'h00;
    pixels[477] = 8'h00;
    pixels[478] = 8'h00;
    pixels[479] = 8'h00;
    pixels[480] = 8'h00;
    pixels[481] = 8'h00;
    pixels[482] = 8'h00;
    pixels[483] = 8'h00;
    pixels[484] = 8'h00;
    pixels[485] = 8'h00;
    pixels[486] = 8'h00;
    pixels[487] = 8'h00;
    pixels[488] = 8'h07;
    pixels[489] = 8'h0F;
    pixels[490] = 8'h09;
    pixels[491] = 8'h00;
    pixels[492] = 8'h00;
    pixels[493] = 8'h00;
    pixels[494] = 8'h00;
    pixels[495] = 8'h00;
    pixels[496] = 8'h00;
    pixels[497] = 8'h00;
    pixels[498] = 8'h00;
    pixels[499] = 8'h00;
    pixels[500] = 8'h00;
    pixels[501] = 8'h00;
    pixels[502] = 8'h00;
    pixels[503] = 8'h00;
    pixels[504] = 8'h00;
    pixels[505] = 8'h00;
    pixels[506] = 8'h00;
    pixels[507] = 8'h00;
    pixels[508] = 8'h00;
    pixels[509] = 8'h00;
    pixels[510] = 8'h00;
    pixels[511] = 8'h00;
    pixels[512] = 8'h00;
    pixels[513] = 8'h00;
    pixels[514] = 8'h00;
    pixels[515] = 8'h00;
    pixels[516] = 8'h09;
    pixels[517] = 8'h0F;
    pixels[518] = 8'h08;
    pixels[519] = 8'h00;
    pixels[520] = 8'h00;
    pixels[521] = 8'h00;
    pixels[522] = 8'h00;
    pixels[523] = 8'h00;
    pixels[524] = 8'h00;
    pixels[525] = 8'h00;
    pixels[526] = 8'h00;
    pixels[527] = 8'h00;
    pixels[528] = 8'h00;
    pixels[529] = 8'h00;
    pixels[530] = 8'h00;
    pixels[531] = 8'h00;
    pixels[532] = 8'h00;
    pixels[533] = 8'h00;
    pixels[534] = 8'h00;
    pixels[535] = 8'h00;
    pixels[536] = 8'h00;
    pixels[537] = 8'h00;
    pixels[538] = 8'h00;
    pixels[539] = 8'h00;
    pixels[540] = 8'h00;
    pixels[541] = 8'h00;
    pixels[542] = 8'h00;
    pixels[543] = 8'h00;
    pixels[544] = 8'h0D;
    pixels[545] = 8'h0F;
    pixels[546] = 8'h04;
    pixels[547] = 8'h00;
    pixels[548] = 8'h00;
    pixels[549] = 8'h00;
    pixels[550] = 8'h00;
    pixels[551] = 8'h00;
    pixels[552] = 8'h00;
    pixels[553] = 8'h00;
    pixels[554] = 8'h00;
    pixels[555] = 8'h00;
    pixels[556] = 8'h00;
    pixels[557] = 8'h00;
    pixels[558] = 8'h00;
    pixels[559] = 8'h00;
    pixels[560] = 8'h00;
    pixels[561] = 8'h00;
    pixels[562] = 8'h00;
    pixels[563] = 8'h00;
    pixels[564] = 8'h00;
    pixels[565] = 8'h00;
    pixels[566] = 8'h00;
    pixels[567] = 8'h00;
    pixels[568] = 8'h00;
    pixels[569] = 8'h00;
    pixels[570] = 8'h00;
    pixels[571] = 8'h04;
    pixels[572] = 8'h0F;
    pixels[573] = 8'h0F;
    pixels[574] = 8'h04;
    pixels[575] = 8'h00;
    pixels[576] = 8'h00;
    pixels[577] = 8'h00;
    pixels[578] = 8'h00;
    pixels[579] = 8'h00;
    pixels[580] = 8'h00;
    pixels[581] = 8'h00;
    pixels[582] = 8'h00;
    pixels[583] = 8'h00;
    pixels[584] = 8'h00;
    pixels[585] = 8'h00;
    pixels[586] = 8'h00;
    pixels[587] = 8'h00;
    pixels[588] = 8'h00;
    pixels[589] = 8'h00;
    pixels[590] = 8'h00;
    pixels[591] = 8'h00;
    pixels[592] = 8'h00;
    pixels[593] = 8'h00;
    pixels[594] = 8'h00;
    pixels[595] = 8'h00;
    pixels[596] = 8'h00;
    pixels[597] = 8'h00;
    pixels[598] = 8'h00;
    pixels[599] = 8'h08;
    pixels[600] = 8'h0F;
    pixels[601] = 8'h0C;
    pixels[602] = 8'h00;
    pixels[603] = 8'h00;
    pixels[604] = 8'h00;
    pixels[605] = 8'h00;
    pixels[606] = 8'h00;
    pixels[607] = 8'h00;
    pixels[608] = 8'h00;
    pixels[609] = 8'h00;
    pixels[610] = 8'h00;
    pixels[611] = 8'h00;
    pixels[612] = 8'h00;
    pixels[613] = 8'h00;
    pixels[614] = 8'h00;
    pixels[615] = 8'h00;
    pixels[616] = 8'h00;
    pixels[617] = 8'h00;
    pixels[618] = 8'h00;
    pixels[619] = 8'h00;
    pixels[620] = 8'h00;
    pixels[621] = 8'h00;
    pixels[622] = 8'h00;
    pixels[623] = 8'h00;
    pixels[624] = 8'h00;
    pixels[625] = 8'h00;
    pixels[626] = 8'h01;
    pixels[627] = 8'h0D;
    pixels[628] = 8'h0F;
    pixels[629] = 8'h07;
    pixels[630] = 8'h00;
    pixels[631] = 8'h00;
    pixels[632] = 8'h00;
    pixels[633] = 8'h00;
    pixels[634] = 8'h00;
    pixels[635] = 8'h00;
    pixels[636] = 8'h00;
    pixels[637] = 8'h00;
    pixels[638] = 8'h00;
    pixels[639] = 8'h00;
    pixels[640] = 8'h00;
    pixels[641] = 8'h00;
    pixels[642] = 8'h00;
    pixels[643] = 8'h00;
    pixels[644] = 8'h00;
    pixels[645] = 8'h00;
    pixels[646] = 8'h00;
    pixels[647] = 8'h00;
    pixels[648] = 8'h00;
    pixels[649] = 8'h00;
    pixels[650] = 8'h00;
    pixels[651] = 8'h00;
    pixels[652] = 8'h00;
    pixels[653] = 8'h00;
    pixels[654] = 8'h00;
    pixels[655] = 8'h0C;
    pixels[656] = 8'h0A;
    pixels[657] = 8'h01;
    pixels[658] = 8'h00;
    pixels[659] = 8'h00;
    pixels[660] = 8'h00;
    pixels[661] = 8'h00;
    pixels[662] = 8'h00;
    pixels[663] = 8'h00;
    pixels[664] = 8'h00;
    pixels[665] = 8'h00;
    pixels[666] = 8'h00;
    pixels[667] = 8'h00;
    pixels[668] = 8'h00;
    pixels[669] = 8'h00;
    pixels[670] = 8'h00;
    pixels[671] = 8'h00;
    pixels[672] = 8'h00;
    pixels[673] = 8'h00;
    pixels[674] = 8'h00;
    pixels[675] = 8'h00;
    pixels[676] = 8'h00;
    pixels[677] = 8'h00;
    pixels[678] = 8'h00;
    pixels[679] = 8'h00;
    pixels[680] = 8'h00;
    pixels[681] = 8'h00;
    pixels[682] = 8'h00;
    pixels[683] = 8'h00;
    pixels[684] = 8'h00;
    pixels[685] = 8'h00;
    pixels[686] = 8'h00;
    pixels[687] = 8'h00;
    pixels[688] = 8'h00;
    pixels[689] = 8'h00;
    pixels[690] = 8'h00;
    pixels[691] = 8'h00;
    pixels[692] = 8'h00;
    pixels[693] = 8'h00;
    pixels[694] = 8'h00;
    pixels[695] = 8'h00;
    pixels[696] = 8'h00;
    pixels[697] = 8'h00;
    pixels[698] = 8'h00;
    pixels[699] = 8'h00;
    pixels[700] = 8'h00;
    pixels[701] = 8'h00;
    pixels[702] = 8'h00;
    pixels[703] = 8'h00;
    pixels[704] = 8'h00;
    pixels[705] = 8'h00;
    pixels[706] = 8'h00;
    pixels[707] = 8'h00;
    pixels[708] = 8'h00;
    pixels[709] = 8'h00;
    pixels[710] = 8'h00;
    pixels[711] = 8'h00;
    pixels[712] = 8'h00;
    pixels[713] = 8'h00;
    pixels[714] = 8'h00;
    pixels[715] = 8'h00;
    pixels[716] = 8'h00;
    pixels[717] = 8'h00;
    pixels[718] = 8'h00;
    pixels[719] = 8'h00;
    pixels[720] = 8'h00;
    pixels[721] = 8'h00;
    pixels[722] = 8'h00;
    pixels[723] = 8'h00;
    pixels[724] = 8'h00;
    pixels[725] = 8'h00;
    pixels[726] = 8'h00;
    pixels[727] = 8'h00;
    pixels[728] = 8'h00;
    pixels[729] = 8'h00;
    pixels[730] = 8'h00;
    pixels[731] = 8'h00;
    pixels[732] = 8'h00;
    pixels[733] = 8'h00;
    pixels[734] = 8'h00;
    pixels[735] = 8'h00;
    pixels[736] = 8'h00;
    pixels[737] = 8'h00;
    pixels[738] = 8'h00;
    pixels[739] = 8'h00;
    pixels[740] = 8'h00;
    pixels[741] = 8'h00;
    pixels[742] = 8'h00;
    pixels[743] = 8'h00;
    pixels[744] = 8'h00;
    pixels[745] = 8'h00;
    pixels[746] = 8'h00;
    pixels[747] = 8'h00;
    pixels[748] = 8'h00;
    pixels[749] = 8'h00;
    pixels[750] = 8'h00;
    pixels[751] = 8'h00;
    pixels[752] = 8'h00;
    pixels[753] = 8'h00;
    pixels[754] = 8'h00;
    pixels[755] = 8'h00;
    pixels[756] = 8'h00;
    pixels[757] = 8'h00;
    pixels[758] = 8'h00;
    pixels[759] = 8'h00;
    pixels[760] = 8'h00;
    pixels[761] = 8'h00;
    pixels[762] = 8'h00;
    pixels[763] = 8'h00;
    pixels[764] = 8'h00;
    pixels[765] = 8'h00;
    pixels[766] = 8'h00;
    pixels[767] = 8'h00;
    pixels[768] = 8'h00;
    pixels[769] = 8'h00;
    pixels[770] = 8'h00;
    pixels[771] = 8'h00;
    pixels[772] = 8'h00;
    pixels[773] = 8'h00;
    pixels[774] = 8'h00;
    pixels[775] = 8'h00;
    pixels[776] = 8'h00;
    pixels[777] = 8'h00;
    pixels[778] = 8'h00;
    pixels[779] = 8'h00;
    pixels[780] = 8'h00;
    pixels[781] = 8'h00;
    pixels[782] = 8'h00;
    pixels[783] = 8'h00;



    end

    // ── UART task ──────────────────────────────
    task uart_send_byte;
        input [7:0] data;
        integer j;
        begin
            rx = 0;
            #(BIT_PERIOD);
            for (j = 0; j < 8; j = j + 1) begin
                rx = data[j];
                #(BIT_PERIOD);
            end
            rx = 1;
            #(BIT_PERIOD);
        end
    endtask

    task uart_decode;
        output [7:0] data;
        integer j;
        begin
            @(negedge tx);
            #(BIT_PERIOD / 2);
            for (j = 0; j < 8; j = j + 1) begin
                #(BIT_PERIOD);
                data[j] = tx;
            end
            #(BIT_PERIOD);
        end
    endtask

    // ── 메인 ───────────────────────────────────
    integer   k;
    reg [7:0] result_byte;

    initial begin
        clk = 0;
        rst = 1;
        rx  = 1;

        repeat(10) @(posedge clk);
        rst = 0;
        repeat(5)  @(posedge clk);

        $display("=== 실제 MNIST 이미지 추론 시작 ===");
        $display("    label (정답): %0d", 2);  // Python label 값으로 교체

        fork
            begin : send_pixels
                for (k = 0; k < 784; k = k + 1)
                    uart_send_byte(pixels[k]);
//                     uart_send_byte(8'h08);  // ← pixels[k] 대신 고정값
            end
            begin : recv_result
                uart_decode(result_byte);
            end
        join

        $display("    추론 결과: %0d", result_byte);

        if (result_byte == 2)  // Python label 값으로 교체
            $display("    [PASS]");
        else
            $display("    [FAIL] 정답=%0d, 결과=%0d", 2, result_byte);

        $finish;
    end

    // ── FC1 activation 모니터 (Python 비교용) ─────
    integer fc1_idx;
    initial begin
        fc1_idx = 0;
        forever begin
            @(posedge clk);
            if (dut.fc1.out_valid) begin
                $display("  FC1 act[%0d] = %0d", fc1_idx, dut.fc1.out_data);
                fc1_idx = fc1_idx + 1;
            end
        end
    end

    // ── FC2 score 모니터 ───────────────────────
    // neuron_idx는 out_valid=1과 동시에 +1되므로(non-blocking) 별도 카운터 사용
    integer score_idx;
    initial begin
        score_idx = 0;
        forever begin
            @(posedge clk);
            if (dut.fc2.out_valid) begin
                $display("  FC2 score[%0d] = %0d",
                    score_idx,
                    $signed(dut.fc2.out_data));
                score_idx = score_idx + 1;
            end
        end
    end

    initial begin
        #400000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule