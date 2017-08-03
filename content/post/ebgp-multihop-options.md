---
title: "eBGP Multihop Options"
date: 2017-08-03T21:33:38+10:00
tags: ["cisco", "bgp"]
aliases: ["/2017/07/27/ebgp-multihop-options/",
          "/post/ebgp-multihop-options/"]
---

By default, external BGP (eBGP) peering requires both routers to be directly attached to a common layer 3 segment. Why?

- eBGP is intended for deployment between autonomous systems, that is, for the ability to exchange routing prefixes and policy between two separate networks under different administrative and governing authorities.
- For a successful eBGP multihop between autonomous systems, both independent members would need to participate in a mutual routing domain providing reachability between end points, which blurs demarcation, political and administrative responsibilities, and introduces confusion on the role each party beholds.
- For simplicity and scalability reasons, direct connectivity avoids a requirement of liaising with another administrator for cooperation in building an intermediate routing domain. It also quells the necessity to advertise BGP learned prefixes into an IGP or intermediate routing domain for participating routers to forward toward a destination.

That aside, there are use cases where eBGP peering is required between two routers that are not directly connected. For example...

- Two autonomous systems that wish to peer with each other are separated by a service provider or another routed autonomous system.
- The directly connected router is incapable of BGP routing, but is a viable next hop toward a capable router.

Cisco provides an engineer with three controls within the BGP routing process to enable eBGP multihop.

1. Neighbour eBGP Multihop - `neighbor <IP> ebgp-multihop [TTL]`
2. Neighbour Disable Connected Check - `neighbor <IP> disable-connected-check`
3. Neighbour TTL Security - `neighbor <IP> ttl-security hops [MAX_HOPS]`

Which technique to use depends on requirements, as always. This article takes a look at what each command does and attempts to indicate some use cases on when each option is valid.

# Topology

The scenarios in this post build on the logical topology below.

![Logical Topology](/images/ebgp-multihop-options-logical.png)

Each router is a Cisco CSR1000v operating IOS-XE.

# Scenario 1: eBGP Multihop

The `neighbor <IP> ebgp-multihop [TTL]` option is likely the simplest and most common technique you have probably seen implemented before. However, what does it do?

Before checking the impact of this option, I configured an eBGP peering between R1 and R2 using the directly connected segment. The configuration from R1 and R2 is below.

<table>
<tr><th>R1</th><th>R2</th></tr>
<tr>
<td>
<pre><code class="language-c">router bgp 65001
 bgp log-neighbor-changes
 neighbor 10.0.12.2 remote-as 65002
</code></pre>
</td>
<td>
<pre><code class="language-c">router bgp 65002
 bgp log-neighbor-changes
 neighbor 10.0.12.1 remote-as 65001
</code></pre>
</td>
</tr>
</table>

From this capture snippet, R1 is seen to send its TCP SYN packet toward R2 with a Time to Live (TTL) value of 1 in the encapsulating IP header.

