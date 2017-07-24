---
title: "Connected Static Routes"
date: 2017-07-23T17:27:30+10:00
tags: ["cisco"]
aliases: ["/2017/07/23/connected-static-routes/",
          "/post/connected-static-routes/"]
---

# Overview

Static routing is a simple concept to understand and implement, but how you configure the next hop or gateway of a static route can impact how other routing processes on the router deal with its presence.

A router must have a mechanism to know which local interface it should use to forward packets towards a destination prefix. When deploying static routes, an engineer has the choice to configure the outgoing interface explicitly or not. If you configure only a next IP address, the router must recurse that IP address to a matching locally addressed interface to find an outgoing interface.

> Of course, there are mechanisms to change this behaviour or allow matching a next hop IP address against a remote prefix, but these concepts are out of the scope of this post.

The recursion process is well understood, but there is a difference to how the route is programmed for forwarding when the next hop does not require recursion, that is, explicitly configuring the outgoing interface. These are programmed as 'directly connected' entries in the RIB and flagged as 'attached' in the FIB.

Consider the following table.

|Scenario| Next Hop Configuration                          | Recursion?         | Connected? |
|--------|-------------------------------------------------|--------------------|------------|
|1.      | Outgoing interface only                         | No                 | Yes        |
|2.      | Next hop IP address only                        | Yes                | No         |
|3.      | Both outgoing interface and next hop IP address | No                 | No         |

The following section qualifies this table to understand it, then focuses on the implications of connected static routes should they not be understood.

# Scenarios

The scenarios consider the following topology, in all cases configuring a static route on R1 towards the Loopback0 address of R2.

![Logical Topology](/images/connected-static-routes-logical.png)

## Scenario 1

This scenario describes the deployment of a static route specifying only the outgoing interface as the next hop toward the destination of the prefix, specifically:

`R1(config)#ip route 10.2.2.2 255.255.255.255 GigabitEthernet1.12`

Let's check the routing table first.

```
R1#show ip route 10.2.2.2
Routing entry for 10.2.2.2/32
  Known via "static", distance 1, metric 0 (connected)
  Routing Descriptor Blocks:
  * directly connected, via GigabitEthernet1.12
      Route metric is 0, traffic share count is 1
R1#
```

Note that the static prefix has entered the RIB as **directly connected** via interface GigabitEthernet1.12. The prefix is programmed into CEF as shown below with the **attached** flag.

```
R1#show ip cef 10.2.2.2/32 detail
10.2.2.2/32, epoch 2, flags [attached]
  Adj source: IP adj out of GigabitEthernet1.12, addr 10.2.2.2 7FF9EA823370
    Dependent covered prefix type adjfib, cover 0.0.0.0/0
  attached to GigabitEthernet1.12
```

As an aside, shown below are the internal details of the CEF entry as programmed. Notice the sources of information used to complete the entry includes not just the RIB information, but also from the Adj process, or gleaned ARP information.

```
R1#show ip cef 10.2.2.2/32 internal
10.2.2.2/32, epoch 2, flags [att], RIB[S], refcnt 6, per-destination sharing
  sources: RIB, Adj
  feature space:
    IPRM: 0x00048004
    Broker: linked, distributed at 4th priority
  subblocks:
    Adj source: IP adj out of GigabitEthernet1.12, addr 10.2.2.2 7FF9EA823370
      Dependent covered prefix type adjfib, cover 0.0.0.0/0
  ifnums:
    GigabitEthernet1.12(11): 10.2.2.2
  path list 7FF9F12C1318, 3 locks, per-destination, flags 0x49 [shble, rif, hwcn]
    path 7FF9F1A69E38, share 1/1, type attached host, for IPv4
      attached to GigabitEthernet1.12, IP adj out of GigabitEthernet1.12, addr 10.2.2.2 7FF9EA823370
  output chain:
    IP adj out of GigabitEthernet1.12, addr 10.2.2.2 7FF9EA823370
R1#
```

As the next hop was specified as an outgoing interface only, R1 sent an ARP discovery packet to glean layer 2 information of the next hop. In this scenario, R1 sent the ARP packet toward the destination prefix itself, in our case 10.2.2.2/32. See the output below from an ARP debug after configuration of the route.

