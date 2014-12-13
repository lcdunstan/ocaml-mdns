
open OUnit2
open Printf

(* Adapted from ocaml-pcap/print/print.ml *)

cstruct ethernet {
    uint8_t        dst[6];
    uint8_t        src[6];
    uint16_t       ethertype
  } as big_endian

cstruct ipv4 {
    uint8_t        hlen_version;
    uint8_t        tos;
    uint16_t       len;
    uint16_t       id;
    uint16_t       off;
    uint8_t        ttl;
    uint8_t        proto;
    uint16_t       csum;
    uint8_t        src[4];
    uint8_t        dst[4]
  } as big_endian

cstruct udpv4 {
    uint16_t source_port;
    uint16_t dest_port;
    uint16_t length;
    uint16_t checksum
  } as big_endian

let load_pcap path =
  let fd = Unix.(openfile path [O_RDONLY] 0) in
  let buf = Bigarray.(Array1.map_file fd Bigarray.char c_layout false (-1)) in
  let buf = Cstruct.of_bigarray buf in
  let header, body = Cstruct.split buf Pcap.sizeof_pcap_header in
  match Pcap.detect header with
  | Some h ->
    Pcap.packets h body
  | None ->
    assert_failure "Not pcap format"

let load_packet path =
  match (load_pcap path) () with
  | Some (hdr, eth) ->
    assert_equal 0x0800 (get_ethernet_ethertype eth);
    let ip = Cstruct.shift eth sizeof_ethernet in
    let version = get_ipv4_hlen_version ip lsr 4 in
    assert_equal 4 version;
    assert_equal 17 (get_ipv4_proto ip);
    let udp = Cstruct.shift ip sizeof_ipv4 in
    let body = Cstruct.shift udp sizeof_udpv4 in
    Dns.Buf.of_cstruct body
  | None ->
    assert_failure "No packets"

let hexdump ibuf =
  let n = Dns.Buf.length ibuf in
  let obuf = Buffer.create (3 * n) in
  let rec acc i =
    Buffer.add_string obuf (sprintf "%.2x " (int_of_char ibuf.{i}));
    if i mod 16 = 15 then Buffer.add_char obuf '\n';
    if i < n - 1 then acc (i + 1);
  in
  if n >= 1 then acc 0;
  if n mod 16 != 15 then Buffer.add_char obuf '\n';
  Buffer.contents obuf

let load_file path =
  let ch = open_in path in
  let n = in_channel_length ch in
  let data = String.create n in
  really_input ch data 0 n;
  close_in ch;
  data

let allocfn () = Bigarray.Array1.create Bigarray.char Bigarray.c_layout 4096

open Dns.Packet
open Dns.Name

let tests =
  "Mdns_server" >:::
  [
    "process" >:: (fun test_ctxt ->
        let txlist = ref [] in
        let txfn addr buf =
          txlist := (addr, buf) :: !txlist;
          Lwt.return ()
        in
        let commfn = Mdns_server.({allocfn; txfn}) in
        let zonebuf = load_file "test_mdns.zone" in
        let process = Mdns_server.process_of_zonebufs [zonebuf] commfn in
        let raw = load_packet "q-A-AAAA.pcap" in
        let src = (Ipaddr.V4.of_string_exn "10.0.0.1", 5353) in
        let dst = (Ipaddr.V4.of_string_exn "10.0.0.2", 5353) in
        let thread = process ~src ~dst raw in
        Lwt_main.run thread;

        (* Verify the transmitted packet *)
        assert_equal 1 (List.length !txlist);
        let (txaddr, txbuf) = List.hd !txlist in
        let (txip, txport) = txaddr in
        assert_equal ~printer:(fun s -> s) "224.0.0.251" (Ipaddr.V4.to_string txip);
        assert_equal ~printer:string_of_int 5353 txport;
        let packet = parse txbuf in
        assert_equal ~msg:"id" 0 packet.id;
        assert_equal ~msg:"qr" Response packet.detail.qr;
        assert_equal ~msg:"opcode" Standard packet.detail.opcode;
        assert_equal ~msg:"aa" true packet.detail.aa;
        assert_equal ~msg:"tc" false packet.detail.tc;
        assert_equal ~msg:"rd" false packet.detail.rd;
        assert_equal ~msg:"ra" false packet.detail.ra;
        assert_equal ~msg:"rcode" NoError packet.detail.rcode;
        assert_equal ~msg:"#qu" 0 (List.length packet.questions);
        assert_equal ~msg:"#an" 1 (List.length packet.answers);
        assert_equal ~msg:"#au" 0 (List.length packet.authorities);
        assert_equal ~msg:"#ad" 0 (List.length packet.additionals);

        let a = List.hd packet.answers in
        assert_equal ~msg:"name" "mirage1.local" (domain_name_to_string a.name);
        assert_equal ~msg:"cls" RR_IN a.cls;
        (* TODO: assert_equal ~msg:"flush" true a.flush; *)
        assert_equal ~msg:"ttl" (Int32.of_int 120) a.ttl;
        match a.rdata with
        | A addr -> assert_equal ~msg:"A" "10.0.0.2" (Ipaddr.V4.to_string addr)
        | _ -> assert_failure "RR type";
    );
  ]


