
open OUnit2
open Printf
open Lwt

module StubIpv4 : V1_LWT.IPV4 with type ethif = unit = struct
  type error = [
    | `Unknown of string (** an undiagnosed error *)
    | `Unimplemented     (** operation not yet implemented in the code *)
  ]

  type ethif = unit (*StubEthif.t*)
  type 'a io = 'a Lwt.t
  type buffer = Cstruct.t
  type ipaddr = Ipaddr.V4.t
  type prefix = Ipaddr.V4.t
  type callback = src:ipaddr -> dst:ipaddr -> buffer -> unit Lwt.t

  type t = {
    ethif: ethif;
    mutable ip: Ipaddr.V4.t;
    mutable netmask: Ipaddr.V4.t;
    mutable gateways: Ipaddr.V4.t list;
  }

  let input_arpv4 t buf = return_unit

  let id { ethif; _ } = ethif

  let allocate_frame t ~dst ~proto =
    let ethernet_frame = Cstruct.create 4096 in
    let len = 1500 in
    (ethernet_frame, len)

  (* We write a whole frame, truncated from the right where the
   * packet data stops.
  *)
  let write t frame data =
    (*
    let ihl = 5 in (* TODO options *)
    let tlen = (ihl * 4) + (Cstruct.len data) in
    adjust_output_header ~tlen frame;
    Ethif.writev t.ethif [frame;data]
    *)
    return_unit

  let writev t ethernet_frame bufs =
    (*
    let tlen =
      Cstruct.len ethernet_frame
      - Wire_structs.sizeof_ethernet
      + Cstruct.lenv bufs
    in
    adjust_output_header ~tlen ethernet_frame;
    Ethif.writev t.ethif (ethernet_frame::bufs)
    *)
    return_unit

  let input t ~tcp ~udp ~default buf =
    (*
    (* buf pointers to to start of IPv4 header here *)
    let ihl = (Wire_structs.get_ipv4_hlen_version buf land 0xf) * 4 in
    let src = Ipaddr.V4.of_int32 (Wire_structs.get_ipv4_src buf) in
    let dst = Ipaddr.V4.of_int32 (Wire_structs.get_ipv4_dst buf) in
    let payload_len = Wire_structs.get_ipv4_len buf - ihl in
    (* XXX this will raise exception for 0-length payload *)
    let hdr = Cstruct.sub buf 0 ihl in
    let data = Cstruct.sub buf ihl payload_len in
    match Wire_structs.get_ipv4_proto buf with
    | 1 -> (* ICMP *)
      icmp_input t src hdr data
    | 6 -> (* TCP *)
      tcp ~src ~dst data
    | 17 -> (* UDP *)
      udp ~src ~dst data
    | proto ->
      default ~proto ~src ~dst data
    *)
    return_unit

  let connect ethif =
    let ip = Ipaddr.V4.any in
    let netmask = Ipaddr.V4.any in
    let gateways = [] in
    let t = { ethif; ip; netmask; gateways } in
    return (`Ok t)

  let disconnect _ = return_unit

  let set_ip t ip =
    t.ip <- ip;
    return_unit

  let get_ip t = [t.ip]

  let set_ip_netmask t netmask =
    t.netmask <- netmask;
    return_unit

  let get_ip_netmasks t = [t.netmask]

  let set_ip_gateways t gateways =
    t.gateways <- gateways;
    return_unit

  let get_ip_gateways { gateways; _ } = gateways

  let checksum buf bufl =
    (*
    let pbuf = Io_page.to_cstruct (Io_page.get 1) in
    let pbuf = Cstruct.set_len pbuf 4 in
    Cstruct.set_uint8 pbuf 0 0;
    fun frame bufs ->
      let frame = Cstruct.shift frame Wire_structs.sizeof_ethernet in
      Cstruct.set_uint8 pbuf 1 (Wire_structs.get_ipv4_proto frame);
      Cstruct.BE.set_uint16 pbuf 2 (Cstruct.lenv bufs);
      let src_dst = Cstruct.sub frame 12 (2 * 4) in
      Tcpip_checksum.ones_complement_list (src_dst :: pbuf :: bufs)
    *)
    0

  let get_source t ~dst:_ =
    t.ip
end


module MockUdpv4 : V1_LWT.UDPV4 with type ip = StubIpv4.t = struct
  type 'a io = 'a Lwt.t
  type buffer = Cstruct.t
  type ip = StubIpv4.t
  type ipaddr = Ipaddr.V4.t
  type ipinput = src:ipaddr -> dst:ipaddr -> buffer -> unit io
  type callback = src:Ipaddr.V4.t -> dst:Ipaddr.V4.t -> src_port:int -> Cstruct.t -> unit Lwt.t

  type error = [
    | `Unknown of string (** an undiagnosed error *)
  ]

  type t = {
    ip : ip;
  }

  let id {ip} = ip

  (* FIXME: [t] is not taken into account at all? *)
  let input ~listeners _t ~src ~dst buf =
    (*
    let dst_port = Wire_structs.get_udpv4_dest_port buf in
    let data =
      Cstruct.sub buf Wire_structs.sizeof_udpv4
        (Wire_structs.get_udpv4_length buf - Wire_structs.sizeof_udpv4)
    in
    match listeners ~dst_port with
    | None -> return_unit
    | Some fn ->
      let src_port = Wire_structs.get_udpv4_source_port buf in
      fn ~src ~dst ~src_port data
    *)
    return_unit

  let writev ?source_port ~dest_ip ~dest_port t bufs =
    (*
    begin match source_port with
      | None -> fail (Failure "TODO; random source port")
      | Some p -> return p
    end >>= fun source_port ->
    Ipv4.allocate_frame ~proto:`UDP ~dest_ip t.ip
    >>= fun (ipv4_frame, ipv4_len) ->
    let udp_buf = Cstruct.shift ipv4_frame ipv4_len in
    Wire_structs.set_udpv4_source_port udp_buf source_port;
    Wire_structs.set_udpv4_dest_port udp_buf dest_port;
    Wire_structs.set_udpv4_checksum udp_buf 0;
    Wire_structs.set_udpv4_length udp_buf
      (Wire_structs.sizeof_udpv4 + Cstruct.lenv bufs);
    let ipv4_frame =
      Cstruct.set_len ipv4_frame (ipv4_len + Wire_structs.sizeof_udpv4)
    in
    Ipv4.writev t.ip ipv4_frame bufs
    *)
    return_unit

  let write ?source_port ~dest_ip ~dest_port t buf =
    writev ?source_port ~dest_ip ~dest_port t [buf]

  let connect ip =
    return (`Ok { ip })

  let disconnect _ = return_unit
