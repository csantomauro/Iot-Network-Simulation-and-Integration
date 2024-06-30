
/*
*	IMPORTANT:
*	The code will be avaluated based on:
*		Code design  
*
*/
 
#include "Timer.h"
#include "RadioRoute.h"
#include "time.h"
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <stdlib.h>

module RadioRouteC @safe() {
  uses {
  
    /****** INTERFACES *****/
	interface Boot;
	interface Timer<TMilli> as Timer0;
	interface Timer<TMilli> as Timer1;
	interface Timer<TMilli> as Timer2;
	interface Timer<TMilli> as Timer3;
	interface Timer<TMilli> as Timer4;
	interface Timer<TMilli> as Timer5;
	interface Timer<TMilli> as Timer6;
	interface AMSend;
	interface Receive;
	interface SplitControl as AMControl;
	interface Packet;

    //interfaces for communication
	//interface for timers
	//interface for LED
    //other interfaces, if needed
  }
}
implementation {

  message_t packet;
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  uint16_t time_delays[NUM_NODES]={0,61,173,267,371,479,583,689,792,897}; //Time delay in milli seconds
  char topics[4][15]={"NOT SUBSCRIBED","TEMPERATURE","HUMIDITY","LUMINOSITY"};
  panc_table_t panc_table;
  node_table_t node_table[NUM_NODES];
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  bool locked=FALSE;
  bool conn_done=FALSE;
  bool sub_done=FALSE;
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  int sendToPort(int nport,char* payload);
  
//=============================================================================================================
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  /*
  * 
  * Function to be used when performing the s
  end after the receive message event.
  * It store the packet and address into a global variable and start the timer execution to schedule the send.
  * It allow the sending of only one message for each REQ and REP type
  * @Input:
  *		address: packet destination address
  *		packet: full packet to be sent (Not only Payload)
  *		type: payload message type
  *
  * MANDATORY: DO NOT MODIFY THIS FUNCTION
  */
  	if (call Timer0.isRunning()){
  		return FALSE;
  	}else{
  	if (type == 1 && !route_req_sent ){
  		route_req_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 2 && !route_rep_sent){
  	  	route_rep_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 0){
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;	
  	}
  	}
  	return TRUE;
  }
//=============================================================================================================
  event void Timer0.fired() {
  	/*
  	* Timer triggered to perform the send.
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	actual_send (queue_addr, &queued_packet);
  }
//=============================================================================================================
  bool actual_send (uint16_t address, message_t* packet){
	/*
	* Implement here the logic to perform the actual send of the packet using the tinyOS interfaces
	*/
	 if (locked) {
     	 return;
    }
    else {
    	mqtt_light_msg_t* rsm;
        rsm = (mqtt_light_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_light_msg_t));
     	if(rsm==NULL){
     		return;
     	}
      	//send a direct packet to "address" node and lock on success
      	
		if (call AMSend.send(address, packet, sizeof(mqtt_light_msg_t)) == SUCCESS) {
			dbg("timer", "Actual packet sent!\n");
			locked = TRUE;
		}
	  
  	}
 }
//=============================================================================================================
  event void Boot.booted() {
  int i=0;
    dbg("boot","Application booted.\n");
    /* Fill it ... */
    call AMControl.start();

  }
//=============================================================================================================
  event void AMControl.startDone(error_t err) {
	/* Fill it ... */
	if(err == SUCCESS){
		call Timer1.startOneShot(DELAY);
  	} else{
    	call AMControl.start();
  	}
}
//=============================================================================================================
  event void AMControl.stopDone(error_t err) {
    /* Fill it ... */
  }
