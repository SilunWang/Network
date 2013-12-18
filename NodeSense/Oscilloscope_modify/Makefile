COMPONENT=NodeSenseAppC
BUILD_EXTRA_DEPS += NodeSenseMsg.class

CFLAGS += -I$(TOSDIR)/lib/T2Hack
CFLAGS += -DCC2420_DEF_CHANNEL=19
CFLAGS += -DTOSH_DATA_LENGTH=64
CFLAGS += -DCC2420_DEF_RFPOWER=10

NodeSenseMsg.class: NodeSenseMsg.java
	javac -target 1.4 -source 1.4 *.java
NodeSenseMsg.java:
	mig java -target=null $(CFLAGS) -java-classname=NodeSenseMsg NodeSense.h nodesensemsg -o $@


include $(MAKERULES)