end


module StubTcpv4 : V1_LWT.TCPV4 with type ip = StubIpv4.t = struct
  type flow = unit (*Pcb.pcb*)
  type ip = StubIpv4.t
  type ipaddr = StubIpv4.ipaddr
  type buffer = Cstruct.t
  type +'a io = 'a Lwt.t
  type ipinput = src:ipaddr -> dst:ipaddr -> buffer -> unit io
  type t = ip (*Pcb.t*)
  type callback = flow -> unit Lwt.t

  type error = [
    | `Unknown of string
    | `Timeout
    | `Refused
  ]

  let error_message = function
    | `Unknown msg -> msg
    | `Timeout -> "Timeout while attempting to connect"
    | `Refused -> "Connection refused"

  let id t = t
  let get_dest t = (Ipaddr.V4.unspecified, 0)
  let read t = return `Eof
  let write t view = return (`Ok ())
  let writev t views = return (`Ok ())
  let write_nodelay t view = return_unit
  let writev_nodelay t views = return_unit
  let close t = return_unit
  let create_connection tcp (daddr, dport) = return (`Error `Refused)
  let input t ~listeners ~src ~dst buf = return_unit
  let connect ipv4 = return (`Ok ipv4)
  let disconnect _ = return_unit
end


module MockStack :
  (V1_LWT.STACKV4 with type console = unit and type netif = unit and type mode = unit)
