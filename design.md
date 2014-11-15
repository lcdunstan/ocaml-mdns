# Plan

- [x] Write a Unix-only multicast example with https://github.com/vbmithr/ocaml-sockopt (e.g. via https://github.com/vbmithr/ocaml-llnet)
- [x] Add Lwt
- [x] test UDP multicast receive on Mirage+Xen
- [ ] test UDP multicast transmit on Mirage+Xen

- [ ] Extend tcpip-stack-direct with support for UDP multicast
  - [ ] Ipv4.allocate_frame needs an option to override the default IP TTL
  - [x] Ipv4.Routing.destination_mac needs to recognise a multicast IP address (e.g. 224.0.0.251) and map it to the corresponding MAC address (e.g. 01:00:5E:00:00:FB)
  - [ ] Unix only?: Ipv4 needs an API to join/leave multicast groups (?)
  - [ ] UDP "sockets" need to receive messages transmitted by the same Unikernel

- [ ] Extend tcpip-stack-socket with support for UDP multicast
  - [ ] Add dependency on Sockopt (add to opam-repository first) or include the relevant code directly
  - [ ] Tcpip_stack_socket.listen_udpv4 needs an option for IP_ADD_MEMBERSHIP, IP_MULTICAST_IF, IP_DROP_MEMBERSHIP
  - [ ] Udpv4_socket.get_udpv4_listening_fd needs an option for SO_REUSEADDR

- [ ] Extend mirage-net-unix with support for Ethernet multicast
  - [ ] ?
- [ ] Extend mirage-net-xen with support for Ethernet multicast
  - [ ] ?

- [x] Test a minimal legacy resolver for mDNS
- [ ] Write a minimal responder for mDNS
- [ ] ? Write tests for mirage-tcpip UDP multicast
- [ ] ? Define a layer for selecting either ocaml-sockopt + Lwt_unix or the mirage-tcpip equivalent
- [ ] ? Write tests for the wrapper layer
- [ ] Write a full mDNS library, example server and client


# References

Relevant RFCs:
- https://tools.ietf.org/html/rfc6762 - Multicast DNS
- https://tools.ietf.org/html/rfc1034 - DNS concepts
- https://tools.ietf.org/html/rfc1035 - DNS specification
- https://tools.ietf.org/html/rfc4033 - DNSSEC concepts
- https://tools.ietf.org/html/rfc4034 - DNSSEC RRs
- https://tools.ietf.org/html/rfc1112 - IPv4 multicast
- https://tools.ietf.org/html/rfc3171 - IPv4 multicast IANA

# ocaml-dns

## Static structure

Structure of ocaml-dns server (high-level layers first):
- Dns.Lwt.Dns_server_unix: loads a zone file, listens on a socket and answers queries
- Dns.Lwt.Dns_server: consumes a query message and produces a response message
- Dns.Query: looks up the answer for a query in the Loader trie and produces a response
- Dns.Zone: uses Zone_lexer and Zone_parser to load a zone file into Loader.state
- Dns.Zone_lexer: ocamllex lexer for DNS Master zone file format
- Dns.Zone_parser: ocamlyacc parser for DNS Master zone file format
- Dns.Loader: stores resource records in a trie indexed by domain name, and provides add_\* functions
- Dns.RR: resource record data types

Resolver:
- Dns.Mldig: clone of the standard "dig" command-line tool (uses Dns_resolver_unix)
- Dns.Lwt.Dns_resolver_unix: loads a resolv.conf, creates a socket, sends a query and decodes the response (gethostbyname, gethostbyaddr)
- Dns.Async.Dns_resolver_unix: Async version
- Dns.Mirage.Dns_resolver_mirage: Mirage version
- Dns.Lwt.Dns_resolver: LWT-based DNS resolver
- Dns.Async.Dns_resolver: Async.Std-based DNS resolver
- Dns.Resolvconf: parser for "/etc/resolv.conf" configuration file format

Common and low-level modules:
- Dns.Protocol: encapsulates Packet parsing/marshaling functions into modules called Client and Server
- Dns.Packet: defines DNS protocol constants, packet types, and binary/text serialisation functions
- Dns.Hashcons: data structure used by Dns.Name for "interning" strings and lists of strings
- Dns.Trie: trie data structure specialised for storing domain names
- Dns.Name: defines types for domain names and binary serialisation functions
- Dns.Operator: defines infix operators for bitwise integer operations, plus charstr
- Dns.Buf: byte array

Changes to ocaml-dns
- Do not process queries for \*.local

## Resolver algorithm

