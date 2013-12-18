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
    interface AMSend;
    interface Receive;
    interface Timer<TMilli>;
    interface Read<uint16_t> as readTemp;
    interface Read<uint16_t> as readHumidity;
    interface Read<uint16_t> as readLight;
    interface Leds;
  }
}
implementation
{
  #define SAMPLING_FREQUENCY 100
  uint16_t TempData;
  uint16_t HumidityData;
  message_t sendBuf;
  bool sendBusy;

  /* Current local state - interval, version and accumulated readings */
  nodesense_t local;

  uint8_t Treading; /* 0 to NREADINGS */
  uint8_t Hreading; /* 0 to NREADINGS */
  uint8_t Lreading; /* 0 to NREADINGS */

  /* When we head an NodeSense message, we check it's sample count. If
     it's ahead of ours, we "jump" forwards (set our count to the received
     count). However, we must then suppress our next count increment. This
     is a very simple form of "time" synchronization (for an abstract
     notion of time). */
  bool suppressCountChange;

  // Use LEDs to report various status issues.
  void report_problem() { call Leds.led0Toggle(); }
  void report_sent() { call Leds.led1Toggle(); }
  void report_received() { call Leds.led2Toggle(); }

  event void Boot.booted() {
    local.interval = DEFAULT_INTERVAL;
    local.id = TOS_NODE_ID;
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

  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    nodesense_t *omsg = payload;

    report_received();

    if(TOS_NODE_ID == 2)
    {
      sendBusy = FALSE;
      if (!sendBusy && sizeof local <= call AMSend.maxPayloadLength())
      {
        // Don't need to check for null because we've already checked length
        // above
        memcpy(call AMSend.getPayload(&msg, sizeof(local)), &local, sizeof local);
        if (call AMSend.send(AM_BROADCAST_ADDR, &msg, sizeof local) == SUCCESS)
          sendBusy = TRUE;
      }
      if (!sendBusy)
        report_problem();
    }

    /* If we receive a newer version, update our interval. 
       If we hear from a future count, jump ahead but suppress our own change
    */
    if (omsg->version > local.version)
      {
	local.version = omsg->version;
	local.interval = omsg->interval;
	startTimer();
      }
    if (omsg->count > local.count)
      {
	local.count = omsg->count;
	suppressCountChange = TRUE;
      }

    return msg;
  }

  /* At each sample period:
     - if local sample buffer is full, send accumulated samples
     - read next sample
  */
  event void Timer.fired() {
    if (Treading == NREADINGS && Hreading == NREADINGS && Lreading == NREADINGS)
      {
	if (!sendBusy && sizeof local <= call AMSend.maxPayloadLength())
	  {
	    // Don't need to check for null because we've already checked length
	    // above
	    memcpy(call AMSend.getPayload(&sendBuf, sizeof(local)), &local, sizeof local);
	    if (call AMSend.send(AM_BROADCAST_ADDR, &sendBuf, sizeof local) == SUCCESS)
	      sendBusy = TRUE;
	  }
	if (!sendBusy)
	  report_problem();

	Treading = 0;
	Hreading = 0;
	Lreading = 0;

	/* Part 2 of cheap "time sync": increment our count if we didn't
	   jump ahead. */
	if (!suppressCountChange)
	  local.count++;
	suppressCountChange = FALSE;
      }

    if (call readTemp.read() != SUCCESS)//读取温度值
      report_problem();

    if (call readHumidity.read() != SUCCESS)//读取湿度值
      report_problem();

    if (call readLight.read() != SUCCESS)//读取光照值
      report_problem();

  }

  event void AMSend.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS)
      report_sent();
    else
      report_problem();

    sendBusy = FALSE;
  }

  event void readTemp.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){    
      data = 0xffff;
      report_problem();   
    }
    data = -40.1 + 0.01*data;//转换成摄氏度值，这个公式根据SHT11数据手册
    TempData = data;
    local.curtime[Treading] = call Timer.getNow();
    local.temperature[Treading++] = TempData;
  }

  event void readHumidity.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){
       data = 0xffff;
       report_problem();           
    }
    HumidityData  = -4 + 4*data/100 + (-28/1000/10000)*(data*data);//转换成带温度补偿的湿度值
    HumidityData = (TempData-25)*(1/100+8*data/100/1000)+HumidityData;//但结果不知道这个转换公式转换的结果对不对
    local.humidity[Hreading++] = HumidityData;
  }
  event void readLight.readDone(error_t result, uint16_t data) {
      if (result != SUCCESS){       
        data = 0xffff;
        report_problem();  
      }
      local.illumination[Lreading++] = data;
    }

}
