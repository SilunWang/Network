#ifndef NODESENSE_H
#define NODESENSE_H

enum {
  NREADINGS = 1,
  AM_NODESENSEMSG = 0x1,
  AM_NODERESENDMSG = 0x2,
  AM_SENSEINTERVALMSG = 0x3
};


typedef nx_struct nodesensemsg {
  nx_uint16_t interval;
  nx_uint16_t id; /* Mote id of sending mote. */
  nx_uint16_t SeqNo; /* The readings are samples count * NREADINGS onwards */
  nx_uint16_t temperature[NREADINGS];
  nx_uint16_t humidity[NREADINGS];
  nx_uint16_t illumination[NREADINGS];
  nx_uint16_t curtime[NREADINGS];
} nodesense_t;

typedef nx_struct noderesendmsg {
  nx_uint16_t id;
  nx_uint16_t SeqNo;
} noderesend_t;

typedef nx_struct senseintervalmsg {
  nx_uint16_t interval;
} senseinterval_t;

#endif
