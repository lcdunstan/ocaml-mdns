open Lwt
open V1_LWT
open Printf

let mdns_port = 5353

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
    let module Server = Make(struct
        let alloc () = Io_page.get 1
        let write (dest_ip,dest_port) txbuf =
          U.write ~source_port:mdns_port ~dest_ip:dest_ip ~dest_port udp (Cstruct.of_bigarray txbuf)
        let sleep t = OS.Time.sleep t
      end)
    in
    let server = Server.of_zonebuf zonebuf in
    Server.add_unique_hostname server (Dns.Name.string_to_domain_name "mirage-mdns.local") (S.ipv4 s |> S.IPV4.get_ip |> List.hd);
    S.listen_udpv4 s mdns_port (
      fun ~src ~dst ~src_port buf ->
        MProf.Trace.label "got udp";
        C.log_s c (sprintf "got udp from %s:%d" (Ipaddr.V4.to_string src) src_port)
        >>= fun () ->
        Server.process server ~src:(src,src_port) ~dst:(dst,mdns_port) (Cstruct.to_bigarray buf)
    );
    join [
      (
        Server.first_probe server >>= fun () ->
        Server.announce server ~repeat:3
      );
      S.listen s;
    ]
end