//=============================================================================================================
  event void Timer1.fired() {


      mqtt_light_msg_t* rsm;

      rsm = (mqtt_light_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_light_msg_t));
      
      if ( TOS_NODE_ID != 1 ) {
      	//all motes send a CONN message to the PAN coordinator
      	rsm->type=0;
      	rsm->destination=1;
      	rsm->sender=TOS_NODE_ID;

	  	if(call AMSend.send(rsm->destination, &packet, sizeof(mqtt_light_msg_t))==SUCCESS){
	  		call Timer2.startOneShot(time_delays[TOS_NODE_ID]);
			dbg("timer", "MQTT CONN: packet sent!\n");
	
      }
    }
  }
  //=============================================================================================================
  event void Timer2.fired() {
	/*
	*  Nodes send again CONN if lost
	*/
	   if ( TOS_NODE_ID != 1 && node_table[TOS_NODE_ID].flag_conn==0 && node_table[TOS_NODE_ID].count_retry_conn<MAX_RETRY) {

      	dbg("timer", "MQTT CONN: packet sent again!\n");
      	node_table[TOS_NODE_ID].count_retry_conn++;
      	dbg("timer", "Updating CONN retry count: %d\n",node_table[TOS_NODE_ID].count_retry_conn);
		call Timer1.startOneShot(500);
      } 

  }
    //=============================================================================================================
  event void Timer3.fired() {
	/*
	* PAN sends again CONACK if lost
	*/
		mqtt_light_msg_t* rsm;
		
    	if ( TOS_NODE_ID == 1) {
    		int sender=panc_table.sender_conack;
			if(panc_table.flag_connections[sender]==0 && panc_table.count_retry_conack[sender]<MAX_RETRY){
			
      			dbg("timer", "MQTT CONNACK: ack lost!\n");
      			panc_table.count_retry_conack[sender]++;
      			dbg("timer", "Updating CONNACK retry count: %d!\n",panc_table.count_retry_conack[sender]);
      			rsm = (mqtt_light_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_light_msg_t));
  		  		rsm->type=1;
      			rsm->destination=sender;
      			rsm->sender=1;
				if(call AMSend.send(sender, &packet, sizeof(mqtt_light_msg_t))==SUCCESS){
				
					dbg("timer", "MQTT CONNACK: packet sent again!\n");
					call Timer3.startOneShot(time_delays[sender]);
	   			 }
    		}
      } 
  }
      //=============================================================================================================
  event void Timer4.fired() {
	/*
	*  Nodes send SUB again if necessary
	*/
	mqtt_light_msg_t* rsm;
	
	int topic_choice=2;

	   if ( TOS_NODE_ID != 1 && node_table[TOS_NODE_ID].flag_sub==0 &&node_table[TOS_NODE_ID].count_retry_sub<MAX_RETRY&& !sub_done) {
	   		node_table[TOS_NODE_ID].count_retry_sub++;
	   		
	   		rsm = (mqtt_light_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_light_msg_t));
  		  	rsm->type=4;
      		rsm->destination=1;
      		rsm->sender=TOS_NODE_ID;
  			if(TOS_NODE_ID%2==0){
  				topic_choice=1;
  			}
  			rsm->topic=topic_choice;
  			
	   		if(call AMSend.send(1, &packet, sizeof(mqtt_light_msg_t))==SUCCESS){			

      				dbg("timer", "MQTT SUB: packet sent again!\n");
      				call Timer4.startOneShot(time_delays[TOS_NODE_ID]);
	   		}
      } 

    	
  }
//=============================================================================================================	
  event void Timer5.fired() {
  	/*
	*  PANc sends SUBACK again if necessary
	*/
  	mqtt_light_msg_t* rsm;

    	if ( TOS_NODE_ID == 1) {
    		int sender=panc_table.sender_suback;
			if(panc_table.topic_subscriptions[sender]==0 && panc_table.count_retry_suback[sender]<MAX_RETRY){

      			dbg("timer", "MQTT SUBACK: ack lost!\n");
      			panc_table.count_retry_suback[sender]++;
      			dbg("timer", "Updating SUBACK retry count: %d!\n",panc_table.count_retry_suback[sender]);
      		
      			rsm = (mqtt_light_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_light_msg_t));
  		  		rsm->type=5;
      			rsm->destination=sender;
      			rsm->sender=1;
				if(call AMSend.send(sender, &packet, sizeof(mqtt_light_msg_t))==SUCCESS){
	  				
					dbg("timer", "MQTT SUBACK: packet sent again!\n");
					call Timer5.startOneShot(time_delays[sender]);
	   			 }
    		}
      } 
  }
//=============================================================================================================	
  event void Timer6.fired() {
  	/*
	*  Nodes send Pub message when PSTART is received
	*/
     mqtt_light_msg_t* rsm;
  		int topic_choice=1;
  		dbg("timer", "PSTART received!\n");
  				
  		rsm = (mqtt_light_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_light_msg_t));	
  		rsm->type=8;
      	rsm->destination=1;
      	rsm->sender=TOS_NODE_ID;
  		if(TOS_NODE_ID%2==0){
  			topic_choice=2;
  		}
  		rsm->topic=topic_choice;
  		rsm->payload=rand()%100;
  		if (call AMSend.send(rsm->destination, &packet, sizeof(mqtt_light_msg_t)) == SUCCESS) {
  			dbg("radio_rec", "Sending MQTT PUB!, payload %d DEST %d type %d \n",rsm->payload,rsm->destination,rsm->type);		
				
		}
  }