<pre><code class="language-c">Frame 1372: 64 bytes on wire (512 bits), 64 bytes captured (512 bits) on interface 0
Ethernet II, Src: Vmware_a7:a2:2e (00:50:56:a7:a2:2e), Dst: Vmware_a7:e4:ed (00:50:56:a7:e4:ed)
802.1Q Virtual LAN, PRI: 0, DEI: 0, ID: 12
Internet Protocol Version 4, Src: 10.0.12.1, Dst: 10.0.12.2
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0xc0 (DSCP: CS6, ECN: Not-ECT)
    Total Length: 44
    Identification: 0x485c (18524)
    Flags: 0x02 (Don't Fragment)
    Fragment offset: 0
    <font color="red">Time to live: 1</font>
    Protocol: TCP (6)
    Header checksum: 0x04ae [validation disabled]
    [Header checksum status: Unverified]
    Source: 10.0.12.1
    Destination: 10.0.12.2
    [Source GeoIP: Unknown]
    [Destination GeoIP: Unknown]
Transmission Control Protocol, Src Port: 11522, Dst Port: 179, Seq: 0, Len: 0
VSS-Monitoring ethernet trailer, Source Port: 0
</code></pre>

This result immediately implies that in a multihop scenario, as soon as the packet requires routed off of the directly attached segment, the next hop router decrements the TTL in the IP header to zero, drops the packet, and sends a return ICMP time exceeded packet to the source. The eBGP peering will not succeed.

The `ebgp-multihop` neighbour option is used to overcome this scenario. In this example, we start by configuring an eBGP multihop peering between the loopback addresses of R1 and R3 from our logical topology.

<table>
<tr><th>R1</th><th>R3</th></tr>
<tr>
<td>
<pre><code class="language-c">router bgp 65001
 bgp log-neighbor-changes
 neighbor 10.3.3.3 remote-as 65003
 neighbor 10.3.3.3 update-source Loopback0
 neighbor 10.3.3.3 ebgp-multihop
</code></pre>
</td>
<td>
<pre><code class="language-c">router bgp 65003
 bgp log-neighbor-changes
 neighbor 10.1.1.1 remote-as 65001
 neighbor 10.1.1.1 update-source Loopback0
 neighbor 10.1.1.1 ebgp-multihop
</code></pre>
</td>
</tr>
</table>

The `ebgp-multihop` option takes an additional parameter, a specified `TTL` value. When applied without being specified, the default value applied to the IP header is 255 as verified in this packet capture of the TCP SYN sent by R1 to R3.

<pre><code class="language-c">Frame 8155: 64 bytes on wire (512 bits), 64 bytes captured (512 bits) on interface 0
Ethernet II, Src: Vmware_a7:a2:2e (00:50:56:a7:a2:2e), Dst: Vmware_a7:e4:ed (00:50:56:a7:e4:ed)
802.1Q Virtual LAN, PRI: 0, DEI: 0, ID: 12
Internet Protocol Version 4, Src: 10.1.1.1, Dst: 10.3.3.3
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0xc0 (DSCP: CS6, ECN: Not-ECT)
    Total Length: 44
    Identification: 0x4b39 (19257)
    Flags: 0x02 (Don't Fragment)
    Fragment offset: 0
    <font color="red">Time to live: 255</font>
    Protocol: TCP (6)
    Header checksum: 0x17cb [validation disabled]
    [Header checksum status: Unverified]
    Source: 10.1.1.1
    Destination: 10.3.3.3
    [Source GeoIP: Unknown]
    [Destination GeoIP: Unknown]
Transmission Control Protocol, Src Port: 50911, Dst Port: 179, Seq: 0, Len: 0
VSS-Monitoring ethernet trailer, Source Port: 0
</code></pre>

Because the configuration in this example is complete and correct, the eBGP peering forms successfully. By altering the `TTL` parameter of the `ebgp-multihop` neighbour option, we control the scope, or the length of the path (number of hops), that is acceptable between the peering routers.

First, we test the result of a TTL that is intentionally too short causing the eBGP peering not to succeed. The TTL is configured as 1, which is effectively the same result as not specifying the `ebgp-multihop` neighbor option (not technically correct, as the peering is allowed to initiate irrespective of the connected reachability check result). With a simple ICMP debug we should see an ICMP time exceeded packet returned from R2.

<pre><code class="language-c">R1#debug ip icmp 
ICMP packet debugging is on
R1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
R1(config)#router bgp 65001
R1(config-router)#neighbor 10.3.3.3 ebgp-multihop 1
R1(config-router)#do clear bgp ipv4 uni *
R1(config-router)#
%BGP-3-NOTIFICATION: sent to neighbor 10.3.3.3 6/4 (Administrative Reset) 0 bytes 
R1(config-router)#
%BGP-5-ADJCHANGE: neighbor 10.3.3.3 Down User reset
%BGP_SESSION-5-ADJCHANGE: neighbor 10.3.3.3 IPv4 Unicast topology base removed from session  User reset
R1(config-router)#
<font color="red">ICMP: time exceeded rcvd from 10.0.12.2</font>
</code></pre>

This problem resolution in this topology is to set the TTL parameter to 2 hops.

```
R1(config-router)#neighbor 10.3.3.3 ebgp-multihop 2
R1(config-router)#
%BGP-3-NOTIFICATION: received from neighbor 10.3.3.3 active 6/7 (Connection Collision Resolution) 0 bytes 
R1(config-router)#
%BGP-5-NBR_RESET: Neighbor 10.3.3.3 active reset (BGP Notification received)
%BGP-5-ADJCHANGE: neighbor 10.3.3.3 active Down BGP Notification received
%BGP_SESSION-5-ADJCHANGE: neighbor 10.3.3.3 IPv4 Unicast topology base removed from session  BGP Notification received
R1(config-router)#
%BGP-5-ADJCHANGE: neighbor 10.3.3.3 Up 
R1(config-router)#
```

A capture including the encapsulating IP header proves this on the wire.

<pre><code class="language-c">Frame 8658: 64 bytes on wire (512 bits), 64 bytes captured (512 bits) on interface 0
Ethernet II, Src: Vmware_a7:a2:2e (00:50:56:a7:a2:2e), Dst: Vmware_a7:e4:ed (00:50:56:a7:e4:ed)
802.1Q Virtual LAN, PRI: 0, DEI: 0, ID: 12
Internet Protocol Version 4, Src: 10.1.1.1, Dst: 10.3.3.3
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0xc0 (DSCP: CS6, ECN: Not-ECT)
    Total Length: 44
    Identification: 0x26ac (9900)
    Flags: 0x02 (Don't Fragment)
    Fragment offset: 0
    <font color="red">Time to live: 2</font>
    Protocol: TCP (6)
    Header checksum: 0x3959 [validation disabled]
    [Header checksum status: Unverified]
    Source: 10.1.1.1
    Destination: 10.3.3.3
    [Source GeoIP: Unknown]
    [Destination GeoIP: Unknown]
Transmission Control Protocol, Src Port: 53510, Dst Port: 179, Seq: 0, Len: 0
VSS-Monitoring ethernet trailer, Source Port: 0
</code></pre>

Verification within IOS-XE within the BGP neighbour state is below.

<pre><code class="language-c">R1#show bgp ipv4 uni neighbors 10.3.3.3
BGP neighbor is 10.3.3.3,  remote AS 65003, external link
  BGP version 4, remote router ID 10.3.3.3
  BGP state = Established, up for 01:25:03

  [output omitted]
  
  Address tracking is enabled, the RIB does have a route to 10.3.3.3
  Connections established 3; dropped 2
  Last reset 01:25:34, due to BGP Notification received, Connection Collision Resolution
  <font color="red">External BGP neighbor may be up to 2 hops away.</font>
  External BGP neighbor NOT configured for connected checks (<font color="red">multi-hop</font> no-disable-connected-check)
  Interface associated: (none) (peering address NOT in same link)
  Transport(tcp) path-mtu-discovery is enabled
</code></pre>

Also of interest from the eBGP neighbour output, the disable-connected-check is not enabled in parallel. Rather, a multi-hop flag is set to allow the BGP peering to initiate with an acceptance that the peering address has no association with a local interface or a mutually shared segment.

# Scenario 2: Disable Connected Check

To verify the differences in behaviour of the `disable-connected-check` neighbour option, we continue with the same topology and configuration left behind in Scenario 1.

In short, we keep the intention to eBGP multihop peer between R1 and R3 but attempt to do so by disabling `ebgp-multihop` and implementing `disable-connected-check` with the following changes.

<table>
<tr><th>R1</th></tr>
<tr>
<td>
<pre><code class="language-c">R1#configure terminal
Enter configuration commands, one per line.  End with CNTL/Z.
R1(config)#router bgp 65001
R1(config-router)#no neighbor 10.3.3.3 ebgp-multihop
R1(config-router)#neighbor 10.3.3.3 disable-connected-check
R1(config-router)#end
R1#
%SYS-5-CONFIG_I: Configured from console by console
R1#clear bgp ipv4 unicast neighbor 10.3.3.3
R1#
ICMP: time exceeded rcvd from 10.0.12.2
R1#
ICMP: time exceeded rcvd from 10.0.12.2
R1#
</code></pre>
</td>
</tr>
<tr><th>R3</th></tr>
<td>
<pre><code class="language-c">R3#configure terminal
Enter configuration commands, one per line.  End with CNTL/Z.
R3(config)#router bgp 65003
R3(config-router)#no neighbor 10.1.1.1 ebgp-multihop
R3(config-router)#neighbor 10.1.1.1 disable-connected-check
R3(config-router)#end
R3#
%SYS-5-CONFIG_I: Configured from console by console
R3#clear bgp ipv4 unicast neighbor 10.1.1.1
R3#
ICMP: time exceeded rcvd from 10.0.23.2
R3#
ICMP: time exceeded rcvd from 10.0.23.2
R3#
</code></pre>
</td>
</tr>
</table>

Right away we can see a problem. With the ICMP debug still enabled on routers R1 and R3 from Scenario 1, it highlights we are receiving a TTL expired ICMP packet returned from the intermediate router R2 in the forwarding path.

This result highlights a difference in behaviour: `disable-connected-check` does not function by adjusting the TTL of the IP packet header encapsulating the BGP TCP session. A capture proves this.

<pre><code class="language-c">Frame 1: 64 bytes on wire (512 bits), 64 bytes captured (512 bits) on interface 0
Ethernet II, Src: Vmware_a7:a2:2e (00:50:56:a7:a2:2e), Dst: Vmware_a7:e4:ed (00:50:56:a7:e4:ed)
802.1Q Virtual LAN, PRI: 0, DEI: 0, ID: 12
Internet Protocol Version 4, Src: 10.1.1.1, Dst: 10.3.3.3
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0xc0 (DSCP: CS6, ECN: Not-ECT)
    Total Length: 44
    Identification: 0xfc32 (64562)
    Flags: 0x02 (Don't Fragment)
    Fragment offset: 0
    <font color="red">Time to live: 1</font>
    Protocol: TCP (6)
    Header checksum: 0x64d2 [validation disabled]
    [Header checksum status: Unverified]
    Source: 10.1.1.1
    Destination: 10.3.3.3
    [Source GeoIP: Unknown]
    [Destination GeoIP: Unknown]
Transmission Control Protocol, Src Port: 31745, Dst Port: 179, Seq: 0, Len: 0
VSS-Monitoring ethernet trailer, Source Port: 0
</code></pre>

Let's see what the neighbour state output suggests has changed.

> Note that the peering does not form at this point. I simply wanted to see R1's perspective by simply configuring the option.

<pre><code class="language-c">R1#show bgp ipv4 uni neigh 10.3.3.3
BGP neighbor is 10.3.3.3,  remote AS 65003, external link
  BGP version 4, remote router ID 0.0.0.0
  BGP state = Active
  
  [output omitted]
  
  Address tracking is enabled, the RIB does have a route to 10.3.3.3
  Connections established 3; dropped 3
  Last reset 00:17:49, due to Active open failed
  External BGP neighbor not directly connected.
  External BGP neighbor NOT configured for connected checks (<font color="red">single-hop disable-connected-check</font>)
  Interface associated: (none) (peering address NOT in same link)
  Transport(tcp) path-mtu-discovery is enabled
  Graceful-Restart is disabled
  SSO is disabled
  No active TCP connection
R1#
</code></pre>

The output gives nothing away really, apart from the assertion that the `disable-connected-check` is applied, yet a single-hop peering expectation remains.

So, considering TTL adjustment is a fundamental requirement for multihop routing of packets, our experience here suggests that the two peering eBGP routers still need to be directly connected, but perhaps can peer with each other using respective Loopback interfaces rather than the directly connected link.

To test this, let's attempt a multihop eBGP peering using `disable-connected-check` between R1 and R2 as per this configuration.

<table>
<tr><th>R1</th></tr>
<tr>
<td>
<pre><code class="language-c">R1#configure terminal
Enter configuration commands, one per line.  End with CNTL/Z.
R1(config)#router bgp 65001
R1(config-router)#no neighbor 10.3.3.3
R1(config-router)#
%BGP-3-NOTIFICATION: sent to neighbor 10.3.3.3 active 6/3 (Peer De-configured) 0 bytes 
R1(config-router)#
%BGP-5-NBR_RESET: Neighbor 10.3.3.3 active reset (Neighbor deleted)
%BGP-5-ADJCHANGE: neighbor 10.3.3.3 active Down Neighbor deleted
R1(config-router)#
R1(config-router)#neighbor 10.2.2.2 remote-as 65002
R1(config-router)#neighbor 10.2.2.2 update-source Loopback0
R1(config-router)#neighbor 10.2.2.2 disable-connected-check 
R1(config-router)#end
R1#
%SYS-5-CONFIG_I: Configured from console by console
R1#
<font color="red">%BGP-5-ADJCHANGE: neighbor 10.2.2.2 Up</font>
R1#
</code></pre>
</td>
</tr>
<tr><th>R2</th></tr>
<tr>
<td>
<pre><code class="language-c">R2#configure terminal
Enter configuration commands, one per line.  End with CNTL/Z.
R2(config)#router bgp 65002
R2(config-router)#neighbor 10.1.1.1 remote-as 65001
R2(config-router)#neighbor 10.1.1.1 update-source Loopback0
R2(config-router)#neighbor 10.1.1.1 disable-connected-check 
R2(config-router)#end
R2#
%SYS-5-CONFIG_I: Configured from console by console
R2#
<font color="red">%BGP-5-ADJCHANGE: neighbor 10.1.1.1 Up</font>
R2#
</code></pre>
</td>
</tr>
</table>

Given the peering formed straight away, this proves the theory. The `disable-connected-check` option is providing a mechanism of using indirect logical interfaces on both routers, yet both routers must still be directly connected.

# Scenario 3: TTL Security

The `ttl-security hops [MAX_HOPS]` neighbour option does somewhat the opposite of the `ebgp-multihop` neighbour option. It validates the TTL value in the IP header field of packets received from the peering router.

Before digging too deep, we know with the other multihop options analysed prior that to achieve eBGP multihop the TTL of the outgoing packets must be greater than 1. Let's enable the option with the following configuration between R1 and R3, specifying the maximum 254 hops. As this is a correct deployment, peering forms between R1 and R3.

<table>
<tr><th>R1</th><th>R3</th></tr>
<tr>
<td>
<pre><code class="language-c">router bgp 65001
 bgp log-neighbor-changes
 neighbor 10.3.3.3 remote-as 65003
 neighbor 10.3.3.3 update-source Loopback0
 neighbor 10.3.3.3 ttl-security hops 254
</code></pre>
</td>
<td>
<pre><code class="language-c">router bgp 65003
 bgp log-neighbor-changes
 neighbor 10.1.1.1 remote-as 65001
 neighbor 10.1.1.1 update-source Loopback0
 neighbor 10.1.1.1 ttl-security hops 254
</code></pre>
</td>
</tr>
</table>

Let's see in a packet capture what the outgoing TTL value in the IP header is from R1 toward R3.

<pre><code class="language-c">Frame 69: 64 bytes on wire (512 bits), 64 bytes captured (512 bits) on interface 0
Ethernet II, Src: Vmware_a7:a2:2e (00:50:56:a7:a2:2e), Dst: Vmware_a7:e4:ed (00:50:56:a7:e4:ed)
802.1Q Virtual LAN, PRI: 0, DEI: 0, ID: 12
Internet Protocol Version 4, Src: 10.1.1.1, Dst: 10.3.3.3
    0100 .... = Version: 4
    .... 0101 = Header Length: 20 bytes (5)
    Differentiated Services Field: 0xc0 (DSCP: CS6, ECN: Not-ECT)
    Total Length: 44
    Identification: 0x862c (34348)
    Flags: 0x02 (Don't Fragment)
    Fragment offset: 0
    <font color="red">Time to live: 255</font>
    Protocol: TCP (6)
    Header checksum: 0xdcd7 [validation disabled]
    [Header checksum status: Unverified]
    Source: 10.1.1.1
    Destination: 10.3.3.3
    [Source GeoIP: Unknown]
    [Destination GeoIP: Unknown]
Transmission Control Protocol, Src Port: 21434, Dst Port: 179, Seq: 0, Len: 0
VSS-Monitoring ethernet trailer, Source Port: 0
</code></pre>

The capture suggests that by enabling TTL Security, the outbound TTL has a value of 255 by default. There is no mechanism to alter this with the neighbour option, which gives us a clue as to how this neighbour option is operating. If we default to an outbound TTL of 255, and we cannot alter it, checks on the TTL happen in the inbound direction on the peering router.

So what does R1 think about its peering with R3 then?

<pre><code class="language-c">R1#show bgp ipv4 unicast neighbors 10.3.3.3
BGP neighbor is 10.3.3.3,  remote AS 65003, external link
  BGP version 4, remote router ID 10.3.3.3
  BGP state = Established, up for 00:01:37
  
[output omitted]

  Address tracking is enabled, the RIB does have a route to 10.3.3.3
  Connections established 1; dropped 0
  Last reset never
  <font color="red">External BGP neighbor may be up to 254 hops away.</font>
  External BGP neighbor NOT configured for connected checks (<font color="red">multi-hop</font> no-disable-connected-check)
  Interface associated: (none) (peering address NOT in same link)
</code></pre>

R1 accepts a BGP peering with R3 up to 254 hops away, the value of 254 being that we specified for of the `[MAX_HOPS]` parameter. Thinking about what that means, R1 would appear to accept a packet for BGP peering from R3 as long as the TTL value in the IP header is greater than, or equal to, one.

Let's relate this to our `[MAX_HOPS]` value with an acceptable incoming TTL formula that makes sense, given that we also know that outgoing packets are sent with a TTL of 255 when using this option.

> Incoming TTL >= 255 - [MAX_HOPS]

As an example, if we configure R1's peering towards R3 with `neighbor 10.3.3.3 ttl-security hops 251`, R1 would allow R3 as an eBGP neighbour to be up to 251 hops away, so the incoming TTL must be >= 4. If an incoming TTL be <= 4, the peering can not form.

To prove this functionality, I am going to test ttl-security on R1, but use ebgp-multihop on R2 to control the outgoing TTL. Here is the scenario in config.

<table>
<tr><th>R1</th><th>R2</th></tr>
<tr>
<td>
<pre><code class="language-c">router bgp 65001
 bgp log-neighbor-changes
 neighbor 10.2.2.2 remote-as 65002
 neighbor 10.2.2.2 update-source Loopback0
 neighbor 10.2.2.2 ttl-security hops 5
</code></pre>
</td>
<td>
<pre><code class="language-c">router bgp 65002
 bgp log-neighbor-changes
 neighbor 10.1.1.1 remote-as 65001
 neighbor 10.1.1.1 update-source Loopback0
 neighbor 10.1.1.1 ebgp-multihop 250
</code></pre>
</td>
</tr>
</table>

In this case, R1 only allows the eBGP peering if it receives a packet from R2 with a TTL of at least 250. Because R1 needs to recurse a route lookup towards its loopback, it must decrement the TTL to 249, which does not satisfy the ttl-security criteria. The peering can not form.

This scenario was tricky to debug and prove in a post, as R1 sent no response back to R3. There are no time-expired ICMP packets returned because the TTL has not decremented to zero. R3 experienced TCP SYN timeouts and attempted retransmissions, in vain, to keep trying to build a peering with R1 as shown below.

```
R2#debug ip tcp transactions 
TCP special event debugging is on
R2#
TCB7F62DC35C5E8 created
TCB7F62DC35C5E8 setting property TCP_VRFTABLEID (20) 7F62DC30AA30
TCB7F62DC35C5E8 setting property TCP_MD5KEY (4) 0
TCB7F62DC35C5E8 setting property TCP_ACK_RATE (37) 7F62DCB9ED80
TCB7F62DC35C5E8 setting property TCP_TOS (11) 7F62DCB9ED88
TCB7F62DC35C5E8 setting property TCP_PMTU (45) 7F62DCB9ED20
TCB7F62DC35C5E8 setting property TCP_IN_TTL (34) 7F62DCB9ED20
TCB7F62DC35C5E8 setting property TCP_OUT_TTL (35) 7F62DCB9ED20
TCB7F62DC35C5E8 setting property TCP_OUT_TTL (35) 7F6
R2#2DC30AD52
TCB7F62DC35C5E8 setting property TCP_RTRANSTMO (36) 7F62DCB9ED7C
 tcp_uniqueport: using ephemeral max 55000 
TCP: Random local port generated 39351, network 1
TCB7F62DC35C5E8 bound to 10.2.2.2.39351
Reserved port 39351 in Transport Port Agent for TCP IP type 1
TCP: pmtu enabled,mss is now set to 1460
TCP: sending SYN, seq 3208046828, ack 0
TCP0: Connection to 10.1.1.1:179, advertising MSS 1460
TCP0: state was CLOSED -> SYNSENT [39351 -> 10.1.1.1(179)]
TCP0: bad seg from 10.1.1.1 -- bad 
R2#sequence number: port 179 seq 1285741231 ack 0 rcvnxt 1285741232 rcvwnd 16384 len 0
TCP0: RETRANS timeout timer expired
TCP0: timeout #2 - timeout is 8000 ms, seq 3934657484
TCP: (179) -> 10.1.1.1(19401)
[repeating output omitted]
```

I stumbled on something else through error while testing this. I am glad I did. Consider the scenario according to this configuration.

<table>
<tr><th>R1</th><th>R2</th></tr>
<tr>
<td>
<pre><code class="language-c">router bgp 65001
 bgp log-neighbor-changes
 neighbor 10.2.2.2 remote-as 65002
 neighbor 10.2.2.2 update-source Loopback0
 neighbor 10.2.2.2 ttl-security hops 1
</code></pre>
</td>
<td>
<pre><code class="language-c">router bgp 65002
 bgp log-neighbor-changes
 neighbor 10.1.1.1 remote-as 65001
 neighbor 10.1.1.1 update-source Loopback0
 neighbor 10.1.1.1 ebgp-multihop 255
</code></pre>
</td>
</tr>
</table>

In this case, R1 only allows the eBGP peering if it receives a packet from R2 with a TTL of 254. Configuration R2 to send its packets with a TTL of 255 should work, right? Consider this output.

<pre><code class="language-c">R1#show bgp ipv4 unicast neighbors 10.2.2.2
BGP neighbor is 10.2.2.2,  remote AS 65002, external link
  BGP version 4, remote router ID 0.0.0.0
  <font color="red">BGP state = Idle</font>

[output omitted]

  Address tracking is enabled, the RIB does have a route to 10.2.2.2
  Connections established 3; dropped 3
  Last reset 00:03:25, due to Active open failed
  <font color="red">External BGP neighbor may be up to 1 hop away.</font>
  External BGP neighbor configured for connected checks (<font color="red">single-hop</font> no-disable-connected-check)
  Interface associated: (none) (peering address NOT in same link)
</code></pre>

Setting the `[MAX_HOPS]` attribute to 1 implies that a TTL of 254 is required to form a peering. Note that this is essentially a single-hop topology, and the neighbour output for R2 flagged it as such. To get the peering to form, I also need to use the `disable-connected-check` option in conjunction.

Here is the neighbour output after correcting the configuration.

<pre><code class="language-c">R1#show bgp ipv4 unicast neighbors 10.2.2.2
BGP neighbor is 10.2.2.2,  remote AS 65002, external link
  BGP version 4, remote router ID 10.2.2.2
  <font color="red">BGP state = Established, up for 00:00:09</font>

[output omitted]

  Address tracking is enabled, the RIB does have a route to 10.2.2.2
  Connections established 4; dropped 3
  Last reset 00:07:45, due to Active open failed
  <font color="red">External BGP neighbor may be up to 1 hop away.</font>
  External BGP neighbor NOT configured for connected checks (single-hop <font color="red">disable-connected-check</font>)
  Interface associated: (none) (peering address NOT in same link)
</code></pre>

# Summary

So after exploring the three options available to achieve eBGP multihop, we now understand the different operating models each option provides. In summarising the options through the remainder of this post, an attempt is made to provide valid use cases of each.

`ebgp-multihop [TTL]`:
- The router alters the TTL field in the IP header of the outgoing packets toward the peer address.
- Used to control how many hops across a multihop topology the participating routers allow a peering to occur.
- A viable use case may be multiple redundant multihop paths at the border or edge of a network that requires eBGP peering survivability between routers that are separated by various paths. The TTL field can be used to restrict the maximum amount of hops between peering routers.

`disable-connected-check`:
- The router does not alter the TTL of outgoing packets toward the peer address.
- Should a direct connection between the two peering routers fail, and they have a redundant path via an intermediate router as an alternate path between the two routers, the eBGP peering cannot re-form.
- A viable use case may be a requirement for peering when the routers are directly attached, but no peering should an indirect path between the routers be available. Note that if the `ebgp-multihop` option is in place and the incoming TTL is sufficient, this peering may re-establish.

`ttl-security hops [MAX_HOPS]`:
- The router sets the outgoing TTL of BGP packets to 255.
- Presumes the peering router is either implementing ttl-security or sending BGP packets with a TTL of 255.
- Uses the `[MAX_HOPS]` parameter configured as an offset from the originating TTL value of 255 to calculate an acceptable incoming TTL value.
- Simply drops the peering router's packets should the acceptable incoming TTL be breached.
- Setting a `[MAX_HOPS]` value of 1 implies an incoming TTL value must be >= 254, which is considered a single-hop scenario. The `disable-connected-check` option must also be used to complete a peering in this scenario.

Here is a handy table that helps me to compare the behaviour of each option.

| Option | Outgoing TTL | Incoming TTL | Usable Routes |
|--------|--------------|--------------|---------------|
| `ebgp-multihop 1` | 1 | - | Connected |
| `ebgp-multihop X` | X | - | All Routes (except default) |
| `disable-connected-check` | 1 | - | All Routes (except default) |
| `ttl-security hops 1` | 255 | >=254 | Connected |
| `ttl-security hops X` | 255 | >=255-X | All Routes (except default) |
| `ttl-security hops 1` + `disable-connected-check` | 255 | >=254 | All Routes (except default) |