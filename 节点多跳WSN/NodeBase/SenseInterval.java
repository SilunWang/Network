/**
 * Java-side application for SenseInterval port communication.
 * 
 * @author SilunWang
 * @date 2013-12-18
 */

import java.io.IOException;

import net.tinyos.message.*;
import net.tinyos.packet.*;
import net.tinyos.util.*;

public class SenseInterval implements MessageListener {

  private MoteIF moteIF;
  
  public SenseInterval(MoteIF moteIF) {
    this.moteIF = moteIF;
    this.moteIF.registerListener(new SenseIntervalMsg(), this);
  }

  public void setInterval(int interval) {

    SenseIntervalMsg payload = new SenseIntervalMsg();
    
    try {
      payload.set_interval(interval);
      moteIF.send(MoteIF.TOS_BCAST_ADDR, payload);
    }
    catch (IOException exception) {
      System.err.println("Exception thrown when sending packets. Exiting.");
      System.err.println(exception);
    }
  }

  public void messageReceived(int to, Message message) {
    
  }
  
  private static void usage() {
    System.err.println("usage: SenseInterval [-comm <source>]");
  }
  
  public static void main(String[] args) throws Exception {
    String source = null;
    if (args.length == 3) {
      if (!args[0].equals("-comm")) {
	      usage();
	      System.exit(1);
      }
      source = args[1];
    }
    else if (args.length != 0) {
      usage();
      System.exit(1);
    }
    
    PhoenixSource phoenix;
    
    if (source == null) {
      phoenix = BuildSource.makePhoenix(PrintStreamMessenger.err);
    }
    else {
      phoenix = BuildSource.makePhoenix(source, PrintStreamMessenger.err);
    }

    MoteIF mif = new MoteIF(phoenix);
    SenseInterval serial = new SenseInterval(mif);
    serial.setInterval(Integer.parseInt(args[2]));
  }

}
