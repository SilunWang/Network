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

  AM_NODESENSEMSG = 0x93
};

typedef nx_struct nodesensemsg {
  nx_uint16_t version; /* Version of the interval. */
  nx_uint16_t interval; /* Samping period. */
  nx_uint16_t id; /* Mote id of sending mote. */
  nx_uint16_t count; /* The readings are samples count * NREADINGS onwards */
  nx_uint16_t temperature[NREADINGS];
  nx_uint16_t humidity[NREADINGS];
  nx_uint16_t illumination[NREADINGS];
  nx_uint16_t curtime[NREADINGS];
} nodesense_t;

#endif