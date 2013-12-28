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
#include "NodeDDP.h"

module NodeDDPC @safe() {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    
    interface AMSend as RadioSend[am_id_t id];
    interface Receive as RadioReceive[am_id_t id];
    interface Packet as RadioPacket;
    interface AMPacket as RadioAMPacket;

    interface Leds;
  }
}

implementation
{
  enum {
    RADIO_QUEUE_LEN = 10,
    DROP_QUEUE_LEN = 300,
    DATA_BUF_LEN = 100,
    DATA_QUEUE_LEN = 1000,
  };

  message_t  radioQueueBufs[RADIO_QUEUE_LEN];
  message_t  * ONE_NOK radioQueue[RADIO_QUEUE_LEN];
  uint8_t    radioIn, radioOut;
  bool       radioBusy, radioFull;

  uint16_t        seqQueue;
  uint16_t        tempseq;
  uint8_t         dropflag;
  uint8_t         dropstart;
  uint16_t        dropcount;
  uint16_t        dropQueue[DROP_QUEUE_LEN];
  uint16_t        dropQueue2[DROP_QUEUE_LEN];

  uint16_t        datacount;
  nodedata_t      databuf[DATA_BUF_LEN];
  nodedata_t      dataQueue[DATA_QUEUE_LEN];

  /**** only for commander ****/
  result_t res;
  bool rec_one_flag;
  bool rec_two_flag;
  bool num_one_flag;
  bool num_two_flag;
  uint16_t gb_node_count;
  /**** end ****/

  task void radioSendTask();
  uint16_t getMin(uint16_t arr[], uint16_t length);
  uint16_t getMax(uint16_t arr[], uint16_t length);
  uint16_t randomized_select(uint16_t arr[], uint16_t low, uint16_t high, uint16_t i);
  uint16_t partition(uint16_t arr[], uint16_t low, uint16_t high);
  void QuickSort(uint16_t arr[], uint16_t l, uint16_t r);
  double getAverage(uint16_t arr[], uint16_t length);

  double getAverage(uint16_t arr[], uint16_t length)
  {
    uint16_t aver = 0;
    uint16_t i;
    for(i = 0; i < length; i++)
    {
      aver += arr[i];
    }
    aver = (double)aver/length;
    return aver;
  }

  uint16_t getMin(uint16_t arr[], uint16_t length)
  {
    uint16_t min = arr[0];
    uint16_t i;
    for(i = 1; i < length; i++){
      if(arr[i] < min)
        min = arr[i];
    }
    return min;
  }

  uint16_t getMax(uint16_t arr[], uint16_t length)
  {
    uint16_t max = arr[0];
    uint16_t i;
    for(i = 1; i < length; i++){
      if(arr[i] > max)
        max = arr[i];
    }
    return max;
  }


  uint16_t randomized_select(uint16_t arr[], uint16_t low, uint16_t high, uint16_t i)
  {
    uint16_t pivot;
    uint16_t k;
    if(low == high)
      return arr[low];
    pivot = partition(arr, low, high);
    k = pivot-low +1;
    if(i == k)
      return arr[pivot];
    else if(i < k)
      return randomized_select(arr, low, pivot-1, i);
    else
      return randomized_select(arr, pivot+1, high, i-k);
  }

  uint16_t partition(uint16_t arr[], uint16_t low, uint16_t high)
  {
    uint16_t tmp;
    tmp = arr[low];
    while(low < high){
      while(low < high && arr[high] >= tmp)
        high--;
      arr[low] = arr[high];
      while(low < high && arr[low] <= tmp)
        low++;
      arr[high] = arr[low];
    }
    arr[low] = tmp;
    return low;
  }

  void QuickSort(uint16_t arr[], uint16_t l, uint16_t r)
  {
    if(l < r)
    {
      uint16_t pivot = partition(arr, l, r);
      QuickSort(arr, l, pivot-1);
      QuickSort(arr, pivot+1, r);
    }
  }

  void dropBlink() {
    call Leds.led0Toggle();
  }

  void failBlink() {
    call Leds.led2Toggle();
  }

  // Use LEDs to report various status issues.
  void report_problem() { /*call Leds.led0Toggle();*/ }
  void report_sent() { call Leds.led1Toggle(); }
  void report_received() { call Leds.led2Toggle(); }

  event void Boot.booted() {
    uint16_t i;
    for (i = 0; i < RADIO_QUEUE_LEN; i++)
      radioQueue[i] = &radioQueueBufs[i];

    radioIn = radioOut = 0;
    radioBusy = FALSE;
    radioFull = TRUE;

    for (i = 0; i < DROP_QUEUE_LEN; i++)
      dropQueue[i] = 0;
    for (i = 0; i < DROP_QUEUE_LEN; i++)
      dropQueue2[i] = 0;

    dropflag = 0;
    dropstart = 0;
    dropcount = 0;
    datacount = 1;
    tempseq = 2001;
    seqQueue = 0;

    if(TOS_NODE_ID == NODE_COMMANDER)
    {
      res.group_id = GROUP_ID;
      res.sum = 0;
      res.average = 0; 
      rec_one_flag = FALSE;
      rec_two_flag = FALSE;   
      num_one_flag = FALSE;
      num_two_flag = FALSE;
      gb_node_count = 0;
    }

    call RadioControl.start();
  }

  event void RadioControl.startDone(error_t error) {
    if (error == SUCCESS) {
      radioFull = FALSE;
    }
  }

  event void RadioControl.stopDone(error_t error) {}

  uint8_t count = 0;
  void receive_data(message_t*ONE msg, void* payload);
  void receive_resendmsg(void* payload);
  void resend(nodedata_t* nsmpkt, uint16_t sequence_number);
  void simple_resend(nodedata_t* nsmpkt, uint16_t sequence_number);
  void assistance_cal();
  void result_cal(void* payload);
  void send_pktnum();
  void request_pktnum();
  void check_totalnum(void* payload);
  void stop_send_res();
  void sendpacket(uint16_t dropcount)
  {
        if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
          nrmpkt->id = dropcount;
          nrmpkt->sequence_number = dropcount;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          if (TOS_NODE_ID == NODE_ONE)
          {
            call RadioAMPacket.setDestination(pkt, NODE_TWO);
          }
          else if (TOS_NODE_ID == NODE_TWO)
          {
            call RadioAMPacket.setDestination(pkt, NODE_COMMANDER);
          }
          else if (TOS_NODE_ID == NODE_COMMANDER)
          {
            call RadioAMPacket.setDestination(pkt, NODE_ONE);
          }
          call RadioAMPacket.setType(pkt, AM_NODERESENDMSG);
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
  }
  
  event message_t *RadioReceive.receive[am_id_t id](message_t *msg, void *payload, uint8_t len) {
    am_id_t type = call RadioAMPacket.type(msg);
    if (type == AM_NODEDATAMSG)            // receive original data
      receive_data(msg,payload);
    else if (type == AM_NODERESENDMSG)    // receive resend request and resend
      receive_resendmsg(payload);
    else if (type == AM_NODECOMMANDERMSG)  
    {
      if(TOS_NODE_ID == NODE_ONE || TOS_NODE_ID == NODE_TWO)
        send_pktnum();                     // send the received packet number to commander
      if(TOS_NODE_ID == NODE_COMMANDER)
        check_totalnum(payload);           // check the packet number from node 1,2
    }      
    else if (type == AM_NODEINFOMSG)   
    {
      if(TOS_NODE_ID == NODE_ONE || TOS_NODE_ID == NODE_TWO)
        assistance_cal();                  // calculate and send the res to commander
      if(TOS_NODE_ID == NODE_COMMANDER)
        result_cal(payload);               // calculate result and send to Node 0
    }
    else if (type == AM_NODEACKMSG)        // stop sending packet to Node 0 (stop timmer)
      stop_send_res();
    if ((seqQueue == MAX_DATA_SIZE || tempseq <= MAX_DATA_SIZE) && dropcount == 0)
      call Leds.led2Toggle(); //receive total 2000 data
    return msg;
  }

  void receive_data(message_t *msg, void *payload) {
    nodedata_t* nsmpkt = (nodedata_t*)payload;
    if (tempseq > MAX_DATA_SIZE)
    {
      if (nsmpkt->sequence_number == MAX_DATA_SIZE) {
        dropBlink();
        tempseq = 0;
      }
      if (nsmpkt->sequence_number < seqQueue) {
        bool flag = FALSE;
        uint8_t i;
        atomic {
          if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == 0)
            return;
          else if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == nsmpkt->sequence_number)
          {
            dropcount--;
            sendpacket(dropcount);
            dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] = 0;
            flag = TRUE;    
          }
          else
          {
            for (i = dropstart; i < dropflag; i++)
            {
              if (dropQueue2[i] == nsmpkt->sequence_number)
              {
                dropcount--;
                sendpacket(dropcount);
                dropQueue2[i] = 0;
                flag = TRUE;
                break;
              } 
            }
          }
        }
        if (!flag)
          return;
      }
      else if (seqQueue < nsmpkt->sequence_number) {
        uint16_t sequence_number = seqQueue;
        call Leds.led1Toggle();
        seqQueue = nsmpkt->sequence_number;
        resend(nsmpkt, sequence_number);
      }
      databuf[nsmpkt->sequence_number % DATA_BUF_LEN].sequence_number = nsmpkt->sequence_number;
      databuf[nsmpkt->sequence_number % DATA_BUF_LEN].random_integer = nsmpkt->random_integer;
      if (TOS_NODE_ID == NODE_ONE && nsmpkt->random_integer < -3000)
      {
        dataQueue[datacount].sequence_number = nsmpkt->sequence_number;
        dataQueue[datacount].random_integer = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_TWO && nsmpkt->random_integer > 3000)
      {
        dataQueue[datacount].sequence_number = nsmpkt->sequence_number;
        dataQueue[datacount].random_integer = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_COMMANDER && nsmpkt->random_integer >= -3000 && nsmpkt->random_integer <= 3000)
      {
        dataQueue[datacount].sequence_number = nsmpkt->sequence_number;
        dataQueue[datacount].random_integer = nsmpkt->random_integer;
        datacount++;
      }
    }
    else 
    {
      if (tempseq == MAX_DATA_SIZE) {
        dropBlink();
        tempseq = 0;
      }  
      if (nsmpkt->sequence_number < tempseq) {
        bool flag = FALSE;
        uint8_t i;
        atomic {
          if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == 0)
            return;
          else if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == nsmpkt->sequence_number)
          {
            dropcount--;
            sendpacket(dropcount);
            dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] = 0;
            while(dropQueue2[dropstart] == 0 && dropstart < dropflag)
              dropstart++;
            for (i = dropstart; i < dropflag; i++)
            {
              if (dropQueue2[i] % DROP_QUEUE_LEN == nsmpkt->sequence_number % DROP_QUEUE_LEN)
              {
                dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] = dropQueue2[i];
                dropQueue2[i] = 0;
                break;
              } 
            }
            flag = TRUE;       
          }
          else
          {
            while(dropQueue2[dropstart] == 0 && dropstart < dropflag)
                dropstart++;
            for (i = dropstart; i < dropflag; i++)
            {
              dropcount--;
              sendpacket(dropcount);
              dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] = 0;
              while(dropQueue2[dropstart] == 0 && dropstart < dropflag)
                dropstart++;
              for (i = dropstart; i < dropflag; i++)
              {
                if (dropQueue2[i] % DROP_QUEUE_LEN == nsmpkt->sequence_number % DROP_QUEUE_LEN)
                {
                  dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] = dropQueue2[i];
                  dropQueue2[i] = 0;
                  break;
                } 
              }
              flag = TRUE;
            }
          }
        }
        if (!flag)
          return;
      }
      else if (tempseq < nsmpkt->sequence_number) {
        bool flag = FALSE;
        uint16_t i, j;
        //call Leds.led2Toggle();
        for (j = tempseq + 1; j <= nsmpkt->sequence_number; j++)
        {          
          if (dropQueue[j % DROP_QUEUE_LEN] == 0)
            continue;
          else if (dropQueue[j % DROP_QUEUE_LEN] == j)
          {
            if (j == nsmpkt->sequence_number)
            {
              call Leds.led1Toggle();
              dropcount--;
              sendpacket(dropcount);
              dropQueue[j % DROP_QUEUE_LEN] = 0;
              while(dropQueue2[dropstart] == 0 && dropstart < dropflag)
                dropstart++;
              for (i = dropstart; i < dropflag; i++)
              {
                if (dropQueue2[i] != 0 && dropQueue2[i] % DROP_QUEUE_LEN == j % DROP_QUEUE_LEN)
                {
                  dropQueue[j % DROP_QUEUE_LEN] = dropQueue2[i];
                  dropQueue2[i] = 0;
                  break;
                } 
              }
              flag = TRUE;
            }   
            else
            {
              simple_resend(nsmpkt, j);
            }         
          }
          else
          {
            while(dropQueue2[dropstart] == 0 && dropstart < dropflag)
                dropstart++;
            for (i = dropstart; i < dropflag; i++)
            {
              if (dropQueue2[i] == j)
              {
                if (j == nsmpkt->sequence_number)
                {
                  call Leds.led1Toggle();
                  dropcount--;
                  sendpacket(dropcount);
                  dropQueue2[i] = 0;
                  flag = TRUE;
                }  
                else
                {
                  simple_resend(nsmpkt, tempseq);
                }
              } 
            }
          }          
        }
        tempseq = nsmpkt->sequence_number;
        if (!flag)
          return;
      }
      databuf[nsmpkt->sequence_number % DATA_BUF_LEN].sequence_number = nsmpkt->sequence_number;
      databuf[nsmpkt->sequence_number % DATA_BUF_LEN].random_integer = nsmpkt->random_integer;
      if (TOS_NODE_ID == NODE_ONE && nsmpkt->random_integer < -3000)
      {
        dataQueue[datacount].sequence_number = nsmpkt->sequence_number;
        dataQueue[datacount].random_integer = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_TWO && nsmpkt->random_integer > 3000)
      {
        dataQueue[datacount].sequence_number = nsmpkt->sequence_number;
        dataQueue[datacount].random_integer = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_COMMANDER && nsmpkt->random_integer >= -3000 && nsmpkt->random_integer <= 3000)
      {
        dataQueue[datacount].sequence_number = nsmpkt->sequence_number;
        dataQueue[datacount].random_integer = nsmpkt->random_integer;
        datacount++;
      }
    }
    return;
  }


  void resend(nodedata_t* nsmpkt, uint16_t sequence_number) {
    uint16_t i;
    uint16_t temp = nsmpkt->sequence_number - sequence_number;
    for (i = 1; i < temp; i++) {
      atomic {
        dropcount++;
        sendpacket(dropcount);
        if (dropQueue[(sequence_number + i) % DROP_QUEUE_LEN] == 0)
          dropQueue[(sequence_number + i) % DROP_QUEUE_LEN] = sequence_number + i;
        else
        {
          dropQueue2[dropflag] = sequence_number + i;
          dropflag++;
        }
        if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
          nrmpkt->id = TOS_NODE_ID;
          nrmpkt->sequence_number = sequence_number + i;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          if (TOS_NODE_ID == NODE_ONE)
          {
            call RadioAMPacket.setDestination(pkt, NODE_TWO);
          }
          else if (TOS_NODE_ID == NODE_TWO)
          {
            call RadioAMPacket.setDestination(pkt, NODE_COMMANDER);
          }
          else if (TOS_NODE_ID == NODE_COMMANDER)
          {
            call RadioAMPacket.setDestination(pkt, NODE_ONE);
          }
          call RadioAMPacket.setType(pkt, AM_NODERESENDMSG);
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
        {
          dropBlink();
        }
        if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
          nrmpkt->id = TOS_NODE_ID;
          nrmpkt->sequence_number = sequence_number + i;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          if (TOS_NODE_ID == NODE_ONE)
          {
            call RadioAMPacket.setDestination(pkt, NODE_COMMANDER);
          }
          else if (TOS_NODE_ID == NODE_TWO)
          {
            call RadioAMPacket.setDestination(pkt, NODE_ONE);
          }
          else if (TOS_NODE_ID == NODE_COMMANDER)
          {
            call RadioAMPacket.setDestination(pkt, NODE_TWO);
          }
          call RadioAMPacket.setType(pkt, AM_NODERESENDMSG);
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
        {
          dropBlink();
        }
      }
    }
  }

  void simple_resend(nodedata_t* nsmpkt, uint16_t sequence_number) {
    if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
          nrmpkt->id = TOS_NODE_ID;
          nrmpkt->sequence_number = sequence_number;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          if (TOS_NODE_ID == NODE_ONE)
          {
            call RadioAMPacket.setDestination(pkt, NODE_TWO);
          }
          else if (TOS_NODE_ID == NODE_TWO)
          {
            call RadioAMPacket.setDestination(pkt, NODE_COMMANDER);
          }
          else if (TOS_NODE_ID == NODE_COMMANDER)
          {
            call RadioAMPacket.setDestination(pkt, NODE_ONE);
          }
          call RadioAMPacket.setType(pkt, AM_NODERESENDMSG);
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
        if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
          nrmpkt->id = TOS_NODE_ID;
          nrmpkt->sequence_number = sequence_number;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          if (TOS_NODE_ID == NODE_ONE)
          {
            call RadioAMPacket.setDestination(pkt, NODE_COMMANDER);
          }
          else if (TOS_NODE_ID == NODE_TWO)
          {
            call RadioAMPacket.setDestination(pkt, NODE_ONE);
          }
          else if (TOS_NODE_ID == NODE_COMMANDER)
          {
            call RadioAMPacket.setDestination(pkt, NODE_TWO);
          }
          call RadioAMPacket.setType(pkt, AM_NODERESENDMSG);
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
    {
      dropBlink();
    }
  }

  /*
  * logic handler
  **/
  void receive_resendmsg(void* payload)
  {
    nodedata_t resend_packet;
    noderesend_t* resend_info = (noderesend_t*)payload;
    uint16_t require_id = resend_info->id;
    uint16_t require_seq = resend_info->sequence_number;
    bool resend_flag = FALSE;
    //call Leds.led0Toggle();
    if(require_id == NODE_ONE || require_id == NODE_TWO || require_id == NODE_COMMANDER)
    {
      if(databuf[require_seq % DATA_BUF_LEN].sequence_number == require_seq)
      {
        resend_packet = databuf[require_seq % DATA_BUF_LEN];  
        resend_flag = TRUE;
      }
      if(resend_flag)
      {
        resend_flag = FALSE;
        if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          nodedata_t* nrmpkt = (nodedata_t*)(call RadioPacket.getPayload(pkt, sizeof(nodedata_t)));
          nrmpkt->sequence_number = resend_packet.sequence_number;
          nrmpkt->random_integer = resend_packet.random_integer;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          call RadioAMPacket.setDestination(pkt, require_id);
          call RadioAMPacket.setType(pkt, AM_NODEDATAMSG);
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
      }    
    }
  }

  void request_pktnum()
  {
    if (!radioFull)
    {
      message_t *pkt = &radioQueueBufs[radioIn];
      noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
      nrmpkt->id = TOS_NODE_ID;
      nrmpkt->sequence_number = 0;
      call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
      // send to Node one
      call RadioAMPacket.setDestination(pkt, NODE_ONE);    
      call RadioAMPacket.setType(pkt, AM_NODECOMMANDERMSG);
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
      // send to node two
      call RadioAMPacket.setDestination(pkt, NODE_TWO); 
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
  }

  void send_pktnum()
  {
    if (!radioFull)
    {
      message_t *pkt = &radioQueueBufs[radioIn];
      noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
      nrmpkt->id = TOS_NODE_ID;
      nrmpkt->sequence_number = datacount;
      call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
      call RadioAMPacket.setDestination(pkt, NODE_COMMANDER);    // send to Node commander
      call RadioAMPacket.setType(pkt, AM_NODECOMMANDERMSG);
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
  }

  void check_totalnum(void* payload)
  {
    noderesend_t* assist_num = (noderesend_t*)payload;
    if(assist_num->id==NODE_ONE && !num_one_flag)
    {
      num_one_flag = TRUE;
      gb_node_count += assist_num->sequence_number;
    }
    if(assist_num->id==NODE_TWO && !num_two_flag)
    {
      num_two_flag = TRUE;
      gb_node_count += assist_num->sequence_number;
    }
    if(num_one_flag && num_two_flag)
    {
      gb_node_count += datacount;
      if(gb_node_count == MAX_DATA_SIZE)
      {
        // finish data receiving, require node's data
        if (!radioFull)
        {
          message_t *pkt = &radioQueueBufs[radioIn];
          noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
          nrmpkt->id = NODE_COMMANDER;
          nrmpkt->sequence_number = 0;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          // send to Node one
          call RadioAMPacket.setDestination(pkt, NODE_ONE);    
          call RadioAMPacket.setType(pkt, AM_NODEINFOMSG);
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
          // send to Node two
          call RadioAMPacket.setDestination(pkt, NODE_TWO); 
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
      }
      else
      {
        gb_node_count = 0;
      }
    }
  }

  void stop_send_res()
  {
    // stop timmer
  }

  void assistance_cal()
  {
    uint16_t i;
    message_t msg_assistantbuf;
    uint32_t data_sum = 0;
    nodeassist_t assistant_info;

    if(TOS_NODE_ID == NODE_ONE)
    {
      //calculate min data
      uint32_t data_min = 10002;
      for(i = 0; i < datacount; ++i)
      {
        if(dataQueue[i].random_integer < data_min)
          data_min = dataQueue[i].random_integer;
        data_sum += dataQueue[i].random_integer;
      }
      assistant_info.id = NODE_ONE;
      assistant_info.value = data_min;
    }
    else if(TOS_NODE_ID == NODE_TWO)
    {
      //calculate max data
      uint32_t data_max=0;
      for(i = 0; i < datacount; ++i)
      {
        if(dataQueue[i].random_integer > data_max)
          data_max = dataQueue[i].random_integer;
        data_sum += dataQueue[i].random_integer;
      }
      assistant_info.id = NODE_TWO;
      assistant_info.value = data_max;
    }

    assistant_info.sum = data_sum;
    assistant_info.num = datacount;
    //send the info to commander node
    if (!radioFull)
    {
      message_t *pkt = &radioQueueBufs[radioIn];
      nodeassist_t* nrmpkt = (nodeassist_t*)(call RadioPacket.getPayload(pkt, sizeof(nodeassist_t)));
      nrmpkt->id = assistant_info.id;
      nrmpkt->value = assistant_info.value;
      nrmpkt->sum = assistant_info.sum;
      call RadioPacket.setPayloadLength(pkt, sizeof(nodeassist_t));
      call RadioAMPacket.setDestination(pkt, NODE_COMMANDER);
      call RadioAMPacket.setType(pkt, AM_NODEINFOMSG);
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
  }

  void result_cal(void* payload)
  {
    nodeassist_t* assistnode_info = (nodeassist_t*)payload;
    uint16_t assist_id = assistnode_info->id;
    if(assist_id == NODE_ONE && !rec_one_flag)
    {
      rec_one_flag = TRUE;
      res.min = assistnode_info->value;
      res.sum += assistnode_info->sum;
    }
    if(assist_id == NODE_TWO && !rec_two_flag)
    {
      rec_two_flag = TRUE;
      res.max = assistnode_info->value;
      res.sum += assistnode_info->sum;
    }
    if(rec_one_flag && rec_two_flag)
    {
      uint16_t i;
      for(i = 0; i < datacount; i++)
      {
        res.sum += dataQueue[i].random_integer;
      }
      res.average = res.sum/MAX_DATA_SIZE;// average < 0 ?
      // cal median
      // res.median = 0;
      if (!radioFull)
      {
        message_t *pkt = &radioQueueBufs[radioIn];
        result_t* nrmpkt = (result_t*)(call RadioPacket.getPayload(pkt, sizeof(result_t)));
        nrmpkt->group_id = res.group_id;
        nrmpkt->min = res.min;
        nrmpkt->max = res.max;
        nrmpkt->sum = res.sum;
        nrmpkt->average = res.average;
        nrmpkt->median = res.median;
        call RadioPacket.setPayloadLength(pkt, sizeof(result_t));
        call RadioAMPacket.setDestination(pkt, 0);    // send to Node 0
        call RadioAMPacket.setType(pkt, AM_NODERESULT);
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
    }
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
    len = call RadioPacket.payloadLength(msg);
    addr = call RadioAMPacket.destination(msg);
    id = call RadioAMPacket.type(msg);

    call RadioPacket.clear(msg);

    if (call RadioSend.send[id](addr, msg, len) == SUCCESS){}
      //call Leds.led0Toggle();
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
