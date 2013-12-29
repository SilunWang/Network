/*
 * Copyright (c) 2006 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

/**
 * NodeSense demo application. See README.txt file in this directory.
 *
 * @author David Gay
 */
#include "Timer.h"
#include "NodeSense.h"

module NodeSenseC @safe()
{
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    interface AMSend as NodeAMSend[am_id_t id];
    interface AMPacket;
    interface Packet as RadioPacket;;
    interface Receive as NodeReceive[am_id_t id];
    interface Timer<TMilli>;
    interface Read<uint16_t> as readTemp;
    interface Read<uint16_t> as readHumidity;
    interface Read<uint16_t> as readLight;
    interface Leds;
  }
}
implementation
{
  uint16_t TempData;
  uint16_t HumidityData;
  message_t sendBuf;

  /* Current local state - interval, version and accumulated readings */
  nodesense_t local;

  nodesense_t window[MAX_QUEUESIZE];

  message_t  radioQueueBufs[RADIO_QUEUE_LEN];
  message_t  * ONE_NOK radioQueue[RADIO_QUEUE_LEN];
  uint8_t    radioIn, radioOut;
  bool       radioBusy, radioFull;

  uint16_t i;
  am_id_t type;
  message_t buffermsg;
  message_t retranmsg;
  message_t stopaskmsg;

  uint8_t Treading; /* 0 to NREADINGS */
  uint8_t Hreading; /* 0 to NREADINGS */
  uint8_t Lreading; /* 0 to NREADINGS */

  // Use LEDs to report various status issues.
  void report_problem() { call Leds.led0Toggle(); }
  void report_sent() { call Leds.led1Toggle(); }
  void report_received() { call Leds.led2Toggle(); }

  event void Boot.booted() {
    local.interval = DEFAULT_INTERVAL;
    local.id = TOS_NODE_ID;
    local.SeqNo = 1;

    for (i = 0; i < RADIO_QUEUE_LEN; i++)
      radioQueue[i] = &radioQueueBufs[i];

    radioIn = radioOut = 0;
    radioBusy = FALSE;
    radioFull = TRUE;

    if (call RadioControl.start() != SUCCESS)
      report_problem();
  }

  void startTimer() {
    call Timer.startPeriodic(local.interval);
    Treading = 0;
    Hreading = 0;
    Lreading = 0;
  }

  event void RadioControl.startDone(error_t error) {
    startTimer();
    if (error == SUCCESS) {
      radioFull = FALSE;
    }
  }

  event void RadioControl.stopDone(error_t error) {
  }


  task void nodeSendTask() {
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
    len = call RadioPacket.payloadLength(msg);
    addr = call AMPacket.destination(msg);
    id = call AMPacket.type(msg);

    call RadioPacket.clear(msg);

    if (call NodeAMSend.send[id](addr, msg, len) == SUCCESS)
      report_sent();
    else
    {
      //report_received();
      post nodeSendTask();
    }
  }

  event message_t* NodeReceive.receive[am_id_t id](message_t* msg, void* payload, uint8_t len) {

    //report_received();

    type = call AMPacket.type(msg);

    if(type == AM_NODESENSEMSG){ // original data
      
      if (!radioFull)
      {
        message_t *pkt = &radioQueueBufs[radioIn];
        nodesense_t* omsg = (nodesense_t*)payload;
        nodesense_t* nrmpkt = (nodesense_t*)(call RadioPacket.getPayload(pkt, sizeof(nodesense_t)));
        nrmpkt->interval = omsg->interval;
        nrmpkt->id = 2;
        nrmpkt->SeqNo = omsg->SeqNo;
        nrmpkt->temperature[0] = omsg->temperature[0];
        nrmpkt->humidity[0] = omsg->humidity[0];
        nrmpkt->illumination[0] = omsg->illumination[0];
        nrmpkt->curtime[0] = omsg->curtime[0];
        call RadioPacket.setPayloadLength(pkt, sizeof(nodesense_t));
        call AMPacket.setDestination(pkt, 0);          
        call AMPacket.setType(pkt, AM_NODESENSEMSG);
        radioQueue[radioIn] = pkt;
        if (++radioIn >= RADIO_QUEUE_LEN)
          radioIn = 0;
        if (radioIn == radioOut)
          radioFull = TRUE;
        if (!radioBusy)
        {
          post nodeSendTask();
          radioBusy = TRUE;
        }
      }
      else
        report_problem();

    }
    else if(type == AM_NODERESENDMSG){ // retransmitted packet
      noderesend_t *omsg = (noderesend_t *)payload;
      nodesense_t repacket;
      bool packet_exist = FALSE;

      report_received();

      if(TOS_NODE_ID == 1) // Node 1 : mid node
      {
        uint16_t reid = omsg->id;
        //report_received();
        if(reid == 1)
        {
          //report_received();
          if(window[omsg->SeqNo%MAX_QUEUESIZE].SeqNo == omsg->SeqNo)
          {
            //report_received();
            repacket = window[omsg->SeqNo%MAX_QUEUESIZE];
            packet_exist = TRUE;
          }
        }
        if(reid == 2)
        {
          // transmit the message to remote node (node 2)
          if (!radioFull)
          {
            message_t *pkt = &radioQueueBufs[radioIn];
            noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
            nrmpkt->id = omsg->id;
            nrmpkt->SeqNo = omsg->SeqNo;
            call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
            call AMPacket.setDestination(pkt, 2);          
            call AMPacket.setType(pkt, AM_NODERESENDMSG);
            radioQueue[radioIn] = pkt;
            if (++radioIn >= RADIO_QUEUE_LEN)
              radioIn = 0;
            if (radioIn == radioOut)
              radioFull = TRUE;
            if (!radioBusy)
            {
              post nodeSendTask();
              radioBusy = TRUE;
            }
          }
          else
            report_problem();
          return msg;
        }
      }
      if(TOS_NODE_ID == 2) // Node 2: remote node
      {
        if(window[omsg->SeqNo%MAX_QUEUESIZE].SeqNo == omsg->SeqNo)
        {
          repacket = window[omsg->SeqNo%MAX_QUEUESIZE];
          packet_exist = TRUE;
        }
      }
      // if repacket is not null, retransmit
      if (packet_exist)
      {
        packet_exist = FALSE;
        if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          nodesense_t* nrmpkt = (nodesense_t*)(call RadioPacket.getPayload(pkt, sizeof(nodesense_t)));
          nrmpkt->interval = repacket.interval;
          nrmpkt->id = repacket.id;
          nrmpkt->SeqNo = repacket.SeqNo;
          nrmpkt->temperature[0] = repacket.temperature[0];
          nrmpkt->humidity[0] = repacket.humidity[0];
          nrmpkt->illumination[0] = repacket.illumination[0];
          nrmpkt->curtime[0] = repacket.curtime[0];
          call RadioPacket.setPayloadLength(pkt, sizeof(nodesense_t));
          if(TOS_NODE_ID == 1)
          {
            call AMPacket.setDestination(pkt, 0); 
          }
          if(TOS_NODE_ID == 2)
          {
            call AMPacket.setDestination(pkt, 1);   
          }        
          call AMPacket.setType(pkt, AM_NODESENSEMSG);
          radioQueue[radioIn] = pkt;
          if (++radioIn >= RADIO_QUEUE_LEN)
            radioIn = 0;
          if (radioIn == radioOut)
            radioFull = TRUE;
          if (!radioBusy)
          {
            post nodeSendTask();
            radioBusy = TRUE;
          }
        }
        else
          report_problem();

      }
      else
      {
        if(!packet_exist)// if repacket does not exist, send type 2 packet to inform base
        {
          if (!radioFull)
          {
            message_t *pkt = &radioQueueBufs[radioIn];
            noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
            nrmpkt->id = omsg->id;
            nrmpkt->SeqNo = omsg->SeqNo;
            call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
            call AMPacket.setDestination(pkt, 0);        
            call AMPacket.setType(pkt, AM_NODERESENDMSG);
            radioQueue[radioIn] = pkt;
            if (++radioIn >= RADIO_QUEUE_LEN)
              radioIn = 0;
            if (radioIn == radioOut)
              radioFull = TRUE;
            if (!radioBusy)
            {
              post nodeSendTask();
              radioBusy = TRUE;
            }
          }
          else
            report_problem();

        }

        return msg;
      }
    }
    else if(type == AM_SENSEINTERVALMSG){ // packet for changing interval
        senseinterval_t *omsg = (senseinterval_t *)payload;
        local.interval = omsg->interval;
        startTimer();
    }
    else
      report_problem();

    return msg;
  }

  /* At each sample period:
     - if local sample buffer is full, send accumulated samples
     - read next sample
  */
  event void Timer.fired() {
    atomic{
      if (call readTemp.read() != SUCCESS)//读取温度值
        report_problem();

      if (call readHumidity.read() != SUCCESS)//读取湿度值
        report_problem();

      if (call readLight.read() != SUCCESS)//读取光照值
        report_problem();
    }
  }



  event void NodeAMSend.sendDone[am_id_t id](message_t* msg, error_t error) {
      atomic
        if (msg == radioQueue[radioOut])
        {
          if (++radioOut >= RADIO_QUEUE_LEN)
            radioOut = 0;
          if (radioFull)
            radioFull = FALSE;
        }
    post nodeSendTask();
  }

  void senddata()
  {
    //if (Treading == NREADINGS && Hreading == NREADINGS && Lreading == NREADINGS)
    //{
      window[local.SeqNo%MAX_QUEUESIZE] = local;
      if (!radioFull)
      {
      
        message_t *pkt = &radioQueueBufs[radioIn];
        nodesense_t* nrmpkt = (nodesense_t*)(call RadioPacket.getPayload(pkt, sizeof(nodesense_t)));
        nrmpkt->interval = local.interval;
        nrmpkt->id = TOS_NODE_ID;
        nrmpkt->SeqNo = local.SeqNo;
        nrmpkt->temperature[0] = local.temperature[0];
        nrmpkt->humidity[0] = local.humidity[0];
        nrmpkt->illumination[0] = local.illumination[0];
        nrmpkt->curtime[0] = local.curtime[0];
        call RadioPacket.setPayloadLength(pkt, sizeof(nodesense_t));
        if(TOS_NODE_ID == 2)
        {
          call AMPacket.setDestination(pkt, 1);
        }
        if(TOS_NODE_ID == 1)
        {
          call AMPacket.setDestination(pkt, 0);          
        }
        call AMPacket.setType(pkt, AM_NODESENSEMSG);
        radioQueue[radioIn] = pkt;
        if (++radioIn >= RADIO_QUEUE_LEN)
          radioIn = 0;
        if (radioIn == radioOut)
          radioFull = TRUE;
        if (!radioBusy)
        {
          post nodeSendTask();
          radioBusy = TRUE;
        }
      }
      
      Treading = 0;
      Hreading = 0;
      Lreading = 0;

      /* Part 2 of cheap "time sync": increment our count if we didn't
         jump ahead. */
      local.SeqNo++;
    //}
  }


  event void readTemp.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){    
      data = 0xffff;
      report_problem();   
    }
    data = -39.6 + 0.01*(data&0x3fff);//转换成摄氏度值，这个公式根据SHT11数据手册
    TempData = data;
    local.curtime[Treading] = call Timer.getNow();
    local.temperature[Treading++] = TempData;
    //senddata();
  }

  event void readHumidity.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){
       data = 0xffff; 
       report_problem();           
    }
    //HumidityData  = -4 + 4*data/100 + (-28/1000/10000)*(data*data);//转换成带温度补偿的湿度值
    //HumidityData = (TempData-25)*(1/100+8*data/100/1000)+HumidityData;
    data = (data&0x0fff);
    HumidityData = -2.0468 + 0.0367*data - 1.5955/1000000 * (data*data);
    local.curtime[Hreading] = call Timer.getNow();
    local.humidity[Hreading++] = HumidityData;
    //senddata();
  }
  event void readLight.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){       
      data = 0xffff;
      report_problem();  
    }
    local.curtime[Lreading] = call Timer.getNow();
    local.illumination[Lreading++] = 0.085*data;
    senddata();
  }
}
