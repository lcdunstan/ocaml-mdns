open Lwt
open V1_LWT
open Printf

let listening_port = 5353

let red fmt    = sprintf ("\027[31m"^^fmt^^"\027[m")
let green fmt  = sprintf ("\027[32m"^^fmt^^"\027[m")
let yellow fmt = sprintf ("\027[33m"^^fmt^^"\027[m")
let blue fmt   = sprintf ("\027[36m"^^fmt^^"\027[m")

module Main (C:CONSOLE) (K:KV_RO) (S:STACKV4) = struct

  module U = S.UDPV4

  let start c k s =
    MProf.Trace.label "mDNS test";
    lwt zonebuf =
      K.size k "test.zone"
      >>= function
      | `Error _ -> fail (Failure "test.zone not found")
      | `Ok sz ->
        K.read k "test.zone" 0 (Int64.to_int sz)
        >>= function
        | `Error _ -> fail (Failure "test.zone error reading")
        | `Ok pages -> return (String.concat "" (List.map Cstruct.to_string pages))
    in
    let open Mdns_server in
    let udp = S.udpv4 s in
    let allocfn () = Io_page.get 1 in
    let txfn (dest_ip,dest_port) txbuf =
      U.write ~source_port:listening_port ~dest_ip:dest_ip ~dest_port udp (Cstruct.of_bigarray txbuf)
    in
    let sleepfn = Lwt_unix.sleep in
    let commfn = { allocfn; txfn; sleepfn } in
    let process = process_of_zonebuf zonebuf commfn in
    S.listen_udpv4 s listening_port (
      fun ~src ~dst ~src_port buf ->
        MProf.Trace.label "got udp";
        C.log_s c (sprintf "got udp from %s:%d" (Ipaddr.V4.to_string src) src_port)
        >>= fun () ->
        process ~src:(src,src_port) ~dst:(dst,listening_port) (Cstruct.to_bigarray buf)
    );
    S.listen s
end