= struct
  type +'a io = 'a Lwt.t
  type ('a,'b,'c) config = ('a,'b,'c) V1_LWT.stackv4_config
  type console = unit
  type netif = unit
  type mode = unit
  type id = (console, netif, mode) config
  type buffer = Cstruct.t
  type ipv4addr = Ipaddr.V4.t
  type tcpv4 = StubTcpv4.t
  type udpv4 = MockUdpv4.t
  type ipv4 = StubIpv4.t

  module UDPV4 = MockUdpv4
  module TCPV4 = StubTcpv4
  module IPV4  = StubIpv4

  type t = {
    id    : id;
    mode  : mode;
    (*
    c     : Console.t;
    netif : Netif.t;
    ethif : Ethif.t;
    *)
    ipv4  : ipv4;
    udpv4 : udpv4;
    tcpv4 : tcpv4;
    udpv4_listeners: (int, UDPV4.callback) Hashtbl.t;
    (*tcpv4_listeners: (int, (Tcpv4.flow -> unit Lwt.t)) Hashtbl.t;*)
  }

  type error = [
      `Unknown of string
  ]

  let id { id; _ } = id
  let tcpv4 { tcpv4; _ } = tcpv4
  let udpv4 { udpv4; _ } = udpv4
  let ipv4 { ipv4; _ } = ipv4

  let listen_udpv4 t ~port callback =
    Hashtbl.replace t.udpv4_listeners port callback

  let listen_tcpv4 t ~port callback =
    (*Hashtbl.replace t.tcpv4_listeners port callback*)
    ()

  let configure t config = return_unit

  let udpv4_listeners t ~dst_port =
    try Some (Hashtbl.find t.udpv4_listeners dst_port)
    with Not_found -> None

  (*
  let tcpv4_listeners t dst_port =
    try Some (Hashtbl.find t.tcpv4_listeners dst_port)
    with Not_found -> None
  *)

  let listen t = return_unit

  let connect id =
    let { V1_LWT.console = c; interface = netif; mode; _ } = id in
    let or_error fn t err =
      fn t
      >>= function
      | `Error _ -> fail (Failure err)
      | `Ok r -> return r
    in
    let ethif = () in
    or_error StubIpv4.connect ethif "ipv4"
    >>= fun ipv4 ->
    or_error MockUdpv4.connect ipv4 "udpv4"
    >>= fun udpv4 ->
    or_error StubTcpv4.connect ipv4 "tcpv4"
    >>= fun tcpv4 ->
    let udpv4_listeners = Hashtbl.create 7 in
    let t = { id; mode; (*c; netif; ethif;*) ipv4; tcpv4; udpv4;
              udpv4_listeners; (*tcpv4_listeners*) } in
    let _ = listen t in
    configure t t.mode
    >>= fun () ->
    return (`Ok t)

  let disconnect t = return_unit
end

let create_stack () =
  let config = {
    V1_LWT.name = "mockstack";
    console = (); interface = ();
    (*mode = `IPv4 (Ipaddr.V4.of_string_exn "10.0.0.2", Ipaddr.V4.of_string_exn "255.255.255.0", [Ipaddr.V4.of_string_exn "10.0.0.1"]);*)
    mode = ();
  } in
  match Lwt_main.run (MockStack.connect config) with
  | `Error e -> assert_failure "create_stack"
  | `Ok stackv41 -> stackv41

module MockTime : V1_LWT.TIME = struct
  type 'a io = 'a Lwt.t
  let sleep t = return_unit
end

module Resolver = Mdns_resolver_mirage.Make(MockTime)(MockStack)

let tests =
  "Mdns_resolver_mirage" >:::
  [
    "fail" >:: (fun test_ctxt ->
        let stack = create_stack () in
        let r = Resolver.create stack in
        let thread = Resolver.gethostbyname r "localhost" in
        try
          let _ = Lwt_main.run thread in
          assert_failure "No exception raised"
        with
        | Dns.Protocol.Dns_resolve_error x -> ()
        | _ -> assert_failure "Unexpected exception raised"
      );
  ]

