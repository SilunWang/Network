
configuration NodeDDPApp {
}
implementation {
  components MainC, NodeDDPC, LedsC;
  components ActiveMessageC as Radio, SerialActiveMessageC as Serial;
  components new TimerMilliC() as Timer0;
  components new TimerMilliC() as Timer1;
  components new TimerMilliC() as Timer2;
  
  MainC.Boot <- NodeDDPC;

  NodeDDPC.RadioControl -> Radio;
  
  NodeDDPC.RadioSend -> Radio;
  NodeDDPC.RadioReceive -> Radio.Receive;
  NodeDDPC.RadioPacket -> Radio;
  NodeDDPC.RadioAMPacket -> Radio;

  NodeDDPC.Timer0 -> Timer0;
  NodeDDPC.Timer1 -> Timer1;
  NodeDDPC.Timer2 -> Timer2;
  
  NodeDDPC.Leds -> LedsC;
}
