= Plan =

* Done: Write a Unix-only multicast example with https://github.com/vbmithr/ocaml-sockopt (e.g. via https://github.com/vbmithr/ocaml-llnet)
* Done: Add Lwt
* Done: test UDP multicast receive on Mirage+Xen
* test UDP multicast transmit on Mirage+Xen

* Extend tcpip-stack-direct with support for UDP multicast
** Ipv4.allocate_frame needs an option to override the default IP TTL
** Done: Ipv4.Routing.destination_mac needs to recognise a multicast IP address (e.g. 224.0.0.251) and map it to the corresponding MAC address (e.g. 01:00:5E:00:00:FB)
** Unix only?: Ipv4 needs an API to join/leave multicast groups (?)
** UDP "sockets" need to receive messages transmitted by the same Unikernel

* Extend tcpip-stack-socket with support for UDP multicast
** Add dependency on Sockopt (add to opam-repository first) or include the relevant code directly
** Tcpip_stack_socket.listen_udpv4 needs an option for IP_ADD_MEMBERSHIP, IP_MULTICAST_IF, IP_DROP_MEMBERSHIP
** Udpv4_socket.get_udpv4_listening_fd needs an option for SO_REUSEADDR

* Extend mirage-net-unix with support for Ethernet multicast
** ?
* Extend mirage-net-xen with support for Ethernet multicast
** ?

* Done: Test a minimal legacy resolver for mDNS
* Write a minimal responder for mDNS
* ? Write tests for mirage-tcpip UDP multicast
* ? Define a layer for selecting either ocaml-sockopt + Lwt_unix or the mirage-tcpip equivalent
* ? Write tests for the wrapper layer
* Write a full mDNS library, example server and client


= References =

Relevant RFCs:
* https://tools.ietf.org/html/rfc6762 - Multicast DNS
* https://tools.ietf.org/html/rfc1034 - DNS concepts
* https://tools.ietf.org/html/rfc1035 - DNS specification
* https://tools.ietf.org/html/rfc4033 - DNSSEC concepts
* https://tools.ietf.org/html/rfc4034 - DNSSEC RRs
* https://tools.ietf.org/html/rfc1112 - IPv4 multicast
* https://tools.ietf.org/html/rfc3171 - IPv4 multicast IANA

= ocaml-dns =

Structure of ocaml-dns server (high-level layers first):
* Dns.Lwt.Dns_server_unix: loads a zone file, listens on a socket and answers queries
* Dns.Lwt.Dns_server: consumes a query message and produces a response message
* Dns.Query: looks up the answer for a query in the Loader trie and produces a response
* Dns.Zone: uses Zone_lexer and Zone_parser to load a zone file into Loader.state
* Dns.Zone_lexer: ocamllex lexer for DNS Master zone file format
* Dns.Zone_parser: ocamlyacc parser for DNS Master zone file format
* Dns.Loader: stores resource records in a trie indexed by domain name, and provides add_* functions
* Dns.RR: resource record data types

Resolver:
* Dns.Mldig: clone of the standard "dig" command-line tool (uses Dns_resolver_unix)
* Dns.Lwt.Dns_resolver_unix: loads a resolv.conf, creates a socket, sends a query and decodes the response (gethostbyname, gethostbyaddr)
* Dns.Async.Dns_resolver_unix: Async version
* Dns.Mirage.Dns_resolver_mirage: Mirage version
* Dns.Lwt.Dns_resolver: LWT-based DNS resolver
* Dns.Async.Dns_resolver: Async.Std-based DNS resolver
* Dns.Resolvconf: parser for "/etc/resolv.conf" configuration file format

Common and low-level modules:
* Dns.Protocol: encapsulates Packet parsing/marshaling functions into modules called Client and Server
* Dns.Packet: defines DNS protocol constants, packet types, and binary/text serialisation functions
* Dns.Hashcons: data structure used by Dns.Name for "interning" strings and lists of strings
* Dns.Trie: trie data structure specialised for storing domain names
* Dns.Name: defines types for domain names and binary serialisation functions
* Dns.Operator: defines infix operators for bitwise integer operations, plus charstr
* Dns.Buf: byte array

Changes to ocaml-dns
* Do not process queries for *.local


= mDNS Key Concepts =

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


= DNS vs mDNS =

(see also RFC 6762 section 19)

Unicast vs multicast (usually)
Port 53 vs port 5353
(3) Any vs *.local
(4) Any vs *.254.169.in-addr.arpa
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