```
IP ARP: creating incomplete entry for IP address: 10.2.2.2 interface GigabitEthernet1.12
IP ARP: sent req src 10.12.1.1 0050.56a7.a22e,
                 dst 10.2.2.2 0000.0000.0000 GigabitEthernet1.12
IP ARP: rcvd rep src 10.2.2.2 0050.56a7.e4ed, dst 10.12.1.1 GigabitEthernet1.12
```

The process works, and a CEF entry is complete in this case due to Proxy ARP support on R2. The ARP and CEF entries would exist but would be incomplete should Proxy ARP be disabled on GigabitEthernet1.12 on R2.

## Scenario 2

This scenario describes the deployment of a static route specifying only the next hop IP address of the destination of the prefix, specifically:

`R1(config)#ip route 10.2.2.2 255.255.255.255 10.12.1.2`

Let's recheck the routing table.

```
R1#show ip route 10.2.2.2
Routing entry for 10.2.2.2/32
  Known via "static", distance 1, metric 0
  Routing Descriptor Blocks:
  * 10.12.1.2
      Route metric is 0, traffic share count is 1
R1#
```

This time the RIB prefix is not shown as directly connected. This because recursion needs to occur on R1 to identify its outgoing interface, as shown in the corresponding CEF entry.

```
R1#show ip cef 10.2.2.2/32 detail
10.2.2.2/32, epoch 2
  recursive via 10.12.1.2
    attached to GigabitEthernet1.12
R1#
```

Presuming ARP information can be gleaned for 10.12.1.2, all is well, and nothing is surprising about this result.

## Scenario 3

This scenario describes the deployment of a static route specifying both the outgoing interface and the next hop IP address of the destination of the prefix, specifically:

`R1(config)#ip route 10.2.2.2 255.255.255.255 GigabitEthernet1.12 10.12.1.2`

Let's recheck the routing table.

```
R1#show ip route 10.2.2.2  
Routing entry for 10.2.2.2/32
  Known via "static", distance 1, metric 0
  Routing Descriptor Blocks:
  * 10.12.1.2, via GigabitEthernet1.12
      Route metric is 0, traffic share count is 1
R1#
```

Curiously, although we specify the outgoing interface, the RIB prefix is still not flagged as directly connected. In Scenario 2 we felt this was because no outgoing interface was specified and recursion was required on R1 to identify its outgoing interface. However, recursion is also not needed in this scenario, as shown from the CEF entry below.

```
R1#show ip cef 10.2.2.2/32 detail
10.2.2.2/32, epoch 2
  nexthop 10.12.1.2 GigabitEthernet1.12
R1#
```

I am not entirely sure why Scenario 3 does not also see the prefix flagged as directly connected. Thinking about why (good practice), I can only speculate that in Scenario 1, next hop resolution was entirely dependent on the outgoing interface. In Scenario 3, there is no dependency, and it is simply a matter that R1 has all of the required information so that the prefix can be immediately a candidate for the RIB.

# Implications

> This section only considers the result from Scenario 1, as its prefix was flagged as directly connected.

Should R1 also be running a distance vector routing protocol (i.e., EIGRP, RIPv2), the engineer must be aware of what may happen when a static route is flagged in the RIB as directly connected.

Distance vector protocols are link specific. They form a list, or a vector, of directly connected links and send the vector to their connected neighbours. If they have received a list from a neighbour, they increase the hop count (or metric depending on the protocol and its algorithm) and send them along with their list of directly connected links.

The next sections steps through two examples for RIPv2 and EIGRP to see how they behave with a static route flagged as directly connected.

## RIPv2 Example

If we were to run RIPv2 between R1 and R2, with both routers replicating a common scenario of simply enabling the process on all connected links (network 0.0.0.0), and then we reproduce a connected static route as we described in Scenario 1, what would happen? Let's see!

R1 configured is as follows. R2 has an identical configuration.

```
router rip
 version 2
 network 0.0.0.0
 no auto-summary
```

On R2, we verify that it has received any RIP prefixes. We would expect to see a RIB entry for at least the Loopback0 address of R1.

