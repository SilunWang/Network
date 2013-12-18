/*
 * Copyright (c) 2006 Intelpp Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

/**
 * NodeSense demo application. Uses the demo sensor - change the
 * new DemoSensorC() instantiation if you want something else.
 *
 * See README.txt file in this directory for usage instructions.
 *
 * @author David Gay
 */
configuration NodeSenseAppC { }
implementation
{
  components NodeSenseC, MainC, ActiveMessageC, LedsC,
    new TimerMilliC(), 
    new AMSenderC(AM_NODESENSEMSG), new AMReceiverC(AM_NODESENSEMSG),
    new SensirionSht11C(), new HamamatsuS1087ParC();   

  NodeSenseC.Boot -> MainC;
  NodeSenseC.RadioControl -> ActiveMessageC;
  NodeSenseC.AMSend -> AMSenderC;
  NodeSenseC.Receive -> AMReceiverC;
  NodeSenseC.Timer -> TimerMilliC;
  NodeSenseC.Leds -> LedsC;
  NodeSenseC.readTemp -> SensirionSht11C.Temperature;
  NodeSenseC.readHumidity -> SensirionSht11C.Humidity;
  NodeSenseC.readLight -> HamamatsuS1087ParC; 

}
