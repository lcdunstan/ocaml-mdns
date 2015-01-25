open Lwt
open V1_LWT
open Printf

let mdns_port = 5353

module Main (C:CONSOLE) (K:KV_RO) (S:STACKV4) = struct

  module U = S.UDPV4

  let start_responder c k s hostnames =
    MProf.Trace.label "start_responder";
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
    let main_ip = S.ipv4 s |> S.IPV4.get_ip |> List.hd in
    let server = Server.of_zonebuf zonebuf in
    List.iter (fun hostname -> Server.add_unique_hostname server (Dns.Name.string_to_domain_name hostname) main_ip) hostnames;
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

  let start_resolver c s domains =
    MProf.Trace.label "start_resolver";
    let module D = Mdns_resolver_mirage.Make(OS.Time)(S) in
    let t = D.create s in
    C.log_s c "Started, will begin resolving shortly..." >>= fun () ->
    OS.Time.sleep 2.0 >>= fun () ->
    Lwt_list.iter_s (fun domain ->
      C.log_s c (sprintf "Begin: gethostbyname %s" domain)
      >>= fun () ->
      begin
        try_lwt
          D.gethostbyname t domain
          >>= fun rl ->
          printf "#rl: %d" (List.length rl);
          Lwt_list.iter_s (fun r ->
              C.log_s c (sprintf "Success: gethostbyname %s => %s" domain (Ipaddr.to_string r))
            ) rl
        with
        | Failure msg ->
          C.log_s c (sprintf "Failure: gethostbyname %s => %s" domain msg)
        | exn ->
          C.log_s c (sprintf "Failure: gethostbyname %s => exn" domain)
      end
      >>= fun () ->
      OS.Time.sleep 1.0
      ) domains

  let start c k s =
    let cmd_line =
      (* "-h abc.local -r foo.local -h def.local" *)
      OS.Start_info.((get ()).cmd_line)
    in
    C.log_s c (sprintf "cmd_line: %s\n%!" cmd_line) >>= fun () ->
    let args = Str.split (Str.regexp " ") cmd_line in
    let hostnames =
      let rec parse args acc =
        match args with
        | "-h" :: hostname :: tl -> hostname :: parse tl acc
        | hd :: tl -> parse tl acc
        | [] -> acc
      in
      parse args []
    in
    let domains =
      let rec parse args acc =
        match args with
        | "-r" :: hostname :: tl -> hostname :: parse tl acc
        | hd :: tl -> parse tl acc
        | [] -> acc
      in
      parse args []
    in
    C.log_s c (sprintf "hostnames: %s\n%!" (String.concat ", " hostnames)) >>= fun () ->
    C.log_s c (sprintf "domains: %s\n%!" (String.concat ", " domains)) >>= fun () ->
    join [
      start_responder c k s hostnames;
      start_resolver c s domains;
      S.listen s;
    ]
end

