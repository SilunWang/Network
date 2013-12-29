/*
 * Copyright (c) 2006 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

// @author David Gay

#ifndef NODESENSE_H
#define NODESENSE_H

enum {
  /* Number of readings per message. If you increase this, you may have to
     increase the message_t size. */
  NREADINGS = 1,

  /* Default sampling period. */
  DEFAULT_INTERVAL = 500,
  RADIO_QUEUE_LEN = 80,

  AM_NODESENSEMSG = 0x1,
  AM_NODERESENDMSG = 0x2,
  AM_SENSEINTERVALMSG = 0x3,

  MAX_QUEUESIZE = 360
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

typedef nx_struct senseintervalmsg{
  nx_uint16_t interval;
} senseinterval_t;

#endif
