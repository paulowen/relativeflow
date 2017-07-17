---
date: 2017-07-17T18:43:42+10:00
tags: ["cisco", "bgp"]
title: "BGP Peering IP Address Validation"
aliases: [
	"/2017/07/17/bgp-peering-ip-address-validation/",
	"/post/bgp-peering-ip-address-validation/"
]
---

# Overview

BGP peering occurs upon TCP as the transport protocol, which implies that for a successful stateful connection to happen, one of the peering routers is the client, and the other peering router is the server. 

One of the peering validation steps of the BGP server, irrespective as to whether the peering is of type internal or external, is to check that the client's IP address as the source of the SYN packet is valid or approved for peering. This check is performed against configuration within the local BGP process on the server.

Configured neighbor statements within a BGP process triggers two actions:

- The router becomes a BGP server, opening a local socket listening on port 179 for a TCP handshake to be initiated by other clients.
- The router will, eventually (after a DelayOpenTime period has elapsed), become a BGP client and actively initiate a TCP handshake toward port 179 of the server.

# Topology

Consider this simple topology. Both routers are Cisco CSR1000v virtual appliances running IOS-XE.

![Logical Topology](/images/bgp-peering-ip-address-validation-logical.png)

# Validation

The focus of this validation example surrounds R1. A basic IGP (OSPF) deployment is in place for reachability between loopback interfaces. R1 has placeholder configuration for an iBGP peering with R2 as follows.

```
R1# show run | section router bgp
router bgp 65000
 bgp log-neighbor-changes
 neighbor 10.2.2.2 remote-as 65000
 neighbor 10.2.2.2 update-source Loopback0
```

R2 has reciprocal BGP configuration. Given this, we would expect to see the TCP three-way handshake to occur and achieve a stateful TCP connection between the peers, as shown in the following debug snippet (trimmed for relevance and brevity).

```
R1#debug ip packet detail
IP: s=10.2.2.2 (GigabitEthernet1.12), d=10.1.1.1, len 44, enqueue feature
    TCP src=24849, dst=179, seq=1880337189, ack=0, win=16384 SYN, TCP Adjust MSS(5), rtype 0, forus FALSE, sendself FALSE, mtu 0, fwdchk FALSE
IP: s=10.1.1.1 (local), d=10.2.2.2 (GigabitEthernet1.12), len 44, sending
    TCP src=179, dst=24849, seq=700618100, ack=1880337190, win=16384 ACK SYN
IP: s=10.2.2.2 (GigabitEthernet1.12), d=10.1.1.1, len 40, enqueue feature
    TCP src=24849, dst=179, seq=1880337190, ack=700618101, win=16384 ACK, TCP Adjust MSS(5), rtype 0, forus FALSE, sendself FALSE, mtu 0, fwdchk FALSE
R1#
```

Subsequently...

```
R1#
%BGP-5-ADJCHANGE: neighbor 10.2.2.2 Up
R1#
```

The more observant can see it was R2 that was the client that triggered the TCP connection toward the server R1. In this case, R2 was pre-configured before the debug was enabled and the configuration applied to R1. R1, when configured, started its DelayOpenTime timer to wait for a temporary period as a server only to listen for connectivity from its client peers. R2 actively negotiated the TCP connectivity within that period as its DelayOpenTime timer had expired prior.

Should there be a collision with two clients simultaneously attempting to create the TCP connection, the peer with the lower router ID withdraws and takes the passive server role, while the peer with the higher router ID continues as the active client.

So R1's peering with R2 is now up, but under what condition was this allowed? Let's take a look at the TCP sockets of R1.

```
R1#show tcp brief all
TCB       Local Address               Foreign Address             (state)
7FE47500DA50  10.1.1.1.179               10.2.2.2.24849              ESTAB
7FE474FC5E20  0.0.0.0.179                10.2.2.2.*                  LISTEN
R1#
```

The first entry is the operational BGP peering between R1 and R2.

The LISTEN entry is of interest. It shows that although R1 is listening on any of its local logical interfaces, it allows client TCP connection on port 179 for only the explicitly configured neighbour IP address for R2 under the local BGP process. We would expect that only a TCP SYN received from R2 with a source IP address of 10.2.2.2 is accepted.

To prove this, let's change the source IP address of R2's peering by altering the update-source of the peering toward R1 to R2's directly connected interface address.

> QUESTION: Considering what we have covered earlier in this post, will the BGP peering toward R1 still come up?

```
R2#
R2#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
R2(config)#router bgp 65000
R2(config-router)#no  neighbor 10.1.1.1 update-source Loopback0
R2(config-router)#end
R2#
%SYS-5-CONFIG_I: Configured from console by console
R2#clear ip bgp *
R2#
IP: tableid=0, s=10.12.1.2 (local), d=10.1.1.1 (GigabitEthernet1.12), routed via FIB
IP: s=10.12.1.2 (local), d=10.1.1.1 (GigabitEthernet1.12), len 44, sending
    TCP src=33019, dst=179, seq=3809966816, ack=0, win=16384 SYN
BGP: 10.1.1.1 open failed: Connection refused by remote host
BGP: 10.1.1.1 Active open failed - tcb is not available, open active delayed 13312ms (35000ms max, 60% jitter)
BGP: ses global 10.1.1.1 (0x7F063B80FC20:0) act Reset (Active open failed).
BGP: 10.1.1.1 active went from Active to Idle
```

The output shows R1 refused the TCP connection, and the BGP state reverted to Idle. This response confirms the expectation from the TCP socket state of R1 considered earlier.

