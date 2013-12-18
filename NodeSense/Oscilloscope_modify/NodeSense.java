/**
 * Java-side application for testing serial port communication.
 * 
 *
 * @author SilunWang
 * @date 2013-12-18
 */

import java.io.IOException;

import net.tinyos.message.*;
import net.tinyos.packet.*;
import net.tinyos.util.*;

public class NodeSense implements MessageListener {

  private MoteIF moteIF;
  
  public NodeSense(MoteIF moteIF) {
    this.moteIF = moteIF;
    this.moteIF.registerListener(new NodeSenseMsg(), this);
  }

  public void messageReceived(int to, Message message) {
    NodeSenseMsg msg = (NodeSenseMsg)message;
    System.out.print("ID: " + msg.get_id());
    System.out.print(" No." + msg.get_count());
    System.out.print(" temperature: " + msg.get_temperature()[0]);
    System.out.print(" humidity: " + msg.get_humidity()[0]);
    System.out.print(" illumination: " + msg.get_illumination()[0]);
    System.out.println(" time: " + msg.get_curtime()[0]);
  }
  
  private static void usage() {
    System.err.println("usage: TestSerial [-comm <source>]");
  }
  
  public static void main(String[] args) throws Exception {
    String source = null;
    if (args.length == 2) {
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
    NodeSense serial = new NodeSense(mif);
  }

}
