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

    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as Timer1;
    interface Timer<TMilli> as Timer2;

    interface Leds;
  }
}

implementation
{
  enum {
    RADIO_QUEUE_LEN = 30,
    DROP_QUEUE_LEN = 600,
    DATA_BUF_LEN = 100,
    DATA_QUEUE_LEN = 1000,
  };

  message_t  radioQueueBufs[RADIO_QUEUE_LEN];
  message_t  * ONE_NOK radioQueue[RADIO_QUEUE_LEN];
  uint8_t    radioIn, radioOut;
  bool       radioBusy, radioFull;

  uint16_t        seqQueue;
  uint16_t        tempseq;
  uint16_t         dropflag;
  uint16_t         dropstart;
  uint16_t        dropcount;
  uint16_t        dropQueue[DROP_QUEUE_LEN];
  uint16_t        dropQueue2[DROP_QUEUE_LEN];

  uint16_t        datacount;
  nodedata_t      databuf[DATA_BUF_LEN];
  uint32_t        dataQueue[DATA_QUEUE_LEN];

  bool gb_receive_over;

  /**** only for commander ****/
  result_t res;
  bool rec_one_flag;
  bool rec_two_flag;
  bool num_one_flag;
  bool num_two_flag;
  bool rec_commander_flag;
  uint16_t gb_node_count;
  uint16_t gb_nodeOne_count;
  uint16_t gb_nodeTwo_count;
  int32_t gb_sum_tmp ;
  /**** end ****/

  task void radioSendTask();
  uint32_t getMin(uint32_t arr[], uint16_t length);
  uint32_t getMax(uint32_t arr[], uint16_t length);
  uint32_t getSum(uint32_t arr[], uint16_t length);
  uint32_t randomized_select(uint32_t arr[], uint16_t low, uint16_t high, uint16_t i);
  uint16_t partition(uint32_t arr[], uint16_t low, uint16_t high);
  void QuickSort(uint32_t arr[], uint16_t l, uint16_t r);

  uint32_t getMin(uint32_t arr[], uint16_t length)
  {
    int32_t min = (int32_t)arr[0];
    uint16_t i;
    for(i = 0; i < length; i++){
      if((int32_t)arr[i] < min)
        min = (int32_t)arr[i];
    }
    return (uint32_t)min;
  }

  uint32_t getMax(uint32_t arr[], uint16_t length)
  {
    int32_t max = (int32_t)arr[0];
    uint16_t i;
    for(i = 0; i < length; i++){
      if((int32_t)arr[i] > max)
        max = (int32_t)arr[i];
    }
    return (uint32_t)max;
  }

  uint32_t getSum(uint32_t arr[], uint16_t length)
  {
    int32_t sum = 0;
    uint16_t i;
    for(i = 0; i < length; i++)
    {
      sum += (int32_t)arr[i];
    }
    return (uint32_t)sum;
  }


  uint32_t randomized_select(uint32_t arr[], uint16_t low, uint16_t high, uint16_t i)
  {
    uint16_t pivot;
    uint16_t k;
    call Leds.led1Toggle();
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

  void insertSort(uint32_t arr[], int length){
    uint16_t i, j; 
    int32_t tmp;
    for(i=1; i < length; i++)
    {
      tmp = (int32_t)arr[i];
      for(j=i-1; j >= 0; j--)
      {
        if (tmp<(int32_t)arr[j])
          arr[j+1]=arr[j];
        else
        {
          j--;
          break;
        }
      }
      arr[j+1] = (uint32_t)tmp;
    }
}

  uint16_t partition(uint32_t arr[], uint16_t low, uint16_t high)
  {
    int32_t tmp;
    tmp = (int32_t)arr[low];
    while(low < high){
      while(low < high && (int32_t)arr[high] >= tmp)
        high--;
      arr[low] = arr[high];
      while(low < high && (int32_t)arr[low] <= tmp)
        low++;
      arr[high] = arr[low];
    }
    arr[low] = (uint32_t)tmp;
    return low;
  }

  void QuickSort(uint32_t arr[], uint16_t l, uint16_t r)
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
    datacount = 0;
    tempseq = 2001;
    seqQueue = 0;
    gb_receive_over = FALSE;

    if(TOS_NODE_ID == NODE_COMMANDER)
    {
      res.group_id = GROUP_ID;
      res.sum = 0;
      res.average = 0; 
      rec_one_flag = FALSE;
      rec_two_flag = FALSE;   
      num_one_flag = FALSE;
      num_two_flag = FALSE;
      rec_commander_flag = FALSE;
      gb_nodeOne_count = 0;
      gb_nodeTwo_count = 0;
      gb_node_count = 0;
      gb_sum_tmp = 0;
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
  void simple_resend(uint16_t sequence_number);
  void assistance_cal();
  void result_cal(void* payload);
  void send_pktnum();
  void send_numack(uint16_t id); // commander has received the num from id
  void request_pktnum();
  void check_recnum(void* payload);
  void check_totalnum();
  void stop_send_res();
  void sendpacket(uint16_t dp)
  {
        if (!radioFull)
        {\
          message_t *pkt = &radioQueueBufs[radioIn];
          noderesend_t* nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
          nrmpkt->id = dp;
          nrmpkt->sequence_number = dp;
          call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
          call RadioAMPacket.setDestination(pkt, 0);
          call RadioAMPacket.setType(pkt, 15);
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
    {
      nodedata_t * nsmpkt = (nodedata_t*)payload;
      if(gb_receive_over) // all packets has been received
        return msg;
      else if (seqQueue < nsmpkt->sequence_number && nsmpkt->sequence_number - seqQueue > 100)
        return msg;
      receive_data(msg,payload);
    }
    else if (type == AM_NODERESENDMSG)    // receive resend request and resend
      receive_resendmsg(payload);
    else if (type == AM_NODECOMMANDERMSG)  
    {
      if(TOS_NODE_ID == NODE_COMMANDER)
        check_recnum(payload);           // check the packet number from node 1,2
    }      
    else if (type == AM_NODEINFOMSG)   
    {
      if(TOS_NODE_ID == NODE_ONE || TOS_NODE_ID == NODE_TWO)
        assistance_cal();                  // calculate and send the res to commander
      if(TOS_NODE_ID == NODE_COMMANDER)
      {
        result_cal(payload);               // calculate result and send to Node 0
      }
    }
    else if (type == AM_NODENUM_RECMSG)    // stop sending num to commander
    {
      call Timer0.stop();     
    }           
    else if (type == AM_NODEACKMSG)        // stop sending packet to Node 0 (stop timmer)
      stop_send_res();

    if (!gb_receive_over && (seqQueue == MAX_DATA_SIZE || tempseq <= MAX_DATA_SIZE) && dropcount == 0)
    {
      gb_receive_over = TRUE;
      if(TOS_NODE_ID == NODE_COMMANDER)
        check_totalnum();
      if(TOS_NODE_ID == NODE_ONE || TOS_NODE_ID == NODE_TWO)
        call Timer0.startPeriodic( TIME_INTERVAL ); // send its num to commander

      call Leds.led2Toggle(); //receive total 2000 data
    }
    return msg;
  }

  event void Timer0.fired()
  {
    send_pktnum();                     // send until the commander receive
  }

  event void Timer1.fired()
  {
    message_t *pkt;
    noderesend_t* nrmpkt;
    if (!radioFull)
    {
      pkt = &radioQueueBufs[radioIn];
      nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
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
    } 
    if (!radioFull)
    {
      pkt = &radioQueueBufs[radioIn];
      nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
      nrmpkt->id = NODE_COMMANDER;
      nrmpkt->sequence_number = 0;
      call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
      // send to Node one
      call RadioAMPacket.setDestination(pkt, NODE_TWO);    
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

  event void Timer2.fired()
  {
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

  void receive_data(message_t *msg, void *payload) {
    nodedata_t* nsmpkt = (nodedata_t*)payload;
    if (tempseq > MAX_DATA_SIZE)
    {
      if (nsmpkt->sequence_number == MAX_DATA_SIZE) {
        dropBlink();
        tempseq = 0;
      }
      else if (seqQueue > nsmpkt->sequence_number && seqQueue - nsmpkt->sequence_number > MAX_DATA_SIZE / 2) {
        uint16_t i;
        tempseq = 0;
        for (i = seqQueue + 1; i <= MAX_DATA_SIZE; i++)
        {
          dropcount++;
          //sendpacket(dropcount);
          if (dropQueue[i % DROP_QUEUE_LEN] == 0)
            dropQueue[i % DROP_QUEUE_LEN] = i;
          else
          {
            dropQueue2[dropflag] = i;
            dropflag++;
          }
          simple_resend(i);
        }
      }
      if (nsmpkt->sequence_number < seqQueue) {
        bool flag = FALSE;
        uint16_t i;
        atomic {
          if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == 0)
            return;
          else if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == nsmpkt->sequence_number)
          {
            dropcount--;
            //sendpacket(dropcount);
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
                //sendpacket(dropcount);
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
        seqQueue = nsmpkt->sequence_number;
        databuf[nsmpkt->sequence_number % DATA_BUF_LEN].sequence_number = nsmpkt->sequence_number;
        databuf[nsmpkt->sequence_number % DATA_BUF_LEN].random_integer = nsmpkt->random_integer;
        resend(nsmpkt, sequence_number);
      }
      if (TOS_NODE_ID == NODE_ONE && (int32_t)(nsmpkt->random_integer) < 3500)
      {
        dataQueue[datacount] = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_TWO && (int32_t)(nsmpkt->random_integer) > 6500)
      {
        dataQueue[datacount] = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_COMMANDER && (int32_t)(nsmpkt->random_integer)>= 3500 && (int32_t)(nsmpkt->random_integer) <= 6500)
      {
        call Leds.led1Toggle();
        dataQueue[datacount] = nsmpkt->random_integer;
        datacount++;
      }
    }
    else 
    {
      if (tempseq == MAX_DATA_SIZE) {
        dropBlink();
        tempseq = 0;
      }  
      else if (tempseq > nsmpkt->sequence_number && tempseq - nsmpkt->sequence_number > MAX_DATA_SIZE / 2) {
        uint16_t i;
        for (i = tempseq + 1; i <= MAX_DATA_SIZE; i++)
        {
          simple_resend(i);
        }
        tempseq = 0;
      }
      if (nsmpkt->sequence_number < tempseq || nsmpkt->sequence_number - tempseq > MAX_DATA_SIZE / 2) {
        bool flag = FALSE;
        uint16_t i;
        atomic {
          if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == 0)
            return;
          else if (dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] == nsmpkt->sequence_number)
          {
            dropcount--;
            //sendpacket(dropcount);
            dropQueue[nsmpkt->sequence_number % DROP_QUEUE_LEN] = 0;
            while(dropQueue2[dropstart] == 0 && dropstart < dropflag)
              dropstart++;
            for (i = dropstart; i < dropflag; i++)
            {
              if (dropQueue2[i] != 0 && dropQueue2[i] % DROP_QUEUE_LEN == nsmpkt->sequence_number % DROP_QUEUE_LEN)
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
              if (dropQueue2[i] == nsmpkt->sequence_number)
              {
                dropcount--;
                //sendpacket(dropcount);
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
      else if (tempseq < nsmpkt->sequence_number) {
        bool flag = FALSE;
        uint16_t i, j;
        if (nsmpkt->sequence_number - tempseq > 10)
        {
          tempseq = nsmpkt->sequence_number;
          return;
        }
        databuf[nsmpkt->sequence_number % DATA_BUF_LEN].sequence_number = nsmpkt->sequence_number;
        databuf[nsmpkt->sequence_number % DATA_BUF_LEN].random_integer = nsmpkt->random_integer;
        for (j = tempseq + 1; j <= nsmpkt->sequence_number; j++)
        {          
          if (dropQueue[j % DROP_QUEUE_LEN] == 0)
            continue;
          else if (dropQueue[j % DROP_QUEUE_LEN] == j)
          {
            if (j == nsmpkt->sequence_number)
            {
              dropcount--;
              //sendpacket(dropcount);
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
              simple_resend(j);
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
                  dropcount--;
                  //sendpacket(dropcount);
                  dropQueue2[i] = 0;
                  flag = TRUE;
                }  
                else
                {
                  simple_resend(j);
                }
                break;
              } 
            }
          }          
        }
        tempseq = nsmpkt->sequence_number;
        if (!flag)
          return;
      }
      if (TOS_NODE_ID == NODE_ONE && (int32_t)(nsmpkt->random_integer) < 3500)
      {
        dataQueue[datacount] = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_TWO && (int32_t)(nsmpkt->random_integer) > 6500)
      {
        dataQueue[datacount] = nsmpkt->random_integer;
        datacount++;
      }
      else if (TOS_NODE_ID == NODE_COMMANDER && (int32_t)(nsmpkt->random_integer)>= 3500 && (int32_t)(nsmpkt->random_integer) <= 6500)
      {
        call Leds.led1Toggle();
        dataQueue[datacount] = nsmpkt->random_integer;
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
        //sendpacket(dropcount);
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

  void simple_resend(uint16_t sequence_number) {
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
          call RadioPacket.setPayloadLength(pkt, sizeof(nodedata_t));
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
    message_t *pkt;
    noderesend_t* nrmpkt;
    if (!radioFull)
    {
      pkt = &radioQueueBufs[radioIn];
      nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
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
    }    
    if (!radioFull)
    {
      pkt = &radioQueueBufs[radioIn];
      nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
      nrmpkt->id = TOS_NODE_ID;
      nrmpkt->sequence_number = 0;
      call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
      // send to Node two
      call RadioAMPacket.setDestination(pkt, NODE_TWO);    
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

  void send_numack(uint16_t id)
  {
    call Leds.led1Toggle();
    if (!radioFull)
    {
      message_t *pkt;
      noderesend_t* nrmpkt;
      pkt = &radioQueueBufs[radioIn];
      nrmpkt = (noderesend_t*)(call RadioPacket.getPayload(pkt, sizeof(noderesend_t)));
      nrmpkt->id = NODE_COMMANDER;
      nrmpkt->sequence_number = 0;
      call RadioPacket.setPayloadLength(pkt, sizeof(noderesend_t));
      // send to id
      call RadioAMPacket.setDestination(pkt, id);    
      call RadioAMPacket.setType(pkt, AM_NODENUM_RECMSG);
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

  void check_totalnum()
  {
    if(num_one_flag && num_two_flag) // if 1 and 2 are both received
    {
      gb_node_count += datacount;
      sendpacket(datacount);
      if(gb_node_count == MAX_DATA_SIZE)
      {
        // finish data receiving, require node's data
        report_problem();
        call Timer1.startPeriodic(TIME_INTERVAL);
      }
      else
      {
        gb_node_count -= datacount;
      }
    }
  }

  void check_recnum(void* payload)
  {
    noderesend_t* assist_num = (noderesend_t*)payload;
    //call Leds.led1Toggle();
    if(assist_num->id==NODE_ONE)
    {
      if(!num_one_flag)
      {
        num_one_flag = TRUE;
        gb_nodeOne_count = assist_num->sequence_number;// sequence_number here represents num
        gb_node_count += gb_nodeOne_count;
      }
      send_numack(NODE_ONE);
    }
    if(assist_num->id==NODE_TWO)
    {
      if(!num_two_flag)
      {
        num_two_flag = TRUE;
        gb_nodeTwo_count = assist_num->sequence_number;
        gb_node_count += assist_num->sequence_number;
      }
      send_numack(NODE_TWO);
    }
    check_totalnum();
  }

  void stop_send_res()
  {
    // stop timmer
    //call Timer2.stop();
  }

  void assistance_cal()
  {
    uint16_t i;
    int32_t data_sum = 0;
    int32_t data_tmp = 0;
    nodeassist_t assistant_info;

    if(TOS_NODE_ID == NODE_ONE)
    {
      //calculate min data
      /*
      int32_t data_min = 10002;
      for(i = 0; i < datacount; ++i)
      {
        data_tmp = (int32_t)dataQueue[i];
        if( data_tmp < data_min)
          data_min = data_tmp;
        data_sum += data_tmp;
      }*/
      assistant_info.id = NODE_ONE;
      //assistant_info.value = (uint32_t)data_min;
      assistant_info.value = getMin(dataQueue, datacount);
    }
    else if(TOS_NODE_ID == NODE_TWO)
    {
      //calculate max data
      /*
      int32_t data_max = -10002;
      for(i = 0; i < datacount; ++i)
      {
        data_tmp = (int32_t)dataQueue[i];
        if(data_tmp > data_max)
          data_max = data_tmp;
        data_sum += data_tmp;
      }*/
      assistant_info.id = NODE_TWO;
      //assistant_info.value = (uint32_t)data_max;
      assistant_info.value = getMax(dataQueue, datacount);
    }

    assistant_info.sum = getSum(dataQueue, datacount);
    assistant_info.num = datacount;
    //send the info to commander node
    if (!radioFull)
    {
      message_t *pkt = &radioQueueBufs[radioIn];
      nodeassist_t* nrmpkt = (nodeassist_t*)(call RadioPacket.getPayload(pkt, sizeof(nodeassist_t)));
      nrmpkt->id = assistant_info.id;
      nrmpkt->value = assistant_info.value;
      nrmpkt->sum = assistant_info.sum;
      nrmpkt->num = assistant_info.num;
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
    int32_t ave_tmp = 0;
    if(assist_id == NODE_ONE && !rec_one_flag)
    {
      rec_one_flag = TRUE;
      res.min = assistnode_info->value;
      gb_sum_tmp += assistnode_info->sum;
    }
    if(assist_id == NODE_TWO && !rec_two_flag)
    {
      rec_two_flag = TRUE;
      res.max = assistnode_info->value;
      gb_sum_tmp += assistnode_info->sum;
    }
    if(rec_one_flag && rec_two_flag && !rec_commander_flag)
    {
      uint16_t i;
      int32_t sum_tmp = gb_sum_tmp;
      rec_commander_flag = TRUE;
      call Timer1.stop();                // stop sending calculating request
      
      for(i = 0; i < datacount; i++)
      {
        sum_tmp += (int32_t)dataQueue[i];
      }
      ave_tmp = sum_tmp/MAX_DATA_SIZE;// average < 0 ?
      res.sum = (uint32_t)sum_tmp;
      res.average = (uint32_t)(sum_tmp/MAX_DATA_SIZE);
      // cal median
      //res.median = randomized_select(dataQueue, 0, datacount-1, MAX_DATA_SIZE/2-gb_nodeOne_count-1);
      insertSort(dataQueue, datacount);
      //res.median = dataQueue[MAX_DATA_SIZE - gb_nodeTwo_count + 2];
      res.median = dataQueue[1000 - gb_nodeOne_count -1];
      call Timer2.startPeriodic( TIME_INTERVAL ); 
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
