/*
####################### 
This is a sketch requires a Arduino (or clone) with a ethernet shield.

The code cycles every quater of a second:
* Polls the temperature sensor
* Coverts raw input into real temperature
* Compares the 2 temperatures based on the configuration set below
* Turns the fan on/off based on the rules/configuration
* Checks for incoming ethernet connection and provides a webpage with the current temperature and fan status

Beta Features:
*

Untested Features:
* Auto 5 second refresh on the main page
* DHCP
* Better request handling (c as a string)
* Initial steps towards different pages

####################### 
 */

//This sets the temperature point the system will aim to reach at all times (Degrees C)
float TargetFloorTemp = 19;

//The minimum amount of time the fan will run before rechecking the temperature
//Setting this too low (below 10mins) will result in the fan oscilating between on and off rapidly
//Set under 1 min for testing purposes
int MinimumFanRuntime = 0.5;

//This sets the minimum between the ceiling and floor temperature before the system starts the fan
//Setting this too high will mean the system will not be very responsive
//Setting this too low the system will overshot and over heat/cool the floor due to the MinimumFanRuntime
float MinimumDifference = 3;

//Set the input pins for the LM35 Thermometers
//Remember A0 and A1 are used by the Ethernet shield
int ceilingpin = A2;
int floorpin = A3;

//Set the output pin (for the relay to control the fans)
int outputpin = 7;

//Do not edit anything below this line
//Includes
#include <SPI.h>
#include <Ethernet.h>
#include <EthernetDHCP.h>

//Temperature vars
float CeilingSensor;
float Ceilingtemperature;

float FloorSensor;
float Floortemperature;

// Run time vars
int runtimecount = 0;
float comparisonvar;
int Fanstatus = 0;

// Enter a MAC address and IP address for your controller below.
// The IP address will be dependent on your local network:
byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
const byte* ipAddr;
const byte* gatewayAddr;
const byte* dnsAddr;
String  readString = String(45);
String  addressString = String(20);

// Initialize the Ethernet server library
// with the IP address and port you want to use 
// (port 80 is default for HTTP):
Server server(80);

void setup()
{
  // start the Ethernet connection and the server:
  EthernetDHCP.begin(mac);
  ipAddr = EthernetDHCP.ipAddress();
  gatewayAddr = EthernetDHCP.gatewayIpAddress();
  dnsAddr = EthernetDHCP.dnsIpAddress();
  
  Serial.println("A DHCP lease has been obtained.");
  Serial.print("My IP address is ");
  Serial.println(ip_to_str(ipAddr));  
  Serial.print("Gateway IP address is ");
  Serial.println(ip_to_str(gatewayAddr)); 
  Serial.print("DNS IP address is ");
  Serial.println(ip_to_str(dnsAddr));
  
  //Server begin
  server.begin();
  
  //Serial for debugging
  Serial.begin(9600);
}

void loop()
{
// ########### Ethernet section ########### // 

  // listen for incoming clients
  Client client = server.available();
  if (client) 
  {
    // an http request ends with a blank line
    boolean currentLineIsBlank = true;
    while (client.connected()) 
    {
      if (client.available()) 
      {
        char c = client.read();
        readString.concat(c);
        // if you've gotten to the end of the line (received a newline
        // character) and the line is blank, the http request has ended,
        // so you can send a reply
        if (c == '\n' && currentLineIsBlank) 
        {
          /*
          int Firstslash = readString.indexOf("/", 8); //This should find the position of the first slash
          addressString.substring(Firstslash); //finds the exact address
          int statuspagerequest = readString.indexOf("status"); 
          if (statuspagerequest >= 0) 
          {
            Send the status page
          }
          //else if other page addresses
          //else 404 page not found.
          */
          
          // send a standard http response header
          client.println("HTTP/1.1 200 OK");
          client.println("Content-Type: text/html");
          client.println();

          // output the value of each analog input pin
         
          client.println("<HEAD>");
          client.println("<meta http-equiv='refresh' content='5;'/>");
          client.println("</HEAD>");
          
          client.println("<BODY>");
          client.print("The air temperature at the floor is: ");
          client.print(Floortemperature);
          client.print(" Degrees C");
          client.println("<br />");
          
          client.print("The air temperature at the ceiling is: ");
          client.print(Ceilingtemperature);
          client.print(" Degrees C");
          client.println("<br />");
          
          if (Fanstatus == 1)
          {
            client.print("Temperature differance is great enough. The De-stratifiers are on");
            client.println("<br />");
          }
          else
          {
            client.print("Temperature differance isn't great enough. The De-stratifiers are off");
	    client.println("<br />");
          }
          
          client.println("</BODY>");
          
          break;
        }
        // you're starting a new line
        if (c == '\n') currentLineIsBlank = true;
        
        // you've gotten a character on the current line
        else if (c != '\r') currentLineIsBlank = false;
      }
    }
    // give the web browser time to receive the data
    delay(1);
    // close the connection:
    client.stop();
  }

// ########### Temperature section ########### // 

  // Convert the raw 0-0123 analog input into the temperature
  // ((X*5000)/1024)/10 
  // Which is simplified into one line (X*0.48828125)
  CeilingSensor = analogRead(ceilingpin); 
  Ceilingtemperature = CeilingSensor*0.48828125; 
  
  FloorSensor = analogRead(floorpin);
  Floortemperature = FloorSensor*0.48828125;
  
  //floor is cold, is the ceiling air hot enough?
  if (Floortemperature < TargetFloorTemp)
  {
    //[Ceilingtemperature] must be [MinimumDifference] greater than [Floortemperature]
    comparisonvar = Ceilingtemperature + MinimumDifference;

    if (comparisonvar >= Floortemperature) Fanstatus = 1;
    else Fanstatus = 0;
  }
  //floor is hot, is the ceiling air cold enough?
  else if (Floortemperature > TargetFloorTemp)
  {
    //[Ceilingtemperature] must be [MinimumDifference] less than [Floortemperature]
    comparisonvar = Ceilingtemperature - MinimumDifference;
    
    if (comparisonvar <= Floortemperature) Fanstatus = 1;
    else Fanstatus = 0;
  }
  
  //If the it has been decided the fans should be on then enter
  if (Fanstatus ==1)
  {
    //This attempts to de-bounce the starting of the fans
    //This ensures that the fans run for [MinimumFanRuntime]
    if (runtimecount == 0)
    {
      //Where we actually turn the fans on
      digitalWrite(outputpin, HIGH);
      //The system cycles in 0.25 of a second, so there are 240 cycles in a minute
      runtimecount = (MinimumFanRuntime*240);
    }
    //reducing the run time counter 
    else if(runtimecount > 0)
    {
      runtimecount = runtimecount - 1;
    }
  }
  //if the fans should be off, turn them off
  else digitalWrite(outputpin, LOW);
  
  delay(250); 
}

// Just a utility function to nicely format an IP address.
const char* ip_to_str(const uint8_t* ipAddr)
{
  static char buf[16];
  sprintf(buf, "%d.%d.%d.%d\0", ipAddr[0], ipAddr[1], ipAddr[2], ipAddr[3]);
  return buf;
}
