#ifndef NODEDDP_H
#define NODEDDP_H

enum {
  AM_NODEDATAMSG = 0x0,
  AM_NODERESENDMSG = 0x1,
  AM_NODECOMMANDERMSG = 0x2,//require the num from other nodes
  AM_NODEINFOMSG = 0X3,     //send assistant node info to commander node
  AM_NODEACKMSG = 0x5,
  AM_NODERESULT = 0x10,

  GROUP_ID = 31,
  NODE_COMMANDER = (GROUP_ID-1)*3+1,
  NODE_ONE = (GROUP_ID-1)*3+2,
  NODE_TWO = (GROUP_ID-1)*3+3,

  MAX_DATA_SIZE = 1000
};


typedef nx_struct nodedatamsg {
  nx_uint16_t sequence_number;
  nx_int32_t random_integer;
} nodedata_t;

typedef nx_struct noderesendmsg {
  nx_uint16_t id;
  nx_uint16_t sequence_number;
} noderesend_t;

typedef nx_struct nodeassistmsg{
  nx_uint16_t id;
  nx_uint16_t num;
  nx_uint32_t sum;
  nx_uint32_t value;
} nodeassist_t;

typedef nx_struct resultmsg{
  nx_uint8_t  group_id;
  nx_uint32_t max;
  nx_uint32_t min;
  nx_uint32_t sum;
  nx_uint32_t average;
  nx_uint32_t median;
} result_t;

#endif