To see R1's exact behaviour in this scenario, the debug snippet below shows an ACK RST packet sent in response to R2's SYN packet, actively refusing the connection and informing the client of the refused attempt.

```
R1#
IP: tableid=0, s=10.1.1.1 (local), d=10.12.1.2 (GigabitEthernet1.12), routed via FIB
IP: s=10.1.1.1 (local), d=10.12.1.2 (GigabitEthernet1.12), len 40, sending
    TCP src=179, dst=33019, seq=0, ack=3809966817, win=0 ACK RST
R1#
```

> ANSWER: Yes, the BGP peering between R1 and R2 still forms. We altered the source IP address used for peering on R2, which was not approved as per the neighbour statement for R2 in R1's local configuration, but R2 still approved R1's peering address as nothing changed on R1. The result of our configuration change meant that in this specific peering arrangement R1 is always the client, and R2 the server.

So, let's prove the other half of the TCP session table that R1 as a server accepts a connection on any local interface.

Two configuration items comprise this test of R2's peering toward R1:

1. Update R2's update-source to be its Loopback0 interface again, which matches the expectation of R1 implied in its configuration, and a valid peering is accepted irrespective of the role each router takes.
2. Change R2's BGP neighbour configuration towards R1 to use the address of R1 on the directly connected segment, 10.12.1.1.

Now to see if this is enough for an operational peering.

```
R2#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
R2(config)#router bgp 65000
R2(config-router)#no neighbor 10.1.1.1
%BGP-3-NOTIFICATION: sent to neighbor 10.1.1.1 6/3 (Peer De-configured) 0 bytes 
%BGP_SESSION-5-ADJCHANGE: neighbor 10.1.1.1 IPv4 Unicast topology base removed from session  Neighbor deleted
%BGP-5-ADJCHANGE: neighbor 10.1.1.1 Down Neighbor deleted
R2(config-router)#neighbor 10.12.1.1 remote-as 65000
R2(config-router)#neighbor 10.12.1.1 update-source Loopback0
R2(config-router)#end
R2#
%SYS-5-CONFIG_I: Configured from console by console
R2#
%BGP-5-NBR_RESET: Neighbor 10.12.1.1 active reset (Peer closed the session)
%BGP_SESSION-5-ADJCHANGE: neighbor 10.12.1.1 IPv4 Unicast topology base removed from session  Peer closed the session
R2#
%BGP-5-NBR_RESET: Neighbor 10.12.1.1 active reset (Peer closed the session)
%BGP_SESSION-5-ADJCHANGE: neighbor 10.12.1.1 IPv4 Unicast topology base removed from session  Peer closed the session
R2#
```

It is not. Before needing to initiate any debugging for diagnosis on R2, BGP logging shows R1 again is actively refusing the connection.

Debugging R1 to get an idea of the problem, the problem is quickly defined.

```
BGP: 10.2.2.2 active went from Idle to Active
BGP: 10.2.2.2 open active, local address 10.1.1.1
BGP: 10.2.2.2 open failed: Connection refused by remote host
BGP: 10.2.2.2 Active open failed - tcb is not available, open active delayed 9216ms (35000ms max, 60% jitter)
BGP: ses global 10.2.2.2 (0x7FE9E56BC6E0:0) act Reset (Active open failed).
BGP: 10.2.2.2 active went from Active to Idle
BGP: nbr global 10.2.2.2 Active open failed - open timer running
BGP: nbr global 10.2.2.2 Active open failed - open timer running
BGP: 10.2.2.2 passive open to 10.12.1.1
BGP: Fetched peer 10.2.2.2 from tcb
BGP: 10.2.2.2 passive open failed - 10.12.1.1 is not update-source Loopback0's address (10.1.1.1)
BGP: 10.2.2.2 remote connection attempt failed(due to session creation failure, local address 10.12.1.1
R1#
```

R1 is refusing the connection again, as the destination IP address of the TCP SYN packet does match the locally configured update-source interface for the peering toward R2. Here we have encountered onto an additional piece of peer address validation.

By removing the update-source on R1 for the peering to R2, the peering should come up.

```
R1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
R1(config)#router bgp 65000
R1(config-router)#no  neighbor 10.2.2.2 update-source Loopback0
R1(config-router)#end
R1#
%SYS-5-CONFIG_I: Configured from console by console
R1#
%BGP-5-ADJCHANGE: neighbor 10.2.2.2 Up
R1#
```

# Findings

Through this verification and troubleshooting process, we found that the BGP peering address validation enforces the following.

- A BGP server only accepts client TCP SYN packets from the source IP address defined in the neighbour statement. The address becomes the Foreign Address entry in a listening TCP socket.
- If a TCP SYN is received from an unconfigured source IP address, the listening TCP socket does not match, and the router refuses the connection returning a TCP RST packet.
- If the server specifies an update-source for a specific neighbour, the destination IP address configured on the client must also match the logical address assigned to the update-source interface.
- If the server does not specify an update-source for a specific neighbour, the destination IP address configured on the client can match any logical address on the server.

Although it is nice to understand this detail, we also found that BGP peering can still form if not all conditions satisfy. There can only be one server and one client in each peering, and even if all configuration is correct for any combination of roles, collision control ensures this should simultaneous BGP connection attempts between routers occur. The default configuration does not define if a router is a server or client, it is a dynamic process, and the roles are interchangeable. If an incorrect configuration does not allow a particular router to be a server, it may be successful in being a client.
