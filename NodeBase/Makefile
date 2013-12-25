COMPONENT=BaseStationC
BUILD_EXTRA_DEPS += SenseInterval.class
CLEAN_EXTRA = *.class SenseInterval.java

CFLAGS += -DCC2420_NO_ACKNOWLEDGEMENTS
CFLAGS += -DCC2420_DEF_CHANNEL=19
CFLAGS += -DTOSH_DATA_LENGTH=64
CFLAGS += -I$(TOSDIR)/lib/T2Hack

SenseInterval.class: $(wildcard *.java) SenseIntervalMsg.java
	javac -target 1.4 -source 1.4 *.java

SenseIntervalMsg.java:
	mig java -target=null $(CFLAGS) -java-classname=SenseIntervalMsg NodeSense.h senseintervalmsg -o $@

include $(MAKERULES)

