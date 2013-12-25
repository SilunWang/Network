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
  bool sendBusy;
  bool tranBusy;

  /* Current local state - interval, version and accumulated readings */
  nodesense_t local;

  nodesense_t window[MAX_QUEUESIZE];

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
  }

  event void RadioControl.stopDone(error_t error) {
  }


  event message_t* NodeReceive.receive[am_id_t id](message_t* msg, void* payload, uint8_t len) {

    //report_received();

    type = call AMPacket.type(msg);

    if(type == AM_NODESENSEMSG){ // original data
      //The node 1 forward the msg it received
      if(TOS_NODE_ID == 1)
      {
        nodesense_t *omsg = payload;
        //send data to base station
        if (!tranBusy && sizeof *omsg <= call NodeAMSend.maxPayloadLength[AM_NODESENSEMSG]())
        {
          memcpy(call NodeAMSend.getPayload[AM_NODESENSEMSG](msg, sizeof(*omsg)), omsg, sizeof *omsg);
          call AMPacket.setType(msg,AM_NODESENSEMSG);// set the type of msg
          if (call NodeAMSend.send[AM_NODESENSEMSG](0, msg, sizeof *omsg) == SUCCESS)
            tranBusy = TRUE;
        }
        if (!tranBusy)
          report_problem();
      }
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
          if (!tranBusy && sizeof *omsg <= call NodeAMSend.maxPayloadLength[AM_NODERESENDMSG]())
          {
            memcpy(call NodeAMSend.getPayload[AM_NODERESENDMSG](&retranmsg, sizeof(*omsg)), omsg, sizeof *omsg);
            call AMPacket.setType(&retranmsg,AM_NODERESENDMSG);// ask for retransmitting
            // ask node 2 for packet
            if (call NodeAMSend.send[AM_NODERESENDMSG](2, &retranmsg, sizeof *omsg) == SUCCESS)
            {
              tranBusy = TRUE;
            }
          } 

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
      if (packet_exist && !tranBusy && sizeof repacket <= call NodeAMSend.maxPayloadLength[AM_NODESENSEMSG]())
      {
        packet_exist = FALSE;
        memcpy(call NodeAMSend.getPayload[AM_NODESENSEMSG](&buffermsg, sizeof(repacket)), &repacket, sizeof repacket);
        call AMPacket.setType(&buffermsg,AM_NODESENSEMSG);
        if(TOS_NODE_ID == 1)
        {
          if (call NodeAMSend.send[AM_NODESENSEMSG](0, &buffermsg, sizeof(repacket)) == SUCCESS)
          {
            tranBusy = TRUE;   
          }       
        }
        if(TOS_NODE_ID == 2)
        {
          if (call NodeAMSend.send[AM_NODESENSEMSG](1, &buffermsg, sizeof repacket) == SUCCESS)
          {
            tranBusy = TRUE;          
          }
        }
      }
      else
      {
        if(!packet_exist)// if repacket does not exist, send type 2 packet to inform base
        {
          memcpy(call NodeAMSend.getPayload[AM_NODERESENDMSG](&stopaskmsg, sizeof(*omsg)), omsg, sizeof *omsg);
          call AMPacket.setType(&stopaskmsg,AM_NODERESENDMSG);
          if (call NodeAMSend.send[AM_NODERESENDMSG](0, &stopaskmsg, sizeof(*omsg)) == SUCCESS)
            tranBusy = TRUE;
          if (!tranBusy)
            report_problem(); 
        }

        return msg;
      }
      if (!tranBusy)
        report_problem(); 
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
    if (Treading == NREADINGS && Hreading == NREADINGS && Lreading == NREADINGS)
    {
    	if (!sendBusy && sizeof local <= call NodeAMSend.maxPayloadLength[AM_NODESENSEMSG]())
  	  {
          //storage the "local" value
          window[local.SeqNo%MAX_QUEUESIZE] = local;

          memcpy(call NodeAMSend.getPayload[AM_NODESENSEMSG](&sendBuf, sizeof(local)), &local, sizeof local);
          call AMPacket.setType(&sendBuf,AM_NODESENSEMSG);// set the type of msg

          if(TOS_NODE_ID == 2)
          {
            if (call NodeAMSend.send[AM_NODESENSEMSG](1, &sendBuf, sizeof local) == SUCCESS)
              sendBusy = TRUE;            
          }
          if(TOS_NODE_ID == 1)
          {
            if (call NodeAMSend.send[AM_NODESENSEMSG](0, &sendBuf, sizeof local) == SUCCESS)
              sendBusy = TRUE;
          }

  	  }
    	if (!sendBusy)
    	  report_problem();

    	Treading = 0;
    	Hreading = 0;
    	Lreading = 0;

    	/* Part 2 of cheap "time sync": increment our count if we didn't
    	   jump ahead. */
  	  local.SeqNo++;
    }

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
    if (error == SUCCESS)
      report_sent();
    else
      report_problem();

    tranBusy = FALSE;
    sendBusy = FALSE;
  }

  event void readTemp.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){    
      data = 0xffff;
      report_problem();   
    }
    data = -39.6 + 0.01*data;//转换成摄氏度值，这个公式根据SHT11数据手册
    TempData = data;
    local.curtime[Treading] = call Timer.getNow();
    local.temperature[Treading++] = TempData;
  }

  event void readHumidity.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){
       data = 0xffff; 
       report_problem();           
    }
    //HumidityData  = -4 + 4*data/100 + (-28/1000/10000)*(data*data);//转换成带温度补偿的湿度值
    //HumidityData = (TempData-25)*(1/100+8*data/100/1000)+HumidityData;
    HumidityData = -2.0468 + 0.0367*data - 1.5955/1000000 * (data*data);
    local.humidity[Hreading++] = HumidityData;
  }
  event void readLight.readDone(error_t result, uint16_t data) {
      if (result != SUCCESS){       
        data = 0xffff;
        report_problem();  
      }
      local.illumination[Lreading++] = 0.085*data;
    }

}
