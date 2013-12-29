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
import java.io.File;
import java.io.FileOutputStream;
import java.io.*;

public class NodeSense implements MessageListener {

  private MoteIF moteIF;
  private int count1 = 0;
  private int count2 = 0;
  private FileOutputStream fout;
  
  public NodeSense(MoteIF moteIF) {
    this.moteIF = moteIF;
    this.moteIF.registerListener(new NodeSenseMsg(), this);
    try {
      this.fout = new FileOutputStream("result.txt", true);
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }

  public void messageReceived(int to, Message message) {
    if(count1 >= 1200 && count2 >= 1200)
    {
      try {
        fout.close();
      }
      catch (Exception e) {
        e.printStackTrace();
      }
      return;
    }

    NodeSenseMsg msg = (NodeSenseMsg)message;

    System.out.println("Got it!");
    if(msg.get_id() == 1)
      count1++;
    else if(msg.get_id() == 2)
      count2++;
    else
      return;

    String resultStr = "";
    resultStr += msg.get_id() + " ";
    resultStr += msg.get_SeqNo() + " ";
    resultStr += msg.get_temperature()[0] + " ";
    resultStr += msg.get_humidity()[0] + " ";
    resultStr += msg.get_illumination()[0] + " ";
    resultStr += msg.get_curtime()[0] + "\n";

    try {
		  byte[] bytes = resultStr.getBytes();
		  fout.write(bytes);
	  }
	  catch (Exception e) {
		  e.printStackTrace();
	  }
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
