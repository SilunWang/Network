// $Id$

/*									tab:4
 * "Copyright (c) 2000-2005 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Copyright (c) 2002-2005 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

/*
 * @author Phil Buonadonna
 * @author Gilman Tolle
 * @author David Gay
 * Revision:	$Id$
 */
  
/* 
 * BaseStationP bridges packets between a serial channel and the radio.
 * Messages moving from serial to radio will be tagged with the group
 * ID compiled into the TOSBase, and messages moving from radio to
 * serial will be filtered by that same group id.
 */

#include "AM.h"
#include "Serial.h"
#include "NodeSense.h"

module BaseStationP @safe() {
  uses {
    interface Boot;
    interface SplitControl as SerialControl;
    interface SplitControl as RadioControl;

    interface AMSend as UartSend[am_id_t id];
    interface Receive as UartReceive[am_id_t id];
    interface Packet as UartPacket;
    interface AMPacket as UartAMPacket;
    
    interface AMSend as RadioSend[am_id_t id];
    interface Receive as RadioReceive[am_id_t id];
    interface Packet as RadioPacket;
    interface AMPacket as RadioAMPacket;

    interface Timer<TMilli> as Timer;
    interface Leds;
  }
}

implementation
{
  enum {
    UART_QUEUE_LEN = 12,
    RADIO_QUEUE_LEN = 12,
    SEQ_QUEUE_LEN = 10,
    DROP_QUEUE_LEN = 50,
  };

  message_t  uartQueueBufs[UART_QUEUE_LEN];
  message_t  * ONE_NOK uartQueue[UART_QUEUE_LEN];
  uint8_t    uartIn, uartOut;
  bool       uartBusy, uartFull;

  message_t  radioQueueBufs[RADIO_QUEUE_LEN];
  message_t  * ONE_NOK radioQueue[RADIO_QUEUE_LEN];
  uint8_t    radioIn, radioOut;
  bool       radioBusy, radioFull;

  uint16_t    seqQueue[SEQ_QUEUE_LEN];
  noderesend_t    dropQueue[DROP_QUEUE_LEN];
  uint8_t     dropflag;

  task void uartSendTask();
  task void radioSendTask();

  void dropBlink() {
    call Leds.led2Toggle();
  }

  void failBlink() {
    call Leds.led2Toggle();
  }

  event void Boot.booted() {
    uint8_t i;

    for (i = 0; i < UART_QUEUE_LEN; i++)
      uartQueue[i] = &uartQueueBufs[i];

    uartIn = uartOut = 0;
    uartBusy = FALSE;
    uartFull = TRUE;

    for (i = 0; i < RADIO_QUEUE_LEN; i++)
      radioQueue[i] = &radioQueueBufs[i];

    radioIn = radioOut = 0;
    radioBusy = FALSE;
    radioFull = TRUE;

    for (i = 0; i < SEQ_QUEUE_LEN; i++) 
      seqQueue[i] = 0;
    for (i = 0; i < DROP_QUEUE_LEN; i++)
      dropQueue[i].SeqNo = 0;

    dropflag = 0;

    call RadioControl.start();
    call SerialControl.start();
    call Timer.startPeriodic( 500 );
  }

  event void RadioControl.startDone(error_t error) {
    if (error == SUCCESS) {
      radioFull = FALSE;
    }
  }

  event void SerialControl.startDone(error_t error) {
    if (error == SUCCESS) {
      uartFull = FALSE;
    }
  }

  event void Timer.fired() {
    uint8_t i;
    atomic {
      for (i = 0; i < DROP_QUEUE_LEN; i++) {
        if (dropQueue[i].SeqNo > 0) {
          atomic {
            if (!radioFull)
            {
              message_t *pkt = &radioQueueBufs[radioIn];
              noderesend_t* nrmpkt = (noderesend_t*)(call UartPacket.getPayload(pkt, sizeof(noderesend_t)));
              nrmpkt->id = dropQueue[i].id;
              nrmpkt->SeqNo = dropQueue[i].SeqNo;
              call UartPacket.setPayloadLength(pkt, sizeof(noderesend_t));
              call UartAMPacket.setDestination(pkt, 1);
              call UartAMPacket.setType(pkt, AM_NODERESENDMSG);
              radioQueue[radioIn] = pkt;
              if (++radioIn >= RADIO_QUEUE_LEN)
                radioIn = 0;
              if (radioIn == radioOut)
                radioFull = TRUE;

              if (!radioBusy)
                {
                  post radioSendTask();
                  radioBusy = TRUE;
                }
            }
            else
              dropBlink();
          }
        }
      }
    }
  }

  event void SerialControl.stopDone(error_t error) {}
  event void RadioControl.stopDone(error_t error) {}

  uint8_t count = 0;

  message_t* ONE receive(message_t* ONE msg, void* payload, uint8_t len);
  bool checkmsg(message_t *msg, void *payload, uint8_t len);
  
  event message_t *RadioReceive.receive[am_id_t id](message_t *msg, void *payload, uint8_t len) {
    if (checkmsg(msg, payload, len))
      return receive(msg, payload, len);
    else 
      return uartQueue[uartIn];
  }

  message_t* receive(message_t *msg, void *payload, uint8_t len) {
    message_t *ret = msg;
    atomic {
      if (!uartFull)
    	{
    	  ret = uartQueue[uartIn];
    	  uartQueue[uartIn] = msg;

    	  uartIn = (uartIn + 1) % UART_QUEUE_LEN;
    	
    	  if (uartIn == uartOut)
    	    uartFull = TRUE;

    	  if (!uartBusy)
    	    {
    	      post uartSendTask();
    	      uartBusy = TRUE;
    	    }
    	}
      else
        dropBlink();
    }
    
    return ret;
  }

  bool checkmsg(message_t *msg, void *payload, uint8_t len) {
    if (len == sizeof(nodesense_t)) {
      nodesense_t* nsmpkt = (nodesense_t*)payload;
      if (seqQueue[nsmpkt->id] == 0) {
        seqQueue[nsmpkt->id] = nsmpkt->SeqNo;
      }
      else if (nsmpkt->SeqNo == 1) {
        seqQueue[nsmpkt->id] = nsmpkt->SeqNo;
      }
      else if (nsmpkt->SeqNo > seqQueue[nsmpkt->id] && nsmpkt->SeqNo - seqQueue[nsmpkt->id] > RADIO_QUEUE_LEN) {
        seqQueue[nsmpkt->id] = nsmpkt->SeqNo;
      }
      else if (nsmpkt->SeqNo < seqQueue[nsmpkt->id] && seqQueue[nsmpkt->id] - nsmpkt->SeqNo > 5*DROP_QUEUE_LEN) {
        seqQueue[nsmpkt->id] = nsmpkt->SeqNo;
      }
      else if (nsmpkt->SeqNo < seqQueue[nsmpkt->id]) {
        bool flag = FALSE;
        uint8_t i;
        atomic {
          for (i = 0; i < DROP_QUEUE_LEN; i++) {
            if (dropQueue[i].SeqNo == nsmpkt->SeqNo) {
              dropQueue[i].SeqNo = 0;
              flag = TRUE;
            }
          }
          if(!flag)
            return FALSE;
        }
      }
      else if (seqQueue[nsmpkt->id] < nsmpkt->SeqNo) {
        uint16_t seqno = seqQueue[nsmpkt->id];
        seqQueue[nsmpkt->id] = nsmpkt->SeqNo;
        call Leds.led2Toggle();
        if (seqno + 1 < nsmpkt->SeqNo) {
          uint16_t i;
          for (i = 1; i < nsmpkt->SeqNo - seqno; i++) {
            atomic {
              if (!radioFull)
              {
                message_t *pkt = &radioQueueBufs[radioIn];
                noderesend_t* nrmpkt = (noderesend_t*)(call UartPacket.getPayload(pkt, sizeof(noderesend_t)));
                nrmpkt->id = nsmpkt->id;
                nrmpkt->SeqNo = seqno + i;
                dropQueue[dropflag].SeqNo = nrmpkt->SeqNo;
                dropQueue[dropflag].id = nrmpkt->id;
                dropflag = (dropflag + 1)%DROP_QUEUE_LEN;
                call UartPacket.setPayloadLength(pkt, sizeof(noderesend_t));
                call UartAMPacket.setDestination(pkt, 1);
                call UartAMPacket.setType(pkt, AM_NODERESENDMSG);
                radioQueue[radioIn] = pkt;
                if (++radioIn >= RADIO_QUEUE_LEN)
                  radioIn = 0;
                if (radioIn == radioOut)
                  radioFull = TRUE;

                if (!radioBusy)
                  {
                    post radioSendTask();
                    radioBusy = TRUE;
                  }
              }
              else
                dropBlink();
            }
          }
        }
      }
    }
    else if (call RadioAMPacket.type(msg) == AM_NODERESENDMSG) {
      uint8_t i;
      noderesend_t* nsmpkt = (noderesend_t*)payload;
      atomic {
        for (i = 0; i < DROP_QUEUE_LEN; i++) {
          if (dropQueue[i].SeqNo == nsmpkt->SeqNo) {
            dropQueue[i].SeqNo = 0;
          }
        }
        return FALSE;
      }
    }
    return TRUE;
  }

  uint8_t tmpLen;
  
  task void uartSendTask() {
    uint8_t len;
    am_id_t id;
    am_addr_t addr, src;
    message_t* msg;
    atomic
      if (uartIn == uartOut && !uartFull)
    	{
    	  uartBusy = FALSE;
    	  return;
    	}

    msg = uartQueue[uartOut];
    tmpLen = len = call RadioPacket.payloadLength(msg);
    id = call RadioAMPacket.type(msg);
    addr = call RadioAMPacket.destination(msg);
    src = call RadioAMPacket.source(msg);
    call UartPacket.clear(msg);
    call UartAMPacket.setSource(msg, src);

    if (call UartSend.send[id](addr, uartQueue[uartOut], len) == SUCCESS)
      call Leds.led1Toggle();
    else
    {
    	failBlink();
    	post uartSendTask();
    }
  }

  event void UartSend.sendDone[am_id_t id](message_t* msg, error_t error) {
    if (error != SUCCESS)
      failBlink();
    else
      atomic
      	if (msg == uartQueue[uartOut])
    	  {
    	    if (++uartOut >= UART_QUEUE_LEN)
    	      uartOut = 0;
    	    if (uartFull)
    	      uartFull = FALSE;
    	  }
    post uartSendTask();
  }

  event message_t *UartReceive.receive[am_id_t id](message_t *msg, void *payload, uint8_t len) {
    message_t *ret = msg;
    bool reflectToken = FALSE;

    atomic {
      if (!radioFull)
    	{
    	  reflectToken = TRUE;
    	  ret = radioQueue[radioIn];
    	  radioQueue[radioIn] = msg;
    	  if (++radioIn >= RADIO_QUEUE_LEN)
    	    radioIn = 0;
    	  if (radioIn == radioOut)
    	    radioFull = TRUE;

    	  if (!radioBusy)
    	    {
    	      post radioSendTask();
    	      radioBusy = TRUE;
    	    }
    	}
      else
        dropBlink();
    }
    
    return ret;
  }

  task void radioSendTask() {
    uint8_t len;
    am_id_t id;
    am_addr_t addr,source;
    message_t* msg;
    
    atomic
      if (radioIn == radioOut && !radioFull)
    	{
    	  radioBusy = FALSE;
    	  return;
    	}

    msg = radioQueue[radioOut];
    len = call UartPacket.payloadLength(msg);
    addr = call UartAMPacket.destination(msg);
    source = call UartAMPacket.source(msg);
    id = call UartAMPacket.type(msg);

    call RadioPacket.clear(msg);
    call RadioAMPacket.setSource(msg, source);

    if (call RadioSend.send[id](addr, msg, len) == SUCCESS)
      call Leds.led0Toggle();
    else
    {
      failBlink();
      post radioSendTask();
    }
  }

  event void RadioSend.sendDone[am_id_t id](message_t* msg, error_t error) {
    if (error != SUCCESS)
      failBlink();
    else
      atomic
        if (msg == radioQueue[radioOut])
    	  {
    	    if (++radioOut >= RADIO_QUEUE_LEN)
    	      radioOut = 0;
    	    if (radioFull)
    	      radioFull = FALSE;
    	  }
    post radioSendTask();
  }
}  