```
R2#show ip route rip
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
       D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 
       N1 - OSPF NSSA external type 1, N2 - OSPF NSSA external type 2
       E1 - OSPF external type 1, E2 - OSPF external type 2
       i - IS-IS, su - IS-IS summary, L1 - IS-IS level-1, L2 - IS-IS level-2
       ia - IS-IS inter area, * - candidate default, U - per-user static route
       o - ODR, P - periodic downloaded static route, H - NHRP, l - LISP
       a - application route
       + - replicated route, % - next hop override

Gateway of last resort is not set

      10.0.0.0/8 is variably subnetted, 4 subnets, 2 masks
R        10.1.1.1/32 [120/1] via 10.12.1.1, 00:00:07, GigabitEthernet1.12
R        10.13.1.0/24 [120/1] via 10.12.1.1, 00:00:07, GigabitEthernet1.12
R2#
```

Let's now introduce a new static route, to a made up destination of 100.100.100.0/24, specifying GigabitEthernet1.13 only as its next hop.

> Note that GigabitEthernet1.13 is introduced as a new dummy interface in up/up state toward a hypothetical R3 for use as the static route outgoing interface. We, of course, could not use GigabitEthernet1.12 as the outgoing interface, as split-horizon rules would prevent R1 advertising the prefix across the same outgoing interface used to reach the destination.

```
R1#configure terminal
Enter configuration commands, one per line.  End with CNTL/Z.
R1(config)#ip route 100.100.100.0 255.255.255.0 GigabitEthernet1.13
R1(config)#end
%SYS-5-CONFIG_I: Configured from console by console
R1#
R1#show ip route 100.100.100.0
Routing entry for 100.100.100.0/24
  Known via "static", distance 1, metric 0 (connected)
  Redistributing via rip
  Advertised by rip
  Routing Descriptor Blocks:
  * directly connected, via GigabitEthernet1.13
      Route metric is 0, traffic share count is 1
R1#
```

So we can see that the prefix has gone into the RIB as a directly connected prefix as described in Scenario 1. So what RIP received entries do we now see in the RIB of R2?

```
R2#show ip route rip
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
       D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 
       N1 - OSPF NSSA external type 1, N2 - OSPF NSSA external type 2
       E1 - OSPF external type 1, E2 - OSPF external type 2
       i - IS-IS, su - IS-IS summary, L1 - IS-IS level-1, L2 - IS-IS level-2
       ia - IS-IS inter area, * - candidate default, U - per-user static route
       o - ODR, P - periodic downloaded static route, H - NHRP, l - LISP
       a - application route
       + - replicated route, % - next hop override

Gateway of last resort is not set

      10.0.0.0/8 is variably subnetted, 5 subnets, 2 masks
R        10.1.1.1/32 [120/1] via 10.12.1.1, 00:00:23, GigabitEthernet1.12
R        10.13.1.0/24 [120/1] via 10.12.1.1, 00:00:23, GigabitEthernet1.12
      100.0.0.0/24 is subnetted, 1 subnets
R        100.100.100.0 [120/1] via 10.12.1.1, 00:00:23, GigabitEthernet1.12
R2#
```

There it is, in the routing table of R2, and no redistribute required on R1 because of the directly connected flag.

## EIGRP Example

In similar fashion to the RIPv2 scenario, in this example, EIGRP is configured between R1 and R2, with both routers again replicating a typical scenario of enabling the process on all connected links (network 0.0.0.0). The result of reproducing a connected static route as described in Scenario 1 has different implications due to the way in which EIGRP treats internal versus external prefixes.

R1 configured is as follows. R2 has an identical configuration.

```
router eigrp 100
 network 0.0.0.0
```

On R2, we verify that it has received any RIP prefixes. We would expect to see a RIB entry for the Loopback0 address of R1.

```
R2#show ip route eigrp
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
       D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 
       N1 - OSPF NSSA external type 1, N2 - OSPF NSSA external type 2
       E1 - OSPF external type 1, E2 - OSPF external type 2
       i - IS-IS, su - IS-IS summary, L1 - IS-IS level-1, L2 - IS-IS level-2
       ia - IS-IS inter area, * - candidate default, U - per-user static route
       o - ODR, P - periodic downloaded static route, H - NHRP, l - LISP
       a - application route
       + - replicated route, % - next hop override

Gateway of last resort is not set

      10.0.0.0/8 is variably subnetted, 5 subnets, 2 masks
D        10.1.1.1/32 [90/130816] via 10.12.1.1, 00:00:27, GigabitEthernet1.12
D        10.13.1.0/24 [90/3072] via 10.12.1.1, 00:00:27, GigabitEthernet1.12
R2#
```