- Platform-specific code defines the commfn record containing txfn, rxfn, timerfn and cleanfn
- Call Dns.Packet.create to build a query packet
- Dns_resolver.resolve calls send_pkt to do the work and catches any exceptions
- send_pkt calls Dns.Protocol.Client.marshal to get the bytes for the query
- A Lwt.wait pair is created for synchronisation
- Two threads are created in parallel: send and receive
- The send thread calls txfn (e.g. sendto) to send the message, then sleeps for 5 seconds
- If the sleep completes then a time-out Error is signalled
- The receive thread calls rxfn (e.g. recvfrom) to wait for a response
- If the receive fails, or if decoding the response fails, then an Error is signalled
- Otherwise, if the response is decoded successfully then an Answer is signalled
- send_pkt waits for an Answer, or for both threads to return Error


# mDNS

## mDNS Key Concepts

(2) UDP Port 5353
(2) Shared vs unique resource record sets
(3) mDNS as a fall-back DNS
(5.1) Legacy one-shot
(5.2) Continuous queries
(5.2) Re-query after % of TTL, randomised
(5.3) Multiple questions per query
(5.4) Requesting unicast responses
(5.5) Response delays
(6.1) Negative responses (NSEC) for unique (owned) RR sets
(6.2) Grouping of address records by interface, and optionally by address family
(6.3) Multi-question queries, with delays
(6.4) Response aggregation
(6.5) Wildcard (ANY) queries
(6.6) Observation of peer responses -> conflict resolution / announcement (TTL different)
(6.7) Legacy unicast, source port != 5353, TTL <= 10, !cache flush
(7.1) Known answer suppression (shared RR sets)
(7.2) Multi-packet (TC) known answer suppression, with delays
(7.3) Duplicate QM question suppression (question sniffing)
(7.4) Duplicate answer suppression during delay (answer sniffing)
(8.1) Probing for ownership of unique RRs
(8.2) Simultaneous probe tiebreaking, lexicographical ordering
(8.3) Announcing, e.g. on interface start-up (after successful probing)
(8.4) Updating, i.e. repeating announcements when data changes
(9) Conflict resolution, unique name generation, limit to 60 seconds
(10) Host names TTL=120s, other TTL=75s
(10.1) Goodbye packets (TTL=0)
(10.2) Cache flush announcements (unique), 1-second delay, bridge handling
(10.3) Cache flush on topology change
(10.4) Cache flush on failure indication, e.g ARP time-out
(10.5) Passive observation of failures (sniffing query time-outs)
(11) Response IP TTL should be 255
(11) Source address check (accept local only)
(12) No NS or SOA records
(14) Dot-local hostname should be valid for all interface
(15) Should use SO_REUSEADDR / SO_REUSEPORT
(16) UTF-8, no BOM
(18.14) Name compression


## DNS vs mDNS

(see also RFC 6762 section 19)

Unicast vs multicast (usually)
Port 53 vs port 5353
(3) Any vs \*.local
(4) Any vs \*.254.169.in-addr.arpa
(5.3) One question per query vs allows multiple questions per query
(5.4 / 18.12) 16-bit QCLASS vs 15-bit qclass plus unicast response bit
(6.1) different NSEC semantics, stored vs synthesised NSEC, NSEC bit
(6.1) full vs restricted NSEC format
(6.1) RR type <= 65535 vs RR type <= 255
(6.4) No aggregation vs response aggregation
(6.5) ANY subset vs ANY all matches
(7.1) No known answers in query vs known answers in query
(10.2 / 18.13) 16-bit RR CLASS vs 15-bit rrclass plus cache flush bit (for standard RR types only)
(12) Subdomains vs no subdomains
(12) SOA vs no SOA
(12) NS vs no NS
(16) Punycode vs UTF-8
(17) Jumboframes not supported vs packets up to 9000 bytes allowed
(18.3) A few opcodes vs opcode zero only
(18.4) AA optional in response vs AA always 1 in responses
(18.5) TC allowed for responses vs TC always zero for responses (except legacy)
(18.6) RD supported vs RD always zero
(18.7) RA supported vs RA always zero
(18.9) AD supported (DNSSEC) vs AD always zero
(18.10) CD supported (DNSSEC) vs CD always zero
(18.11) RCODE used to signal errors vs RCODE always zero (for multicast)
(18.14) Compression not used for SRV vs compression supported for SRV
(19) Query ID field echoed vs query ID field ignored (except legacy)
(19) Question repeated in response vs question repeat not required

## mDNS Responder Algorithm

- Configuration: preferred unique host name(s)
- Configuration: zone file (everything except for the host name)
  - Authoritative only (6.0.1)
  - Need to mark record "sets" as either "unique" or "shared" (2)
