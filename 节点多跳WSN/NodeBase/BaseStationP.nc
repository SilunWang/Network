
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
    RADIO_QUEUE_LEN = 50,
    SEQ_QUEUE_LEN = 10,
    DROP_QUEUE_LEN = 200,
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
    //call Leds.led0Toggle();
  }

  void failBlink() {
    //call Leds.led0Toggle();
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
    call Timer.startPeriodic( 1000 );
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
      return msg;
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
    if (call RadioAMPacket.type(msg) == AM_NODESENSEMSG) {
      nodesense_t* nsmpkt = (nodesense_t*)payload;
      if (seqQueue[nsmpkt->id] == 0) {
        seqQueue[nsmpkt->id] = nsmpkt->SeqNo;
      }
      else if (nsmpkt->SeqNo == 1) {
        seqQueue[nsmpkt->id] = nsmpkt->SeqNo;
      }
      else if (nsmpkt->SeqNo > seqQueue[nsmpkt->id] && nsmpkt->SeqNo - seqQueue[nsmpkt->id] > DROP_QUEUE_LEN) {
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
            if (dropQueue[i].SeqNo == nsmpkt->SeqNo && dropQueue[i].id == nsmpkt->id) {
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
        if (seqno + 1 < nsmpkt->SeqNo) {
          uint16_t i;
          for (i = 1; i < nsmpkt->SeqNo - seqno; i++) {
            atomic {
              while(dropQueue[dropflag].SeqNo != 0)
                dropflag = (dropflag + 1)%DROP_QUEUE_LEN;
              dropQueue[dropflag].SeqNo = seqno + i;
              dropQueue[dropflag].id = nsmpkt->id;
              dropflag = (dropflag + 1)%DROP_QUEUE_LEN;
              if (!radioFull)
              {
                message_t *pkt = &radioQueueBufs[radioIn];
                noderesend_t* nrmpkt = (noderesend_t*)(call UartPacket.getPayload(pkt, sizeof(noderesend_t)));
                nrmpkt->id = nsmpkt->id;
                nrmpkt->SeqNo = seqno + i;
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
            call Leds.led0Toggle();
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
      call Leds.led2Toggle();
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