Let's now re-introduce the new static route on R1 as per the RIPv2 example, again to the same made up destination of 100.100.100.0/24 specifying GigabitEthernet1.13 only as its next hop. Taking a look at R2's view of things, do we again see the 100.100.100.0/24 prefix advertised by R1 in the RIB?

```
R2#show ip route eigrp
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
       D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 
       N1 - OSPF NSSA external type 1, N2 - OSPF NSSA external type 2
       E1 - OSPF external type 1, E2 - OSPF external type 2
       i - IS-IS, su - IS-IS summary, L1 - IS-IS level-1, L2 - IS-IS level-2
       ia - IS-IS inter area, * - candidate default, U - per-user static route
       o - ODR, P - periodic downloaded static route, H - NHRP, l - LISP
       a - application route
       + - replicated route, % - next hop override

Gateway of last resort is not set

      10.0.0.0/8 is variably subnetted, 5 subnets, 2 masks
D        10.1.1.1/32 [90/130816] via 10.12.1.1, 00:00:15, GigabitEthernet1.12
D        10.13.1.0/24 [90/3072] via 10.12.1.1, 00:00:15, GigabitEthernet1.12
R2#
```

It is not there! In this case, EIGRP has some smarts to ensure the directly connected static route is not automatically advertised as a component of the blanket 'match all' network statement. The same result is still possible, but it requires a specific network statement for the prefix.

> Note that the network statement must match the prefix exactly, including the correct subnet mask length in the wildcard, for EIGRP to advertise the prefix.

Let's try this by updating R1 with the necessary network statement.

```
R1#configure terminal
R1(config)#router eigrp 100
R1(config-router)#network 100.100.100.0 0.0.0.255
R1(config-router)#end
R1#
%SYS-5-CONFIG_I: Configured from console by console
R1#  
```

What does R2 see now?

```
R2#show ip route eigrp
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
       D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 
       N1 - OSPF NSSA external type 1, N2 - OSPF NSSA external type 2
       E1 - OSPF external type 1, E2 - OSPF external type 2
       i - IS-IS, su - IS-IS summary, L1 - IS-IS level-1, L2 - IS-IS level-2
       ia - IS-IS inter area, * - candidate default, U - per-user static route
       o - ODR, P - periodic downloaded static route, H - NHRP, l - LISP
       a - application route
       + - replicated route, % - next hop override

Gateway of last resort is not set

      10.0.0.0/8 is variably subnetted, 5 subnets, 2 masks
D        10.1.1.1/32 [90/130816] via 10.12.1.1, 00:05:27, GigabitEthernet1.12
D        10.13.1.0/24 [90/3072] via 10.12.1.1, 00:05:27, GigabitEthernet1.12
      100.0.0.0/24 is subnetted, 1 subnets
D        100.100.100.0 [90/3072] via 10.12.1.1, 00:00:21, GigabitEthernet1.12
R2#
```

R2 now sees the prefix advertised, noticeably as an internal EIGRP route. Although EIGRP handles the scenario in a safer method than RIPv2 by ensuring you must assert your intention with a specific configuration, it is still a neat trick of inject the static route into the dynamic routing process without redistribution.

# Summary

The result of this post is neither a good or a bad thing. It is an awareness thing. As an engineer, one must be aware of the impact of configuration being applied to other processes also running on the router.

Distance vector routing protocols are common because they are simple to understand, simple to configure, have open standard variants, and supported on many home grade and legacy equipment. Generic, loose and poorly considered deployments as shown in this post are common. The same rhetoric applies for static routing. It is a handy and straightforward tool to alter local traffic flows temporarily. Engineers often throw them in to achieve a quick or temporary outcome without much though. If a situation like this were to occur, and the prefix was all of a sudden unwittingly advertised into a distance vector IGP, the routing topology is now not just altered locally but can have wider, and possibly detrimental, effects.

Alternatively, who is to say that your CCIE lab cannot ask you to make sure your static route enters the RIB without redistribution or altering the borders of the routing domain? Understanding even the simplest behaviours may just score you the points.