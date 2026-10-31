`ifndef MYCPU_H
`define MYCPU_H

`define BR_BUS_WD        33
`define FS_TO_DS_BUS_WD  64
`define DS_TO_ES_BUS_WD  292
`define ES_TO_MS_BUS_WD  205
`define MS_TO_WS_BUS_WD  201
`define WS_TO_RF_BUS_WD  38

`define MEM_SIZE_BYTE    2'b00
`define MEM_SIZE_HALF    2'b01
`define MEM_SIZE_WORD    2'b10

// Metadata is prepended to each original pipeline bus (low bits unchanged).
`define CTRL_WD 131
`define CTRL_BADV 31:0
`define CTRL_ESUB 40:32
`define CTRL_ECODE 46:41
`define CTRL_EX 47
`define CTRL_ERTN 48
`define CTRL_VALUE 80:49
`define CTRL_MASK 112:81
`define CTRL_NUM 126:113
`define CTRL_WE 127
`define CTRL_RE 128
`define CTRL_CNT 130:129
`endif
