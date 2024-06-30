

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H
#define NUM_NODES 10 //we consider nodes from 1 to 9 included
#define DELAY 5000
#define MAX_RETRY 3

typedef nx_struct mqtt_light_msg {
   nx_uint8_t type;  //CONN 0 CONNACK 1 CACK 2 SSTART 3 SUB 4 SUBACK 5 SACK 6 PSTART 7 PUB 8 
   nx_uint8_t topic; 	// NOT SUB 0 TEMP 1 HUMI 2 LUMIN 3
   nx_uint32_t sender;  //	1-9
   nx_uint32_t destination;		//	1-9
   nx_uint8_t payload;	//random number
   
} mqtt_light_msg_t;

typedef nx_struct panc_table {
      nx_uint8_t flag_connections[NUM_NODES];	//connection 0: not connected - 1: connected
      nx_uint8_t topic_subscriptions[NUM_NODES]; // NOT SUB 0 TEMP 1 HUMI 2 LUMIN 3
      nx_uint8_t count_retry_conack[NUM_NODES];	//num_retransmission of CONACK
      nx_uint8_t count_retry_suback[NUM_NODES];	//num_retransmission of SUBACK
      nx_uint8_t sender_conack;
      nx_uint8_t sender_suback;

} panc_table_t;

typedef nx_struct node_table {
      nx_uint8_t flag_sub;	//      1: SUB received - 0: SUB not received
      nx_uint8_t flag_conn;	// 		1: CONN received - 0: CONN not received
      nx_uint8_t count_retry_conn;	//num_retransmission of CONN
      nx_uint8_t count_retry_sub;	//num_retransmission of SUBS

} node_table_t;

enum {
  AM_RADIO_COUNT_MSG = 10,

};

#endif