//=============================================================================================================	
	bool connections_established(){
		/*
	*  Check if all connections are established
	*/
	int i;
		for(i=2;i<NUM_NODES;i++){
			if(panc_table.flag_connections[i]==0)
				return FALSE;
		}
		return TRUE;
	}
//=============================================================================================================	
	bool subscriptions_established(){
		/*
	*  Check if at least 6 nodes are subscribed 
	*/
	int i;int nsubs=0;
		for(i=2;i<NUM_NODES;i++){
			if(panc_table.topic_subscriptions[i]!=0)
				nsubs++;
		}
	if(nsubs>=6)	
		return TRUE;
	return FALSE;
	}
	
//=============================================================================================================	
	int sendToPort(int nport,char* payload){
		/*
	*  Establish connection to tcp server on Node Red and send the data
	*/
		int socket_desc;
    	struct sockaddr_in server_addr;
    	char server_message[2000];
    
     	// Clean buffers:
    	memset(server_message,'\0',sizeof(server_message));
	
		// Create socket:
    	socket_desc = socket(AF_INET, SOCK_STREAM, 0);
    
    	if(socket_desc < 0){
       	 	dbg("radio_rec","Unable to create socket\n");
        	return -1;
    	}
	 	dbg("radio_rec","Socket created successfully\n");
    
    	// Set port and IP the same as server-side:
    	server_addr.sin_family = AF_INET;
    	server_addr.sin_port = htons(nport);
    	server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    
   	 	// Send connection request to server:
    	if(connect(socket_desc, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0){
        	dbg("radio_rec","Unable to connect\n");
        	return -1;
    	}
    
    	dbg("radio_rec","Connected with server successfully\n");
    
    
    	// Send the message to server:
    	if(send(socket_desc, (payload) , strlen(payload), 0) < 0){
        	dbg("radio_rec","Unable to send message\n");
        	return -1;
    	}
    
    	return 0;
	}	
//=============================================================================================================	
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
			       
	/*
	* Parse the receive packet.
	*/
	mqtt_light_msg_t* rsm;
	int i;
	if (len == sizeof(mqtt_light_msg_t)) {
		//handle the payload
		rsm= (mqtt_light_msg_t*)payload;
  			
  		
  		//handle CONN
  		if(rsm->type==0 && !conn_done && !sub_done){

  			rsm->type=1;
      		rsm->destination=rsm->sender;
      		rsm->sender=1;
  				
  			dbg("radio_rec", "Replying with CONACK!, DEST %d type %d \n",rsm->destination,rsm->type);
  			if (call AMSend.send(rsm->destination, bufPtr, sizeof(mqtt_light_msg_t)) == SUCCESS) {
  				panc_table.sender_conack=rsm->destination;
				call Timer3.startOneShot(time_delays[rsm->destination]);
			
			}

  		}
  		//handle CONACK
  		else if(rsm->type==1 && !conn_done && !sub_done){
  			node_table[TOS_NODE_ID].flag_conn=1;
  			dbg("radio_rec", "I received the CONACK\n");	
  			
  			rsm->type=2;
      		rsm->destination=rsm->sender;
      		rsm->sender=TOS_NODE_ID;
  			if (call AMSend.send(rsm->destination, bufPtr, sizeof(mqtt_light_msg_t)) == SUCCESS) {
				dbg("timer", "CACK sent!\n");
				
			}
			
		//handle CACK
  		}else if(rsm->type==2 && TOS_NODE_ID==1 && !conn_done && !sub_done){
  			panc_table.flag_connections[rsm->sender]=1;

  			dbg("radio_rec", "Connection enstablished with %d\n",rsm->sender);	
  			for(i=2;i<NUM_NODES;i++)
  				dbg("radio_rec", "C: %d\n",panc_table.flag_connections[i]);	
  		
  			if(connections_established()){
  				//start subscription round	
  				conn_done=TRUE;
  				rsm->type=3;
      			rsm->sender=1;
  				
  				if (call AMSend.send(AM_BROADCAST_ADDR, bufPtr, sizeof(mqtt_light_msg_t)) == SUCCESS) {
					dbg("timer", "SSTART sent!\n");
				}
			
  				
  			}
  			
  		}
  		//handle SSTART
  		else if(rsm->type==3 && !sub_done){
  			int topic_choice=2;
  		  	rsm->type=4;
      		rsm->destination=1;
      		rsm->sender=TOS_NODE_ID;
  			if(TOS_NODE_ID%2==0){
  				topic_choice=1;
  			}
  			rsm->topic=topic_choice;
  			if (call AMSend.send(rsm->destination, bufPtr, sizeof(mqtt_light_msg_t)) == SUCCESS) {
  				dbg("radio_rec", "Sending MQTT SUB!, DEST %d type %d \n",rsm->destination,rsm->type);
				call Timer4.startOneShot(time_delays[rsm->destination]);
				
				
			}
  		}
  		//handle SUB
  		else if(rsm->type==4 && !sub_done){
  			rsm->type=5;
      		rsm->destination=rsm->sender;
      		rsm->sender=1;
  				
  			dbg("radio_rec", "Replying with SUBACK!, DEST %d type %d \n",rsm->destination,rsm->type);
  			if (call AMSend.send(rsm->destination, bufPtr, sizeof(mqtt_light_msg_t)) == SUCCESS) {
  				panc_table.sender_suback=rsm->destination;
			 	call Timer5.startOneShot(time_delays[rsm->destination]);
			}
			
  		//handle SUBACK
  		}else if(rsm->type==5 && !sub_done){
  			node_table[TOS_NODE_ID].flag_sub=1;
  			
  			rsm->type=6;
      		rsm->destination=1;
      		rsm->sender=TOS_NODE_ID;
      		
      		if (call AMSend.send(rsm->destination, bufPtr, sizeof(mqtt_light_msg_t)) == SUCCESS) {
  				dbg("radio_rec", "Sending MQTT SACK!, DEST %d type %d \n",rsm->destination,rsm->type);
								
			}
      		
  		}
  		//handle SACK
  		else if(rsm->type==6 && !sub_done){
  			panc_table.topic_subscriptions[rsm->sender]=rsm->topic;
  			dbg("radio_rec", "SACK received!, DEST %d type %d \n",rsm->destination,rsm->type);
  			dbg("radio_rec", "Node %d subscribed to %s! \n",rsm->sender,topics[rsm->topic]);
  			
  			for(i=2;i<NUM_NODES;i++)
  				dbg("radio_rec", "S: %s\n",topics[panc_table.topic_subscriptions[i]]);	
  				
  			if(subscriptions_established()){
  				sub_done=TRUE;
  				rsm->type=7;
      			rsm->sender=1;
  				
  				if (call AMSend.send(AM_BROADCAST_ADDR, bufPtr, sizeof(mqtt_light_msg_t)) == SUCCESS) {
					dbg("timer", "PSTART sent!\n");
				
				}
  			}
  		
  		//handle PSTART	
  		}else if(rsm->type==7){
  			call Timer6.startOneShot(time_delays[TOS_NODE_ID]);
  		
  		//handle PUB	
  		}else if(rsm->type==8){
  			if(TOS_NODE_ID==1){
  				int i;
  				int topic_choice=1;
  				char p[30];
  				
  				
  				dbg("timer", "MQTT PUB received!\n");
  				sprintf(p, "%s %d",topics[rsm->topic], rsm->payload);
  				dbg("radio_rec", "Result send: %d\n", sendToPort(60001,p));
  				for(i=2;i<NUM_NODES;i++){
  					if(panc_table.topic_subscriptions[i]==rsm->topic){
  						rsm->type=8;
  						rsm->destination=i;
  						rsm->sender=1;
  						generate_send (rsm->destination, bufPtr, sizeof(mqtt_light_msg_t));
						dbg("radio_rec", "Forwarding MQTT PUB to %d type %d payload %d! \n",rsm->destination,rsm->type,rsm->payload);			
  					}
  				}
  			}
  		}		
    }	
    return bufPtr;
  }
	//=============================================================================================================
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/* This event is triggered when a message is sent 
	*  Check if the packet is sent 
	*/ 
	if (&packet == bufPtr) {
		locked = FALSE;
	}
  }
}