- Start listening for UDP packets on port 5353
  - Ideally on both IPv4 and IPv6
- Probing stage for unique host name (8)
  - Not required for e.g. PTR (8.1.9)
  - Delay for 0-250 ms (8.1)
  - Send probe queries for all records that are unique on the local link (8.1)
    - Query class Internet (8.1.1)
    - Query type ANY (8.1.1)
    - Use a single multi-question query in preference to multiple messages (8.1.2)
    - QU questions (8.1.6)
    - Set the unicast response bit (8.1)
    - Populate the Authority Section with proposed data of all types (8.2)
  - Wait 250 ms (8.1.3)
  - Send a second probe (8.1.4)
  - Wait 250 ms (8.1.4)
  - Send a third probe (8.1.4)
  - Wait 250 ms (8.1.4)
  - If no conflicts occurred
    - Mark the unique records as finished probing (8.1.4)
    - Continue to Announcing (8.3)
  - Else if a conflict occurs
    - Choose new name(s) for the applicable RR(s) (8.1.7)
    - If 15 conflicts have occured in the last 10 seconds (8.1.8)
      - Delay 5 seconds (8.1.8)
    - Restart probe (8.1.8)
- Announcing stage (8.3)
  - Send an unsolicited multicast response with all records that completed probing (8.3)
  - Also include shared records (8.3.2)
  - For unique records, set the cache flush bit (8.3.3)
  - Wait for 1 second (8.3.4)
  - Resend the same announcemnt (8.3.4)
  - Optional: send additional announcements (8.3.4)
    - Delay between responses must double each time (8.3.4)
- When a probe is received and matches one of our unique records
  - Delay until at least 250 ms after the last time the response record was seen (6.0.14)
  - TODO
- When any request is received (includes probes)
  - If the source port is not 5353 (6.7)
    - TODO (legacy)
    - Response should be via unicast (6.7)
    - RR TTL should be <= 10 seconds (6.7)
  - If the request contains known answers (7.1)
    - If a known answer matches but has a RR TTL >= DB RR TTL / 2 (7.1)
      - Exclude that record from matches (7.1)
    - Else if a known answer matches but has RR TTL < DB RR TTL / 2 (7.1)
      - Act as though the known answer was not present in the request (7.1)
    - Else if a known answer doesn't match, ignore it (7.1)
  - If it does not match any record
    - Ignore it
  - If it matches a unique record, ignoring A vs AAAA (and there are no other questions in the request (6.0.10, 6.3))
    - Else if the received request is a probe (Authority Section) (8.2)
      - If the received probe is lexicographically greater than our data (8.2)
        - Delay 1 second (8.2)
        - Restart probing (8.2)
      - Else ignore the probe
    - Else if the unique record has finished probing (6.0.8)
      - If a response for this record was already sent in the last 1 second (6.0.14)
        - Do nothing
      - Else
        - Send the response immediately (6.0.7)
        - For an A request, send A plus NSEC AAAA (6.0.3, 6.1.3, 6.2.3)
          - Include all IP addresses valid on that interface if multi-homed (6.2.1)
        - For an AAAA request, send NSEC AAAA (6.0.3, 6.1.3)
    - Else if probing in progress then do nothing ?
  - Else (if it matches a shared record) (6.0.9)
    - If the TC bit is set (6.3)
      - Delay for 400-500 ms (6.3)
      - Aggregate responses during the delay period (6.4)
    - Else if not TC
      - Delay for 20-120 ms (6.3)
      - Aggregate responses during the delay period, for up to an additional 500 ms (6.4)
    - Duplicate answer suppression? (7.4)
    - Send the response(s)
- When any response is received
  - Ignore questions (6.0.4)
  - Ignore known answers (7.1)
  - If is a multicast message
    - If it matches a record in our database by (name, rrtype, rrclass) (6.6)
      - Record the timestamp of when the response was seen (6.0.14)
      - If the rdata matches our database (6.6)
        - If the TTL in the received response is less than half the TTL in the DB (6.6)
          - Send a response with the correct TTL (6.6)
        - Else do nothing (6.6, 7.4)
      - Else if the rdata does NOT match our database (6.6)
        - If the record is shared (6.6)
          - Do nothing (6.6)
        - Else if the record is unique (6.6)
          - Conflict resolution (6.6, 9)
    - Else if there is no match then ignore it
  - Else if it is a unicast message (i.e. not sent to 224.0.0.251)
    - If it answers a query that we sent in the last 2 seconds, and we requested a unicast response (6)
      - Process it
    - Else
      - Ignore it (6.0.13)
- When the IPv4 address changes
  - Update the A record for the host name
  - TODO


 vi:ft=markdown:sw=2
